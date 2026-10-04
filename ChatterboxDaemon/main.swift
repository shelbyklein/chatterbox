import Foundation
import Darwin

var daemon:RuntimeServer?
var context:DaemonContext?
Task { @MainActor in
    do {
        try RuntimePreferences.load()
        #if DEBUG
        if RuntimePaths.data.path.hasPrefix("/tmp/golem-"), let fake=ProcessInfo.processInfo.environment["FAKE_PROVIDER"] {
            AppPreferences.defaults.setVolatileDomain(["claudePath":fake,"codexPath":fake,"easyCLIProxyEnabled":false,"remoteControlClaudeChats":false],forName:UserDefaults.argumentDomain)
        }
        #endif
        let runtime=try ConversationRuntime()
        RuntimeHooks.note={ message in fputs("chatterboxd: \(message)\n",stderr) }
        await runtime.resume()
        let server=RuntimeServer(runtime:runtime)
        try server.start();daemon=server
        let model=DaemonContext(runtime);context=model
        NotificationCenter.default.addObserver(forName:Notification.Name("ChatterboxRuntimeOpenPin"),object:nil,queue:.main){note in
            MainActor.assumeIsolated{if let pin=note.object as? Pin,let payload=try? JSON.value(pin){runtime.publishUIRequest("pin.open",payload:payload)}}
        }
        CompanionServer.shared.model=model
        CompanionServer.shared.startAgentListener()
        if CompanionServer.shared.isEnabled {CompanionServer.shared.start()}
        RuntimeHooks.clearSuggestions={NextSteps.shared.clear($0)}
        RuntimeHooks.suggested={session,item in
            try? runtime.recordAssistantNote(title:"Suggested an answer",detail:item.suggestedReason,chat:session.id)
        }
        RuntimeHooks.answered={session,item,suggestion,answers in
            try? runtime.recordAssistantNote(title:answers==suggestion ? "Sent the suggested answer":"Answered a question",detail:item.text,chat:session.id)
        }
        RuntimeHooks.turnEnded={session in NextSteps.shared.turnEnded(session,commands:session.availableSlashCommands);session.automaticTurn=false}
        print("chatterboxd ready");fflush(stdout)
        if ProcessInfo.processInfo.environment["CHATTERBOX_TEST_DISABLE_COMPUTER"] != "1" {PreviewRelays.shared.start()}
    } catch {fputs("chatterboxd: \(error.localizedDescription)\n",stderr);exit(1)}
}
signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN)
let stop=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
stop.setEventHandler {MainActor.assumeIsolated {daemon?.stop();exit(0)}};stop.resume()
RunLoop.main.run()

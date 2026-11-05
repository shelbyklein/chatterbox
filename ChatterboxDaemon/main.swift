import Foundation
import Darwin

var daemon:RuntimeServer?
var context:DaemonContext?
Task { @MainActor in
    do {
        try RuntimePreferences.load()
        #if DEBUG
        if RuntimePaths.data.path.hasPrefix("/tmp/chatterbox-test-"), let fake=ProcessInfo.processInfo.environment["FAKE_PROVIDER"] {
            AppPreferences.defaults.setVolatileDomain(["claudePath":fake,"codexPath":fake,"easyCLIProxyEnabled":false,"remoteControlClaudeChats":false],forName:UserDefaults.argumentDomain)
        }
        #endif
        await EasyCLIProxy.shared.refresh()
        let runtime=try ConversationRuntime()
        RuntimeHooks.note={ message in fputs("chatterboxd: \(message)\n",stderr) }
        // Listen first, reattach to the background host after: a host that's slow or had just
        // handed off once kept the service silent for a minute. Chats with nothing in a host
        // are settled now; ones with a reply there show as reconnecting until it's confirmed.
        runtime.settleUnlinked()
        let server=RuntimeServer(runtime:runtime)
        try server.start();daemon=server
        let model=DaemonContext(runtime);context=model
        let automations=AutomationRunner(model);AutomationRunner.shared=automations;automations.start()
        // Booted simulators nothing has used for half an hour are shut down (the whole Mac's).
        let simulators=SimulatorSweeper();SimulatorSweeper.shared=simulators;simulators.start()
        // How hard the Mac is working: Chatterbox holds its own work back before it's too much.
        let pressure=PressureMonitor(runtime:runtime);PressureMonitor.shared=pressure
        pressure.onChange={snapshot in runtime.publishUIRequest("pressure.changed",payload:(try? JSON.value(snapshot)) ?? .null)}
        pressure.start()
        NotificationCenter.default.addObserver(forName:Notification.Name("ChatterboxRuntimeOpenPin"),object:nil,queue:.main){note in
            MainActor.assumeIsolated{if let pin=note.object as? Pin,let payload=try? JSON.value(pin){runtime.publishUIRequest("pin.open",payload:payload)}}
        }
        CompanionServer.shared.model=model
        if CompanionServer.shared.isEnabled {CompanionServer.shared.start()}
        // The Desk tells the app what it shows now, whenever that changes.
        DeskStore.shared.onChange={desk in runtime.publishUIRequest("desk.changed",payload:(try? JSON.value(desk)) ?? .null)}
        // Claude's connector: each sign-in asks the Mac app to Allow it.
        ConnectorServer.shared.onRequest={id,client in runtime.publishUIRequest("connector.request",payload:["id":.string(id.uuidString),"client":.string(client)])}
        ConnectorServer.shared.start()
        RuntimeHooks.clearSuggestions={NextSteps.shared.clear($0)}
        RuntimeHooks.turnEnded={session in
            NextSteps.shared.turnEnded(session,commands:session.availableSlashCommands);session.automaticTurn=false
            // A sidequest's answer goes back once the turn has settled.
            if let parent=session.record.sidequestOf {DispatchQueue.main.async{session.sidequestTurnEnded(parent:runtime.session(parent))}}
            // …and a work thread's result goes to its front thread (plans/work-threads.md).
            if let front=session.record.workOf {DispatchQueue.main.async{session.workTurnEnded(front:runtime.session(front))}}
            // A work thread that has reported (a returned sidequest) lets its agent go now (ChatSession+Pressure).
            if session.record.workOf != nil || session.record.sidequestOf != nil {DispatchQueue.main.asyncAfter(deadline:.now()+2){runtime.releaseIdleAgents()}}
        }
        print("chatterboxd ready");fflush(stdout)
        let started=Date()
        await runtime.resume()
        let waiting=runtime.sessions.filter(\.awaitingHostResume).count
        RuntimeHooks.note("Checked the background host in \(String(format:"%.1f",Date().timeIntervalSince(started)))s"+(waiting>0 ? "; \(waiting) chat(s) still reconnecting":""))
    } catch {fputs("chatterboxd: \(error.localizedDescription)\n",stderr);exit(1)}
}
signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN)
let stop=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
stop.setEventHandler {MainActor.assumeIsolated {daemon?.stop();exit(0)}};stop.resume()
RunLoop.main.run()

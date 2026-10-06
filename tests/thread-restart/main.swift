@testable import Chatterbox
import AppKit
import SwiftUI

let app=NSApplication.shared
app.setActivationPolicy(.accessory)
setbuf(stdout,nil)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-thread-restart."))
    UserDefaults.standard.setVolatileDomain([
        "dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,
        "companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,
        "nextStepsEnabled":false,"claudeRemoteControl":false,
        "codexPath":root.appendingPathComponent("fake-codex.py").path,
        "claudePath":root.appendingPathComponent("fake-claude.py").path
    ],forName:UserDefaults.argumentDomain)
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    CodexAppServer.shared.resume([])
    func chat(_ backend:Backend,_ thread:String)->ChatSession {
        var r=ConversationRecord(title:"Fixture",model:"fixture",effort:"medium",personality:.neutral)
        r.items=[DisplayItem(kind:.user,text:"Keep this request"),DisplayItem(kind:.assistant,text:"Keep this answer",phase:.final)]
        if backend == .codex {r.codex=CodexSettings(threadId:thread,model:"fixture",effort:"medium",fastMode:true,folder:root.path,canEdit:false,mode:"readOnly",forkFrom:nil,route:nil)}
        else {r.claudeSessionID=thread;r.projectFolder=root.path;r.remoteControl=false}
        let s=ChatSession(record:r);s.draft="Unsent draft";s.draftAttachments=[Attachment(name:"draft.txt",path:root.appendingPathComponent("draft.txt").path,mediaType:"text/plain",kind:.text)]
        return s
    }
    func requests()->[[String:Any]] {
        let text=(try? String(contentsOf:root.appendingPathComponent("codex-requests.jsonl"),encoding:.utf8)) ?? ""
        return text.split(separator:"\n").map {try! JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
    }
    func pause() async throws {try await Task.sleep(for:.milliseconds(180))}
    let a=chat(.codex,"thread-a"), b=chat(.codex,"thread-b")
    let otherHistory=b.items
    let history=a.items, settings=a.record.codex, attachments=a.draftAttachments
    b.isRunning=true;b.codexTurnID="other-turn";b.codexRegisterHandler("thread-b")
    await a.restartThread()
    precondition(a.items==history && a.record.codex==settings && a.draft=="Unsent draft" && a.draftAttachments==attachments)
    precondition(a.threadRestartStatus?.hasPrefix("Thread restarted")==true)
    precondition(b.isRunning && b.codexTurnID=="other-turn" && b.items==otherHistory)
    let host=CodexAppServer.shared.hostID
    let before=requests().filter {$0["method"] as? String=="thread/resume"}.count
    async let first:Void=a.restartThread()
    try await Task.sleep(for:.milliseconds(20))
    precondition(a.isRestartingThread)
    a.send("Must not send during reconnect")
    await a.restartThread()
    await first
    precondition(requests().filter {$0["method"] as? String=="thread/resume"}.count==before+1,"Double click reconnects twice")
    precondition(a.items==history && CodexAppServer.shared.hostID==host)
    print("PASS idle history/settings/draft/attachments, single flight, input guard, other thread and shared host preserved")
    a.isRunning=true;a.codexTurnID="turn-a"
    a.pendingSteering=[UserMessage(text:"Queued request")]
    let queue=DisplayItem(kind:.user,text:"Queued request",queued:true)
    a.record.items.append(queue);a.pendingSteeringItems=[queue.id]
    await a.restartThread()
    precondition(!a.isRunning && !a.isRestartingThread && a.record.codex==settings)
    precondition(a.items.contains {$0.id==queue.id && $0.text==queue.text})
    let relevant=requests().filter {$0["threadId"] as? String=="thread-a"}.suffix(2)
    precondition(relevant.map {$0["method"] as! String}==["turn/interrupt","thread/resume"])
    precondition(!requests().contains { ["turn/start","turn/steer","thread/start","thread/archive","thread/delete"].contains($0["method"] as? String ?? "") })
    print("PASS active interrupt before reconnect; queued prompt retained without resend")
    let stale=chat(.codex,"stale-idle")
    stale.isRunning=true;stale.codexTurnID=nil
    let staleQueue=DisplayItem(kind:.user,text:"Keep queued",queued:true)
    stale.record.items.append(staleQueue)
    stale.pendingSteering=[UserMessage(text:"Keep queued")];stale.pendingSteeringItems=[staleQueue.id]
    let staleHistory=stale.items
    await stale.restartThread()
    precondition(!stale.isRunning && stale.items==staleHistory && stale.pendingSteeringItems==[staleQueue.id])
    precondition(stale.threadRestartStatus?.hasPrefix("Thread restarted")==true)
    precondition(!requests().contains {$0["method"] as? String=="turn/interrupt" && $0["threadId"] as? String=="stale-idle"})
    let recovered=chat(.codex,"missing-active");recovered.isRunning=true;recovered.codexTurnID=nil
    recovered.codexRegisterHandler("missing-active")
    await recovered.restartThread()
    precondition(!recovered.isRunning && recovered.threadRestartStatus?.hasPrefix("Thread restarted")==true)
    precondition(requests().contains {$0["method"] as? String=="turn/interrupt" && $0["turnId"] as? String=="recovered-turn"})
    let unknown=chat(.codex,"unknown-state");unknown.isRunning=true;unknown.codexTurnID=nil
    await unknown.restartThread()
    precondition(unknown.isRunning && unknown.threadRestartStatus?.hasPrefix("Couldn't restart")==true)
    precondition(!requests().contains {$0["method"] as? String=="thread/resume" && $0["threadId"] as? String=="unknown-state"})
    let starting=chat(.codex,"starting");starting.isRunning=true;starting.codexStartInFlight=true
    let beforeStart=requests().count
    _ = try await starting.codexReconcileMissingTurn()
    precondition(starting.isRunning && requests().count==beforeStart)
    print("PASS provider-confirmed stale state recovery; queued messages/history retained; missing active ID recovered; unknown/in-flight state fails closed")
    let failed=chat(.codex,"fail"), failedHistory=failed.items
    await failed.restartThread()
    precondition(failed.record.codex?.threadId=="fail" && failed.items==failedHistory && !failed.isRestartingThread && failed.threadRestartStatus?.hasPrefix("Couldn't restart")==true)
    do {_=try await CodexAppServer.shared.request("test/slow",.null,timeout:.milliseconds(50));preconditionFailure("Timeout did not fail")} catch {}
    await a.restartThread()
    precondition(a.threadRestartStatus?.hasPrefix("Thread restarted")==true,"Late response interfered with reconnect")
    let stuck=chat(.codex,"never-stops")
    stuck.isRunning=true;stuck.codexTurnID="stuck-turn";stuck.codexRegisterHandler("never-stops")
    await stuck.restartThread()
    precondition(stuck.isRunning && !stuck.isRestartingThread && stuck.record.codex?.threadId=="never-stops")
    precondition(stuck.threadRestartStatus?.hasPrefix("Couldn't restart")==true)
    precondition(!requests().contains {$0["method"] as? String=="thread/resume" && $0["threadId"] as? String=="never-stops"})
    print("PASS reconnect failure, RPC timeout/late response, failed stop does not reconnect or reset history")
    let claude=chat(.claude,"claude-session"), claudeHistory=claude.items
    let claudeAttachments=claude.draftAttachments
    await claude.restartThread()
    while !FileManager.default.fileExists(atPath:root.appendingPathComponent("claude-launches.jsonl").path) {try await pause()}
    let old=claude.claudeProcess!.hostID
    claude.isRunning=true
    await claude.restartThread()
    let launchDeadline=Date().addingTimeInterval(5)
    while ((try? String(contentsOf:root.appendingPathComponent("claude-launches.jsonl"),encoding:.utf8).split(separator:"\n").count) ?? 0)<2 {
        precondition(Date()<launchDeadline,"Second Claude fixture never launched")
        try await pause()
    }
    precondition(claude.claudeProcess?.hostID != old && claude.claudeProcess?.isRunning==true && !claude.isRunning)
    precondition(claude.record.claudeSessionID=="claude-session" && claude.items==claudeHistory && claude.draft=="Unsent draft" && claude.draftAttachments==claudeAttachments)
    let launches=try String(contentsOf:root.appendingPathComponent("claude-launches.jsonl"),encoding:.utf8)
    precondition(launches.split(separator:"\n").count==2 && !launches.contains("new-fixture-session"))
    let input=(try? String(contentsOf:root.appendingPathComponent("claude-input.jsonl"),encoding:.utf8)) ?? ""
    precondition(!input.contains("user"),"Claude restart sent input")
    print("PASS Claude dedicated process replaced with same --resume ID; no user prompt sent; history/drafts intact")
    let missing=chat(.claude,"claude-missing")
    let missingOriginal=missing.items
    await missing.restartThread()
    let missingDeadline=Date().addingTimeInterval(5)
    while missing.claudeProcess != nil {
        precondition(Date()<missingDeadline,"Missing-session fixture did not exit")
        try await pause()
    }
    precondition(missing.record.claudeSessionID=="claude-missing" && missing.items==missingOriginal && missing.threadRestartStatus?.hasPrefix("Couldn't restart")==true)
    print("PASS Claude failed resume preserves original session ID/history and reports failure")
    let panel=NSPanel(contentRect:NSRect(x:30,y:80,width:380,height:620),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
    a.threadRestartStatus=nil
    panel.contentView=NSHostingView(rootView:ScrollView {ChatSettingsCog(session:a).main})
    panel.orderFrontRegardless()
    try await pause()
    capture(panel,root.appendingPathComponent("restart-control.png"))
    let count=requests().filter {$0["method"] as? String=="thread/resume"}.count
    for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
        let event=NSEvent.mouseEvent(with:type,location:NSPoint(x:80,y:panel.contentView!.bounds.height-24),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        panel.sendEvent(event)
    }
    try await Task.sleep(for:.milliseconds(600))
    precondition(requests().filter {$0["method"] as? String=="thread/resume"}.count==count+1,"Native Restart Thread click didn't reconnect")
    capture(panel,root.appendingPathComponent("restart-result.png"))
    print("PASS native Golem settings Restart Thread button click and rendered outcome")
    claude.claudeProcess?.terminate()
    CodexAppServer.shared.terminate()
    panel.orderOut(nil)
}
@MainActor func capture(_ window:NSWindow,_ url:URL) {
    typealias Fn = @convention(c) (CGRect,UInt32,UInt32,UInt32)->Unmanaged<CGImage>?
    let sym=dlsym(UnsafeMutableRawPointer(bitPattern:-2),"CGWindowListCreateImage")!
    let fn=unsafeBitCast(sym,to:Fn.self)
    let image=fn(.null,1<<3,UInt32(window.windowNumber),(1<<0)|(1<<3))!.takeRetainedValue()
    try! NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:url)
}
Task {do {try await run();exit(0)}catch {print("FAIL",error);exit(1)}}
app.run()

import Foundation
import Darwin

func check(_ condition: @autoclosure () -> Bool, _ message:String) throws {
    guard condition() else {throw RuntimeFailure(message)}
    print("PASS \(message)")
}
@MainActor func wait(_ message:String, until predicate: () -> Bool) async throws {
    let until=Date().addingTimeInterval(8)
    while !predicate() { if Date()>until { throw RuntimeFailure("Timed out: \(message)") };try await Task.sleep(for:.milliseconds(20)) }
}
@MainActor func test() async throws {
    let root=RuntimePaths.data
    UserDefaults.standard.setVolatileDomain([
        "claudePath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,"codexPath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,
        "easyCLIProxyEnabled":false,"remoteControlClaudeChats":false
    ], forName:UserDefaults.argumentDomain)
    var runtime:ConversationRuntime?=try ConversationRuntime(root:root)
    await runtime!.resume()
    do { let second=try ConversationRuntime(root:root);_ = second;throw RuntimeFailure("Duplicate writer accepted") }
    catch {try check(error.localizedDescription.contains("active writer"),"duplicate writer refused")}
    try RuntimePreferences.update(["proxyClaudeChats":true,"proxyCodexChats":false])
    AppPreferences.defaults.removeObject(forKey:"proxyClaudeChats")
    try RuntimePreferences.load()
    try check(EasyCLIProxy.shared.claudeOn && !EasyCLIProxy.shared.codexOn,"proxy preferences persist and reload under their actual keys")
    await EasyCLIProxy.shared.refresh()
    var proxyRecord=ConversationRecord(model:"default",effort:"",personality:.neutral)
    proxyRecord.activeBackend = .claude
    let proxySession=ChatSession(record:proxyRecord)
    if EasyCLIProxy.shared.isRunning {
        try check(proxySession.claudeProxyEnvironment["ANTHROPIC_BASE_URL"] == EasyCLIProxy.shared.endpoint?.base,"Claude launch environment selects healthy proxy")
        proxySession.record.isDot=true
        try check(proxySession.claudeProxyEnvironment.isEmpty,"assistant remains direct")
    }
    try RuntimePreferences.update(["proxyClaudeChats":false])
    proxySession.record.isDot=false
    try check(proxySession.claudeProxyEnvironment.isEmpty,"disabled Claude routing remains direct")
    // Companion-created Studio chats persist unrestricted modes for both agents.
    do {
    let studio=Studio(name:"Permissions",folder:root.path)
    let context=DaemonContext(runtime!)
    for backend in Backend.allCases {
        let created=try context.newChat(in:studio,backend:backend)
        try check(created.record.backend == backend && created.record.claudeModeID == "bypassPermissions" && created.record.codex?.modeID == "fullAccess","\(backend) Studio creation permission defaults")
        try check(created.record.codex?.folder == studio.folder,"\(backend) Studio Codex working folder")
        let data=try Data(contentsOf:root.appendingPathComponent("Conversations/\(created.id.uuidString).json"))
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let saved=try decoder.decode(ConversationRecord.self,from:data)
        try check(saved.claudeModeID == "bypassPermissions" && saved.codex?.modeID == "fullAccess","\(backend) Studio permission defaults durable")
    }
    }
    for backend in Backend.allCases {
        var r=ConversationRecord(model:"default",effort:"",personality:.neutral)
        r.activeBackend=backend
        r.projectFolder=root.path
        if backend == .codex {r.codex=CodexSettings(folder:root.path,canEdit:false,mode:"readOnly")}
        let s=try runtime!.insert(r)
        s.send("hello")
        try await wait("\(backend) reply") { !s.isRunning && s.items.contains {$0.kind == .assistant} }
        try check(s.items.filter {$0.kind == .assistant}.count==1,"\(backend) ordinary reply")
        // Attached agents must cool down without losing provider history or the transcript.
        try await Task.sleep(for: .milliseconds(100))
        let providerID = backend == .claude ? s.record.claudeSessionID : s.record.codex?.threadId
        let oldHostID = backend == .claude ? s.claudeProcess?.hostID : CodexAppServer.shared.hostID
        let rowsBeforeIdle = s.items.count
        s.draft = "idle draft"
        let idleStart = Date()
        runtime!.releaseIdleAgents(now: idleStart)
        runtime!.releaseIdleAgents(now: idleStart.addingTimeInterval(119))
        try check(backend == .claude ? s.claudeProcess != nil : CodexAppServer.shared.isRunning,
                  "\(backend) warm process retained before timeout")
        s.record.backgroundTasks = [BackgroundTask(id: "protected", kind: .shell, title: "Background work", detached: true)]
        runtime!.releaseIdleAgents(now: idleStart.addingTimeInterval(130))
        try check(backend == .claude ? s.claudeProcess != nil : CodexAppServer.shared.isRunning,
                  "\(backend) background work protects idle process")
        s.record.backgroundTasks = []
        s.record.items.append(DisplayItem(kind: .approval, approvalState: .pending))
        try check(!s.canReleaseIdleAgent, "\(backend) pending approval blocks retirement after reply")
        s.record.items.removeLast()
        s.record.items.append(DisplayItem(kind: .user, text: "queued", queued: true))
        try check(!s.canReleaseIdleAgent, "\(backend) queued message blocks retirement")
        s.record.items.removeLast()
        if backend == .claude {
            s.record.remoteControl = true
            try check(!s.canReleaseIdleAgent, "remote-control session blocks retirement before URL arrives")
            s.record.remoteControl = false
        }
        runtime!.releaseIdleAgents(now: idleStart.addingTimeInterval(131))
        runtime!.releaseIdleAgents(now: idleStart.addingTimeInterval(252))
        try check(backend == .claude ? s.claudeProcess == nil : !CodexAppServer.shared.isRunning,
                  "\(backend) attached idle process released")
        try check(s.items.count == rowsBeforeIdle && s.draft == "idle draft",
                  "\(backend) idle release preserves transcript and draft")
        try check(providerID == (backend == .claude ? s.record.claudeSessionID : s.record.codex?.threadId),
                  "\(backend) idle release preserves provider history ID")
        s.send("continue after idle")
        try await wait("resumed idle provider") { !s.isRunning && s.items.count > rowsBeforeIdle }
        try check(oldHostID != (backend == .claude ? s.claudeProcess?.hostID : CodexAppServer.shared.hostID),
                  "\(backend) next message starts a fresh process")
        try check(providerID == (backend == .claude ? s.record.claudeSessionID : s.record.codex?.threadId),
                  "\(backend) fresh process resumes same provider history")
        s.send("question")
        try await wait("question") {s.items.contains {$0.kind == .questions && $0.approvalState == .pending}}
        let protectedHost = backend == .claude ? s.claudeProcess?.hostID : CodexAppServer.shared.hostID
        let approvalTime = Date()
        runtime!.releaseIdleAgents(now: approvalTime)
        runtime!.releaseIdleAgents(now: approvalTime.addingTimeInterval(1000))
        try check(protectedHost == (backend == .claude ? s.claudeProcess?.hostID : CodexAppServer.shared.hostID),
                  "\(backend) active question survives idle sweeps")
        let q=s.items.last {$0.kind == .questions}!
        s.answerQuestions(q.id,answers:[q.questions!.first!.id:["A"]])
        try await wait("answered") {!s.isRunning}
        try check(s.items.first {$0.id==q.id}?.approvalState == .approved,"\(backend) user answer")
        s.send("approval")
        try await wait("approval") {s.items.contains {$0.kind == .approval && $0.approvalState == .pending}}
        let a=s.items.last {$0.kind == .approval}!
        s.resolveApproval(a.id,.denied)
        try await wait("denied") {!s.isRunning}
        try check(s.items.first {$0.id==a.id}?.approvalState == .denied,"\(backend) user denial")
        s.send("hold")
        try await wait("running") {s.isRunning}
        try await Task.sleep(for:.milliseconds(150))
        s.send("steer")
        try await wait("steered") {!s.isRunning}
        try check(s.items.contains {$0.kind == .user && $0.steered},"\(backend) steering")
        s.send("hold")
        try await Task.sleep(for:.milliseconds(150));s.interrupt()
        try await wait("stopped") {!s.isRunning}
        try check(!s.canStop,"\(backend) stop")
        s.send("hold")
        s.send("queued immediately")
        try await wait("queued drain") {!s.isRunning}
        try check(s.items.contains {$0.text=="queued immediately" && $0.steered},"\(backend) queued while starting")
        s.send("hold")
        try await Task.sleep(for:.milliseconds(150))
        try runtime!.flush()
        let beforeRestart=s.items.count
        let chatID=s.id
        for old in runtime!.sessions {old.onChange=nil;old.onStreamed=nil}
        runtime=nil
        runtime=try ConversationRuntime(root:root)
        await runtime!.resume()
        let reattached=runtime!.session(chatID)!
        try check(reattached.isRunning,"\(backend) active turn reattached headlessly")
        reattached.interrupt()
        try await wait("reattached stop") {!reattached.isRunning}
        try check(reattached.items.count <= beforeRestart+1,"\(backend) active replay without duplicate user row")
        try runtime!.updateDraft(reattached,text:"unsent",attachments:[])
    }
    // Idle threads release independently while the shared server continues another turn.
    var idleRecord = ConversationRecord(model: "default", effort: "", personality: .neutral)
    idleRecord.activeBackend = .codex
    idleRecord.codex = CodexSettings(folder: root.path, canEdit: false, mode: "readOnly")
    let idleChat = try runtime!.insert(idleRecord)
    var activeRecord = ConversationRecord(model: "default", effort: "", personality: .neutral)
    activeRecord.activeBackend = .codex
    activeRecord.codex = CodexSettings(folder: root.path, canEdit: false, mode: "readOnly")
    let activeChat = try runtime!.insert(activeRecord)
    idleChat.send("idle thread hello")
    try await wait("idle thread initialized") { !idleChat.isRunning && idleChat.record.codex?.threadId != nil }
    activeChat.send("hold")
    try await wait("second thread running") { activeChat.isRunning && activeChat.codexTurnID != nil }
    let idleThread = idleChat.record.codex!.threadId!
    let activeThread = activeChat.record.codex!.threadId!
    let sharedHost = CodexAppServer.shared.hostID
    let idleRowCount = idleChat.items.count
    idleChat.draft = "keep this draft"
    let threadIdleStart = Date()
    runtime!.releaseIdleAgents(now: threadIdleStart)
    runtime!.releaseIdleAgents(now: threadIdleStart.addingTimeInterval(121))
    try await wait("idle thread unsubscribed") { CodexAppServer.shared.unsubscribedThreads.contains(idleThread) }
    try check(activeChat.isRunning && CodexAppServer.shared.hostID == sharedHost,
              "per-thread cleanup preserves active reply and shared process")
    try check(CodexAppServer.shared.isThreadSubscribed(activeThread), "active thread remains subscribed")
    try check(idleChat.items.count == idleRowCount && idleChat.draft == "keep this draft", "unsubscribe preserves idle transcript and draft")
    let requestsURL = root.appendingPathComponent("codex-requests.jsonl")
    func requests() throws -> [JSON] {
        try String(contentsOf: requestsURL, encoding: .utf8).split(separator: "\n").map { try JSON.parse(Data($0.utf8)) }
    }
    let unsubscribeRequests = try requests()
    try check(unsubscribeRequests.contains { $0["method"]?.string == "thread/unsubscribe" && $0["threadId"]?.string == idleThread },
              "idle thread unsubscribe sent to provider")
    try check(!unsubscribeRequests.contains { $0["method"]?.string == "thread/unsubscribe" && $0["threadId"]?.string == activeThread },
              "no unsubscribe sent for active thread")
    // Restart metadata must preserve the distinction between loaded and subscribed.
    CodexAppServer.shared.saveResumeState()
    let resumeJSON = try JSON.parse(Data(contentsOf: HostPaths.directory.appendingPathComponent("codex-resume.json")))
    try check(resumeJSON["unsubscribedThreads"]?.array?.contains(.string(idleThread)) == true, "unsubscribe persisted for service reattachment")
    idleChat.send("resume idle thread")
    try await wait("idle thread resumed") { !idleChat.isRunning && idleChat.items.count > idleRowCount }
    try check(idleChat.record.codex?.threadId == idleThread && CodexAppServer.shared.isThreadSubscribed(idleThread), "returning message resumes original thread")
    let resumeRequests = try requests()
    let unsubscribeIndex = resumeRequests.lastIndex { $0["method"]?.string == "thread/unsubscribe" && $0["threadId"]?.string == idleThread }!
    let resumeIndex = resumeRequests.lastIndex { $0["method"]?.string == "thread/resume" && $0["threadId"]?.string == idleThread }!
    try check(resumeIndex > unsubscribeIndex, "resubscribe occurs after unsubscribe")
    try check(CodexAppServer.shared.hostID == sharedHost && activeChat.isRunning, "resumed idle chat does not restart or stop other chat")
    let threadRead = Task { @MainActor in try await CodexAppServer.shared.request("thread/read", ["threadId": .string(idleThread)]) }
    try await Task.sleep(for: .milliseconds(30))
    try check(!CodexAppServer.shared.canUnsubscribeThread(idleThread), "pending per-thread RPC blocks unsubscribe")
    _ = try await threadRead.value
    let inFlightUnsubscribe = Task { @MainActor in await CodexAppServer.shared.unsubscribeIdleThread(idleThread) }
    try await Task.sleep(for: .milliseconds(30))
    let beforeRacedMessage = idleChat.items.count
    idleChat.send("message during unsubscribe")
    try await wait("message during unsubscribe resumed") { !idleChat.isRunning && idleChat.items.count > beforeRacedMessage }
    await inFlightUnsubscribe.value
    try check(CodexAppServer.shared.isThreadSubscribed(idleThread) && activeChat.isRunning,
              "returning message wins unsubscribe race without interrupting other thread")
    let racedRequests = try requests()
    let racedUnsubscribe = racedRequests.lastIndex { $0["method"]?.string == "thread/unsubscribe" && $0["threadId"]?.string == idleThread }!
    let racedResume = racedRequests.lastIndex { $0["method"]?.string == "thread/resume" && $0["threadId"]?.string == idleThread }!
    let racedTurn = racedRequests.lastIndex { $0["method"]?.string == "turn/start" && $0["threadId"]?.string == idleThread }!
    try check(racedUnsubscribe < racedResume && racedResume < racedTurn,
              "in-flight unsubscribe completes before resume and new turn")
    _ = try await CodexAppServer.shared.request("fixture/failUnsubscribe", [:])
    await CodexAppServer.shared.unsubscribeIdleThread(idleThread)
    try check(!CodexAppServer.shared.isThreadSubscribed(idleThread), "unconfirmed unsubscribe requires resumption before next turn")
    let beforeFailureResume = idleChat.items.count
    idleChat.send("recover unsubscribe failure")
    try await wait("failed unsubscribe recovery") { !idleChat.isRunning && idleChat.items.count > beforeFailureResume }
    try check(idleChat.record.codex?.threadId == idleThread && CodexAppServer.shared.isThreadSubscribed(idleThread), "unsubscribe failure preserves history and next-message usability")
    _ = try await CodexAppServer.shared.request("fixture/closeThread", ["threadId": .string(idleThread)])
    try await wait("closed thread removed") { !CodexAppServer.shared.loadedThreads.contains(idleThread) }
    try check(!CodexAppServer.shared.loadedThreads.contains(idleThread), "server thread closure clears loaded bookkeeping")
    activeChat.interrupt()
    try await wait("active thread stopped") { !activeChat.isRunning }
    // A retired agent's helpers must not remain after its parent exits.
    let helperPIDFile = root.appendingPathComponent("helper.pid")
    let helperGroupID = "idle-helper-group"
    try HostClient.shared.spawn(id: helperGroupID, executable: "/bin/sh",
        arguments: ["-c", "trap '' TERM; sleep 1000 & echo $! > \(helperPIDFile.path); wait"],
        cwd: root.path, environment: BinaryLocator.environment, kind: nil)
    try await wait("helper started") { FileManager.default.fileExists(atPath: helperPIDFile.path) }
    let helperPID = Int32(try String(contentsOf: helperPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    try check(kill(helperPID, 0) == 0, "agent helper is running before retirement")
    HostClient.shared.kill(id: helperGroupID, forget: true)
    try await wait("retired agent helper gone") { kill(helperPID, 0) != 0 }
    try check(kill(helperPID, 0) != 0, "agent retirement removes stubborn tool helper")
    let request="dedupe"
    let first=try runtime!.execute(id:request,operation:"insert",fingerprint:"same") {let s=try runtime!.insert(ConversationRecord(model:"default",effort:"",personality:.neutral));return .string(s.id.uuidString)}
    let second=try runtime!.execute(id:request,operation:"insert",fingerprint:"same") {throw RuntimeFailure("Repeated side effect")}
    try check(first==second,"idempotent command returns original result")
    try runtime!.flush()
    let counts=Dictionary(uniqueKeysWithValues:runtime!.sessions.map {($0.id,$0.items.count)})
    for s in runtime!.sessions {s.onChange=nil;s.onStreamed=nil}
    runtime=nil
    let reopened=try ConversationRuntime(root:root)
    await reopened.resume()
    try check(reopened.sessions.allSatisfy {counts[$0.id]==$0.items.count},"restart retains row counts")
    try check(reopened.sessions.filter {$0.draft=="unsent"}.count==2,"restart retains drafts")
    try await Task.sleep(for:.milliseconds(200))
    try check(reopened.sessions.allSatisfy {counts[$0.id]==$0.items.count},"provider replay does not duplicate rows")
    for s in reopened.sessions {s.shutdown()}
    CodexAppServer.shared.terminate();HostClient.shared.disconnect()
    print("PASS Foundation runtime, both providers, restart and ownership")
}
Task { @MainActor in do {try await test();exit(0)}catch {print("FAIL \(error.localizedDescription)");exit(1)} }
RunLoop.main.run()

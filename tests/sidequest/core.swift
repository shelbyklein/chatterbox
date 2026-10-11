import Foundation
import Darwin
// A sidequest round trip through the conversation engine, with the fixture providers:
// Claude chat → Codex sidequest → the answer goes back → Claude carries on.

func check(_ condition: @autoclosure () -> Bool, _ message:String) throws {
    guard condition() else {throw RuntimeFailure(message)}
    print("PASS \(message)")
}
@MainActor func wait(_ message:String, until predicate: () -> Bool) async throws {
    let until=Date().addingTimeInterval(10)
    while !predicate() { if Date()>until { throw RuntimeFailure("Timed out: \(message)") };try await Task.sleep(for:.milliseconds(20)) }
}
@MainActor func test() async throws {
    let root=RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-sidequest."))
    UserDefaults.standard.setVolatileDomain([
        "claudePath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,"codexPath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,
        "easyCLIProxyEnabled":false,"remoteControlClaudeChats":false
    ], forName:UserDefaults.argumentDomain)
    let runtime=try ConversationRuntime(root:root)
    await runtime.resume()
    // As the service wires it (ChatterboxDaemon/main.swift).
    RuntimeHooks.turnEnded={session in
        session.automaticTurn=false
        if let parent=session.record.sidequestOf {DispatchQueue.main.async{session.sidequestTurnEnded(parent:runtime.session(parent))}}
    }
    var r=ConversationRecord(model:"default",effort:"",personality:.neutral)
    r.activeBackend = .claude
    let parent=try runtime.insert(r)
    parent.send("Plan the header layout")
    try await wait("parent reply") {!parent.isRunning && parent.items.contains {$0.kind == .assistant}}

    let record=ChatSession.sidequestRecord(of:parent,anchor:parent,number:1,backend:.codex,task:"Check the build passes")
    try check(record.activeBackend == .codex && record.codex != nil,"sidequest runs on the other agent, with Codex settings")
    try check(record.codex?.mode != "readOnly" && record.codex?.canEdit == true,"a Codex sidequest may write in its folder")
    try check(record.pendingHandoff?.contains("change nothing unless the task asks") == true,"its instructions say when to stay read-only")
    var claudeParent=ConversationRecord(model:"default",effort:"",personality:.neutral)
    claudeParent.activeBackend = .codex
    claudeParent.codex=CodexSettings(folder:root.path,canEdit:false,mode:"fullAccess")
    claudeParent.claudeMode="plan"
    let codexChat=ChatSession(record:claudeParent)
    let toClaude=ChatSession.sidequestRecord(of:codexChat,anchor:codexChat,number:1,backend:.claude,task:"Check this")
    try check(toClaude.claudeModeID == "acceptEdits","a Claude sidequest may write in its folder")
    try check(toClaude.pendingHandoff?.contains("treat it as a review") == true,"Codex-to-Claude defaults to a review")
    var trusted=claudeParent;trusted.claudeMode="bypassPermissions"
    try check(ChatSession.sidequestRecord(of:ChatSession(record:trusted),anchor:codexChat,number:1,backend:.claude,task:"x").claudeModeID == "bypassPermissions","settings that allow more stay")
    try check(record.sidechatOf == parent.id && record.sidequestOf == parent.id,"sidequest sits under its chat and returns to it")
    try check(record.pendingHandoff?.contains("Plan the header layout") == true && record.pendingHandoff?.contains("<sidequest>") == true,"sidequest is caught up on the whole chat")
    let parentReplies=parent.items.filter {$0.kind == .assistant}.count
    let quest=try runtime.insert(record)
    quest.beginSidequest(from:parent)
    try check(parent.items.last?.sidequest == quest.id,"the chat marks the sidequest it started")
    try check(quest.items.first {$0.kind == .user}?.text == "Check the build passes","the task is the sidequest's first message")
    try await wait("handoff sent") {quest.record.pendingHandoff == nil}
    try check(true,"the handoff went with the task")

    try await wait("sidequest answer returns") {
        parent.items.contains {$0.kind == .user && $0.sidequest == quest.id && $0.automatic == true}
    }
    let back=parent.items.last {$0.kind == .user && $0.sidequest == quest.id}!
    try check(back.text.contains("<sidequest_result>") && back.text.contains("Fixture reply.") && back.text.contains("Check the build passes"),"the answer carries the task and the final reply")
    try check(back.detail == "Codex is back from its sidequest","the returned row is labelled")
    try await wait("parent carries on") {!parent.isRunning && parent.items.filter {$0.kind == .assistant}.count > parentReplies}
    try check(true,"the original agent carries on from the answer")
    try check(quest.record.sidequestReturned != nil && quest.unreturnedSidequestReply == nil,"the reply is recorded as sent back")

    // Chatting on in the sidequest doesn't bounce every answer back.
    let returnedCount=parent.items.filter {$0.sidequest == quest.id && $0.kind == .user}.count
    quest.send("Also check the tests")
    try await wait("follow-up reply") {!quest.isRunning && quest.unreturnedSidequestReply != nil}
    try await Task.sleep(for:.milliseconds(300))
    try check(parent.items.filter {$0.sidequest == quest.id && $0.kind == .user}.count == returnedCount,"later replies wait for Send Back")
    quest.returnSidequest(to:parent)
    try check(parent.items.filter {$0.sidequest == quest.id && $0.kind == .user}.count == returnedCount+1,"Send Back sends the newest reply")
    try await wait("parent settles") {!parent.isRunning}
    for s in runtime.sessions {s.shutdown()}
    try runtime.flush()
    print("PASS sidequest round trip")
}
Task { @MainActor in do {try await test();exit(0)} catch {print("FAIL \(error.localizedDescription)");exit(1)} }
RunLoop.main.run()

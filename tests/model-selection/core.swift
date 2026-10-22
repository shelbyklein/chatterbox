import Foundation
import Darwin
// Keeping the closest effort across a switch, and new sessions starting on what their kind
// last used.

func check(_ condition: @autoclosure () -> Bool, _ message:String) throws {
    guard condition() else {throw RuntimeFailure(message)}
    print("PASS \(message)")
}
@MainActor func test() async throws {
    let root=RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-model-selection."))
    UserDefaults.standard.setVolatileDomain([
        "claudePath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,"codexPath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,
        "easyCLIProxyEnabled":false,"remoteControlClaudeChats":false
    ], forName:UserDefaults.argumentDomain)
    // The closest effort a model takes.
    try check(ModelSelection.closest("max",in:["low","medium","high"])=="high","max becomes high")
    try check(ModelSelection.closest("minimal",in:["low","medium","high"])=="low","minimal becomes low")
    try check(ModelSelection.closest("medium",in:["low","medium","high"])=="medium","a supported effort stays")
    try check(ModelSelection.closest("",in:["low","high"])=="","the model's default stays the default")

    let runtime=try ConversationRuntime(root:root)
    await runtime.resume()
    var r=ConversationRecord(model:"opus",effort:"max",personality:.neutral)
    r.activeBackend = .claude
    let s=try runtime.insert(r)
    let selection=ModelSelection.shared
    // Switching to Codex keeps the closest effort (Codex here takes low, medium, high).
    selection.choose(ModelChoice(backend:.codex,model:"gpt-6.1-sol"),for:s)
    try check(s.record.backend == .codex && s.record.codex?.model=="gpt-6.1-sol" && s.record.codex?.effort=="high","Claude at max → Codex at high (closest)")
    try check(ModelSelection.lastUsed(.chats)==LastModel(backend:.codex,model:"gpt-6.1-sol",effort:"high"),"remembered for Chats")
    selection.setEffort("low",for:s)
    try check(s.record.codex?.effort=="low" && ModelSelection.lastUsed(.chats)?.effort=="low","dragging the effort is remembered too")
    try check(ModelSelection.lastUsed(.studios)==nil,"other kinds are separate")

    // A new Chats session starts there; a named agent that differs keeps its own.
    var fresh=ConversationRecord(model:"opus",effort:"",personality:.neutral);fresh.activeBackend = .claude
    let next=try runtime.insert(fresh)
    ModelSelection.startLikeLast(next,kind:.chats)
    try check(next.record.backend == .codex && next.record.codex?.model=="gpt-6.1-sol" && next.record.codex?.effort=="low","a new session starts on what Chats last used")
    var named=ConversationRecord(model:"opus",effort:"",personality:.neutral);named.activeBackend = .claude
    let claudeOnly=try runtime.insert(named)
    ModelSelection.startLikeLast(claudeOnly,kind:.chats,requested:.claude)
    try check(claudeOnly.record.backend == .claude && claudeOnly.record.model=="opus","New Claude Session stays on Claude")

    for s in runtime.sessions {s.shutdown()}
    try runtime.flush()
    print("PASS model selection")
}
Task { @MainActor in do {try await test();exit(0)} catch {print("FAIL \(error.localizedDescription)");exit(1)} }
RunLoop.main.run()

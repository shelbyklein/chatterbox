import Foundation
import Darwin
// Favorites replaced presets: first-run migration, keeping the closest effort across a
// switch, and new sessions starting on what their kind last used.

func check(_ condition: @autoclosure () -> Bool, _ message:String) throws {
    guard condition() else {throw RuntimeFailure(message)}
    print("PASS \(message)")
}
@MainActor func test() async throws {
    let root=RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-model-favorites."))
    UserDefaults.standard.setVolatileDomain([
        "claudePath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,"codexPath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,
        "easyCLIProxyEnabled":false,"remoteControlClaudeChats":false
    ], forName:UserDefaults.argumentDomain)
    // Saved presets (two the same model) become favorites, in order, once.
    let presets=[ModelPreset(title:"Sol",backend:.codex,model:"gpt-6.1-sol",effort:"low"),
                 ModelPreset(title:"Opus",backend:.claude,model:"opus",effort:"high"),
                 ModelPreset(title:"Opus max",backend:.claude,model:"opus",effort:"max")]
    AppPreferences.defaults.set(try JSONEncoder().encode(presets),forKey:"modelPresets")
    AppPreferences.defaults.removeObject(forKey:ModelFavorites.key)
    try check(ModelFavorites.fromPresets()==[ModelChoice(backend:.codex,model:"gpt-6.1-sol"),ModelChoice(backend:.claude,model:"opus")],"presets become favorites, in order, models only")

    // The closest effort a model takes.
    try check(ModelFavorites.closest("max",in:["low","medium","high"])=="high","max becomes high")
    try check(ModelFavorites.closest("minimal",in:["low","medium","high"])=="low","minimal becomes low")
    try check(ModelFavorites.closest("medium",in:["low","medium","high"])=="medium","a supported effort stays")
    try check(ModelFavorites.closest("",in:["low","high"])=="","the model's default stays the default")

    let runtime=try ConversationRuntime(root:root)
    await runtime.resume()
    var r=ConversationRecord(model:"opus",effort:"max",personality:.neutral)
    r.activeBackend = .claude
    let s=try runtime.insert(r)
    let favorites=ModelFavorites.shared
    // Switching to Codex keeps the closest effort (Codex here takes low, medium, high).
    favorites.choose(ModelChoice(backend:.codex,model:"gpt-6.1-sol"),for:s)
    try check(s.record.backend == .codex && s.record.codex?.model=="gpt-6.1-sol" && s.record.codex?.effort=="high","Claude at max → Codex at high (closest)")
    try check(ModelFavorites.lastUsed(.chats)==LastModel(backend:.codex,model:"gpt-6.1-sol",effort:"high"),"remembered for Chats")
    favorites.setEffort("low",for:s)
    try check(s.record.codex?.effort=="low" && ModelFavorites.lastUsed(.chats)?.effort=="low","dragging the effort is remembered too")
    try check(ModelFavorites.lastUsed(.studios)==nil,"other kinds are separate")

    // A new Chats session starts there; a named agent that differs keeps its own.
    var fresh=ConversationRecord(model:"opus",effort:"",personality:.neutral);fresh.activeBackend = .claude
    let next=try runtime.insert(fresh)
    ModelFavorites.startLikeLast(next,kind:.chats)
    try check(next.record.backend == .codex && next.record.codex?.model=="gpt-6.1-sol" && next.record.codex?.effort=="low","a new session starts on what Chats last used")
    var named=ConversationRecord(model:"opus",effort:"",personality:.neutral);named.activeBackend = .claude
    let claudeOnly=try runtime.insert(named)
    ModelFavorites.startLikeLast(claudeOnly,kind:.chats,requested:.claude)
    try check(claudeOnly.record.backend == .claude && claudeOnly.record.model=="opus","New Claude Session stays on Claude")

    // Stars.
    favorites.set([])
    favorites.toggle(ModelChoice(backend:.claude,model:"opus"));favorites.toggle(ModelChoice(backend:.codex,model:nil))
    try check(favorites.favorites.count==2 && favorites.isFavorite(ModelChoice(backend:.codex,model:nil)),"starring adds to the end")
    favorites.move(fromOffsets:[1],toOffset:0)
    try check(favorites.favorites.first==ModelChoice(backend:.codex,model:nil),"and they reorder")
    favorites.toggle(ModelChoice(backend:.claude,model:"opus"))
    try check(favorites.favorites==[ModelChoice(backend:.codex,model:nil)],"unstarring removes")
    for s in runtime.sessions {s.shutdown()}
    try runtime.flush()
    print("PASS model favorites")
}
Task { @MainActor in do {try await test();exit(0)} catch {print("FAIL \(error.localizedDescription)");exit(1)} }
RunLoop.main.run()

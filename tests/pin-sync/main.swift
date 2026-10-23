import Foundation
import Darwin
// Pins from the phone: the service keeps the Mac's list (a list preference, saved and read
// back) and tells the app, which adopts it.
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeFailure(message) }
    print("PASS \(message)")
}
@MainActor func test() async throws {
    let runtime = try ConversationRuntime(root: RuntimePaths.data)
    var events: [RuntimeEvent] = []
    runtime.onEvent = { events.append($0) }
    let a = try runtime.insert(ConversationRecord(model: "default", effort: "", personality: .neutral))
    let b = try runtime.insert(ConversationRecord(model: "default", effort: "", personality: .neutral))
    try RuntimePreferences.update(["macPinnedThreads": .array([.string(a.id.uuidString)])])
    try check(AppPreferences.defaults.stringArray(forKey: "macPinnedThreads") == [a.id.uuidString], "a list preference is stored")
    let context = DaemonContext(runtime)
    context.setPinned(b, true)
    try check(AppPreferences.defaults.stringArray(forKey: "macPinnedThreads") == [a.id.uuidString, b.id.uuidString], "pinning from the phone appends")
    try check(events.last?.kind == "pins.changed" && events.last?.payload?.array?.count == 2, "and tells the app the new list")
    context.setPinned(b, true)
    try check(AppPreferences.defaults.stringArray(forKey: "macPinnedThreads")?.count == 2, "pinning twice doesn't duplicate")
    context.setPinned(a, false)
    try check(AppPreferences.defaults.stringArray(forKey: "macPinnedThreads") == [b.id.uuidString], "unpinning removes")
    // Saved: a restarted service reads it back.
    AppPreferences.defaults.removeObject(forKey: "macPinnedThreads")
    try RuntimePreferences.load()
    try check(AppPreferences.defaults.stringArray(forKey: "macPinnedThreads") == [b.id.uuidString], "the list survives a restart")
    for s in runtime.sessions { s.shutdown() }
    try runtime.flush()
    print("PASS pin sync")
}
Task { @MainActor in do { try await test(); exit(0) } catch { print("FAIL \(error.localizedDescription)"); exit(1) } }
RunLoop.main.run()

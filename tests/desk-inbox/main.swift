import Foundation
import Darwin
// The always-on Desk's inbox (plans/always-on-desk.md): duplicates dropped; a burst is one
// run; one run at a time, with events that arrive mid-run in the next; a failed run retries,
// then gives up; a crash mid-run is retried after a restart.
func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure("FAIL: " + text) }; print("PASS: \(text)")
}
@MainActor func wait(_ what: String, seconds: Double = 5, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() { if Date() > until { throw RuntimeFailure("Timed out: \(what)") }; try await Task.sleep(for: .milliseconds(10)) }
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-test-desk-inbox."))
    let file = root.appendingPathComponent("Desk/inbox.json")
    DeskInbox.settle = .milliseconds(150)
    func event(_ id: String, _ kind: String = "task.updated") -> DeskEvent {
        DeskEvent(source: "clickup", sourceEventID: id, kind: kind, title: "Task " + id)
    }

    var inbox = DeskInbox(file: file)
    var batches: [[String]] = []
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false
    var failNext = 0
    inbox.runner = { events in
        batches.append(events.map(\.sourceEventID))
        if holdNext { holdNext = false; await withCheckedContinuation { gate = $0 } }
        if failNext > 0 { failNext -= 1; throw RuntimeFailure("agent failed") }
    }

    // Duplicates are dropped.
    try check(inbox.add(event("a")), "a new change is added")
    try check(!inbox.add(event("a")), "the same change again is dropped")
    // A burst is one run.
    inbox.add(event("b")); inbox.add(event("c"))
    try await wait("the first batch") { inbox.events.allSatisfy { $0.status == .done } }
    try check(batches == [["a", "b", "c"]], "three changes in a burst make one run (\(batches))")

    // One run at a time: what arrives mid-run goes in the next.
    holdNext = true
    inbox.add(event("d"))
    try await wait("the held run to start") { gate != nil }
    inbox.add(event("e"))
    try await Task.sleep(for: .milliseconds(400))
    try check(batches.count == 2 && inbox.isRunning, "a change mid-run doesn't start a second run")
    gate?.resume(); gate = nil
    try await wait("the next batch") { batches.count == 3 && !inbox.isRunning }
    try check(batches[1] == ["d"] && batches[2] == ["e"], "it goes in the next run (\(batches))")

    // A failed run is retried, then given up on after three tries.
    failNext = 1
    inbox.add(event("f"))
    try await wait("the retry") { inbox.events.first { $0.sourceEventID == "f" }?.status == .done }
    try check(inbox.events.first { $0.sourceEventID == "f" }?.attempts == 2, "a failed run is tried again, and succeeds")
    failNext = 5
    inbox.add(event("g"))
    try await wait("giving up", seconds: 8) { inbox.events.first { $0.sourceEventID == "g" }?.status == .failed }
    let g = inbox.events.first { $0.sourceEventID == "g" }
    try check(g?.attempts == DeskInbox.maxAttempts && g?.problem == "agent failed", "after three failures it stops, with the reason")
    failNext = 0

    // A crash mid-run: a new inbox on the same file tries those events again.
    holdNext = true
    inbox.add(event("h"))
    try await wait("the run to start") { gate != nil }
    try check(inbox.events.first { $0.sourceEventID == "h" }?.status == .running, "mid-run, the event is running")
    let saved = try Data(contentsOf: file)
    inbox = DeskInbox(file: file)   // as after a crash: the old one never finishes
    var after: [[String]] = []
    inbox.runner = { events in after.append(events.map(\.sourceEventID)) }
    try check(inbox.pending.map(\.sourceEventID) == ["h"] && saved.count > 0, "after a restart, the cut-short event is pending again")
    try check(!inbox.add(event("a")), "the restarted inbox still knows what it has seen")
    inbox.wake(now: true)
    try await wait("the retried run") { after == [["h"]] }
    try check(inbox.events.first { $0.sourceEventID == "h" }?.status == .done, "and runs it once")
    print("ALL PASS")
}
MainActor.assumeIsolated {
    Task { @MainActor in do { try await run(); exit(0) } catch { print(error); exit(1) } }
}
RunLoop.main.run()

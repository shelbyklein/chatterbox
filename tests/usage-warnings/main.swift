@testable import ChatterboxTestEngine
import Foundation

// Usage warnings and burn rate (Usage.swift): a limit warns at 50%, 20% and 5% left, once per
// level per window, even across restarts; skipping past levels warns once, at the lowest; a
// reset starts the levels over. The burn rate is the pace over the last hour.

@MainActor func run() throws {
    func check(_ ok: Bool, _ what: String) throws { if !ok { throw NSError(domain: "FAIL: " + what, code: 1) }; print("PASS " + what) }
    AppPreferences.defaults.removeObject(forKey: "usageWarnedLevels")
    let limits = UsageLimits()
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    limits.now = { clock }
    var warnings: [UsageWarning] = []
    limits.onWarning = { warnings.append($0) }
    let reset = clock.addingTimeInterval(5 * 3600)
    func claude(_ used: Double, resets: Date = reset) {
        limits.updateClaude(["unifiedWindows": ["five_hour": ["utilization": .number(used), "resetsAt": .number(resets.timeIntervalSince1970)]]])
    }

    claude(0.30)
    try check(warnings.isEmpty, "70% left: no warning")
    try check(limits.claude.first?.burn == nil, "one reading: no burn rate yet")
    clock += 30 * 60; claude(0.42)
    let burn = limits.claude.first?.burn
    try check(burn.map { abs($0.perHour - 0.24) < 0.001 } == true, "burn rate: 12 points in 30 minutes is 24% an hour (\(String(describing: burn)))")
    try check(burn?.runsOutAt.map { abs($0.timeIntervalSince(clock) - 0.58 / 0.24 * 3600) < 1 } == true, "runs out at this pace in (58/24) hours")
    try check(burn?.beforeReset == true, "…which is before the reset")
    clock += 10 * 60; claude(0.51)
    try check(warnings.map(\.left) == [0.5], "warns at 50% left")
    try check(warnings.first?.title == "Claude: 50% of your 5-hour limit left", warnings.first?.title ?? "-")
    try check(warnings.first?.body.contains("an hour") == true && warnings.first?.body.contains("runs out") == true, "the warning carries the pace: \(warnings.first?.body ?? "")")
    clock += 5 * 60; claude(0.55)
    try check(warnings.count == 1, "not again at the same level")

    // A restart (a new UsageLimits) doesn't repeat it.
    let restarted = UsageLimits()
    restarted.now = { clock }
    var again: [UsageWarning] = []
    restarted.onWarning = { again.append($0) }
    restarted.updateClaude(["unifiedWindows": ["five_hour": ["utilization": .number(0.56), "resetsAt": .number(reset.timeIntervalSince1970)]]])
    try check(again.isEmpty, "a restart doesn't warn again for the same level")

    // Jumping past 20% straight to 4% left: one warning, at 5%.
    clock += 10 * 60; claude(0.96)
    try check(warnings.map(\.left) == [0.5, 0.05], "skipping levels warns once, at the lowest (\(warnings.map(\.left)))")
    clock += 5 * 60; claude(0.99)
    try check(warnings.count == 2, "nothing below 5%")

    // The window resets: the levels start over.
    let next = reset.addingTimeInterval(5 * 3600)
    clock = reset + 60; claude(0.10, resets: next)
    try check(limits.claude.first?.burn == nil, "a reset starts the burn rate over")
    clock += 20 * 60; claude(0.81, resets: next)
    try check(warnings.map(\.left) == [0.5, 0.05, 0.2], "after a reset it warns again (\(warnings.map(\.left)))")

    // Codex: a percent snapshot, same rules.
    limits.updateCodex(["primary": ["usedPercent": .number(60), "windowDurationMins": .number(300), "resetsAt": .number(next.timeIntervalSince1970)]])
    try check(warnings.last?.backend == .codex && warnings.last?.left == 0.5 && warnings.last?.title == "Codex: 50% of your 5-hour limit left", "Codex warns too")

    // Not going up: no run-out time.
    let flat = UsageBurn.from([(clock, 0.3), (clock + 600, 0.3)], now: clock + 600, resetsAt: nil)
    try check(flat?.perHour == 0 && flat?.runsOutAt == nil && flat?.beforeReset == false, "a flat window has no run-out time")
    AppPreferences.defaults.removeObject(forKey: "usageWarnedLevels")
    print("PASS: usage warnings at 50/20/5% left, once per level per window, kept across restarts; burn rate and run-out time")
}

MainActor.assumeIsolated {
    do { try run(); exit(0) } catch { print(error); exit(1) }
}

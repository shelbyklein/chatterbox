import Foundation
// The service's pressure level (Core/ChatterboxRuntime/MacPressure.swift) from recorded readings,
// one every 10 s as PressureMonitor takes them: up as soon as a condition holds (the load ones
// once sustained), down only after the lower level's conditions have held for 3 minutes.
var failures = 0
func check(_ ok: Bool, _ text: String) {
    if ok { print("PASS: \(text)") } else { print("FAIL: \(text)"); failures += 1 }
}
typealias R = MacPressure.Readings
let GB: Int64 = 1 << 30
let start = Date(timeIntervalSince1970: 1_800_000_000)
/// Feeds `readings(t)` every 10 s from `from` to `to` seconds; answers the changes, by time.
func run(_ e: inout MacPressure.Evaluator, from: Int, to: Int, _ readings: (Int) -> R) -> [(Int, MacPressure.Change)] {
    var changes: [(Int, MacPressure.Change)] = []
    for t in stride(from: from, through: to, by: 10) {
        if let change = e.update(readings(t), now: start.addingTimeInterval(TimeInterval(t))) { changes.append((t, change)) }
    }
    return changes
}
func calm(_ t: Int) -> R { R(memory: .normal, swapUsed: 2 * GB, load1: 6, cores: 16) }
func load(_ value: Double) -> (Int) -> R { { _ in R(memory: .normal, swapUsed: 2 * GB, load1: value, cores: 16) } }

// Calm: OK, no change.
do {
    var e = MacPressure.Evaluator()
    let changes = run(&e, from: 0, to: 600, calm)
    check(changes.isEmpty && e.level == .ok, "calm readings stay OK")
    check(e.summary.contains("load 6.0 on 16 cores"), "at OK the summary is the readings: \(e.summary)")
}

// Busy by load: above 1.5x the cores (24) sustained 2 minutes; down after 3 calm minutes.
do {
    var e = MacPressure.Evaluator()
    var changes = run(&e, from: 0, to: 110, load(30))
    check(changes.isEmpty && e.level == .ok, "load 30 on 16 cores for under 2 min: still OK")
    changes = run(&e, from: 120, to: 120, load(30))
    check(changes.first?.0 == 120 && changes.first?.1.to == .busy && e.level == .busy, "sustained 2 min: Busy")
    check(e.reasons.first?.contains("load 30 on 16 cores (over 1.5\u{00D7}) for 2 min") == true, "with why: \(e.reasons)")
    changes = run(&e, from: 130, to: 300, load(10))
    check(changes.isEmpty && e.level == .busy, "calm again for under 3 min: still Busy")
    changes = run(&e, from: 310, to: 320, load(10))
    check(changes.first?.0 == 310 && changes.first?.1.to == .ok, "calm for 3 min: back to OK")
}

// Flapping: load over and under the line never sustains, so it never goes Busy.
do {
    var e = MacPressure.Evaluator()
    let changes = run(&e, from: 0, to: 900) { t in R(load1: (t / 10) % 6 == 5 ? 10 : 40, cores: 16) }
    check(changes.isEmpty && e.level == .ok, "load that dips every minute isn't sustained: OK")
}

// Overloaded by load: over 3x (48) for 1 minute, straight from OK; then down a step at a time.
do {
    var e = MacPressure.Evaluator()
    var changes = run(&e, from: 0, to: 50, load(60))
    check(changes.isEmpty, "load 60 for under a minute: OK")
    changes = run(&e, from: 60, to: 60, load(60))
    check(changes.first?.1 == MacPressure.Change(from: .ok, to: .overloaded, reasons: e.reasons) && e.reasons.first?.contains("over 3\u{00D7}") == true,
          "sustained a minute: Overloaded, from OK (\(e.reasons))")
    changes = run(&e, from: 70, to: 240, load(30))
    check(changes.isEmpty && e.level == .overloaded, "under 3x for under 3 min: still Overloaded")
    changes = run(&e, from: 250, to: 250, load(30))
    check(changes.first?.1.to == .busy && e.reasons.first?.contains("over 1.5\u{00D7}") == true, "under 3x for 3 min: Busy, still over 1.5x (\(e.reasons))")
    // A spike back over 3x during the calm resets the clock, without going back up (not sustained).
    changes = run(&e, from: 260, to: 400, load(8))
    changes += run(&e, from: 410, to: 410, load(50))
    changes += run(&e, from: 420, to: 580, load(8))
    check(changes.isEmpty && e.level == .busy, "a spike resets the calm clock: still Busy")
    changes = run(&e, from: 590, to: 600, load(8))
    check(changes.first?.0 == 600 && changes.first?.1.to == .ok, "3 calm minutes after the spike: OK")
}

// Overloaded to OK in one step when everything calms at once.
do {
    var e = MacPressure.Evaluator()
    _ = run(&e, from: 0, to: 60, load(60))
    let changes = run(&e, from: 70, to: 250, load(4))
    check(changes.count == 1 && changes[0].0 == 250 && changes[0].1.to == .ok, "from Overloaded straight to OK after 3 calm minutes")
}

// Swap growing over 1 GB in 5 minutes: Overloaded at once; calm only once the growth is out of
// the window, then 3 minutes.
do {
    var e = MacPressure.Evaluator()
    var changes = run(&e, from: 0, to: 290) { t in R(swapUsed: 2 * GB + Int64(t) * GB / 1000, load1: 6, cores: 16) }   // +0.29 GB in 5 min
    check(changes.isEmpty, "slow swap growth: OK")
    changes = run(&e, from: 300, to: 400) { t in R(swapUsed: 2 * GB + Int64(t - 290) * GB / 80, load1: 6, cores: 16) }  // +1.4 GB in 110 s
    let at = changes.first?.0 ?? -1
    check(changes.first?.1.to == .overloaded && e.reasons.first?.contains("swap grew") == true, "swap +1 GB within 5 min: Overloaded at \(at) s (\(e.reasons))")
    let top = 2 * GB + 110 * GB / 80
    changes = run(&e, from: 410, to: 1100) { _ in R(swapUsed: top, load1: 6, cores: 16) }
    let down = changes.first { $0.1.to == .ok }?.0 ?? -1
    // The growth leaves the 5-minute window about 5 min after it began, then 3 calm minutes.
    check(down >= at + 180 && down >= 300 + 300 + 180 - 120 && e.level == .ok, "swap steady: OK once the growth is out of the window and 3 min have passed (\(down) s)")
    check(e.swapGrowth == 0, "no growth in the window now")
}

// Memory pressure and thermal state: at once, up; down after 3 minutes.
do {
    var e = MacPressure.Evaluator()
    var changes = run(&e, from: 0, to: 0) { _ in R(memory: .warning, load1: 4) }
    check(changes.first?.1.to == .busy && e.reasons == ["memory pressure warning"], "memory warning: Busy at once")
    changes = run(&e, from: 10, to: 10) { _ in R(memory: .critical, load1: 4) }
    check(changes.first?.1 == MacPressure.Change(from: .busy, to: .overloaded, reasons: ["memory pressure critical"]), "memory critical: Overloaded at once")
    changes = run(&e, from: 20, to: 190) { _ in R(memory: .warning, load1: 4) }
    check(e.level == .overloaded, "warning again: Overloaded holds for 3 min")
    changes = run(&e, from: 200, to: 200) { _ in R(memory: .warning, load1: 4) }
    check(changes.first?.1.to == .busy && e.reasons == ["memory pressure warning"], "then Busy, for the warning")
    changes = run(&e, from: 210, to: 400) { _ in R(memory: .normal, load1: 4) }
    check(changes.first?.0 == 390 && changes.first?.1.to == .ok, "normal for 3 min: OK")

    var hot = MacPressure.Evaluator()
    changes = run(&hot, from: 0, to: 0) { _ in R(load1: 4, thermal: .serious) }
    check(changes.first?.1.to == .busy && hot.reasons == ["thermal state serious"], "thermal serious: Busy")
    changes = run(&hot, from: 10, to: 10) { _ in R(load1: 4, thermal: .critical) }
    check(changes.first?.1.to == .overloaded, "thermal critical: Overloaded")
    changes = run(&hot, from: 20, to: 200) { _ in R(load1: 4, thermal: .fair) }
    check(hot.level == .ok, "fair for 3 min: OK")
}

// Thresholds from the preferences; nonsense values keep the defaults.
do {
    let prefs: [String: Any] = ["pressure.busyLoad": 2.0, "pressure.overloadedLoad": "4", "pressure.swapGrowthGB": 2, "pressure.stepDownMinutes": 1,
                                "pressure.busyLoadSeconds": -5, "pressure.overloadedLoadSeconds": "x"]
    let t = MacPressure.Thresholds(preferences: { prefs[$0] })
    check(t.busyLoad == 2 && t.overloadedLoad == 4 && t.swapGrowth == 2 * GB && t.stepDownAfter == 60 && t.busyLoadFor == 120 && t.overloadedLoadFor == 60,
          "preferences set the thresholds; bad values keep the defaults")
    var e = MacPressure.Evaluator(thresholds: t)
    var changes = run(&e, from: 0, to: 200, load(30))
    check(changes.isEmpty, "load 30 is under 2x 16 cores: OK")
    changes = run(&e, from: 210, to: 330, load(40))
    check(changes.first?.1.to == .busy, "over 2x for 2 min: Busy")
    changes = run(&e, from: 340, to: 400, load(5))
    check(changes.first?.0 == 400 && changes.first?.1.to == .ok, "a 1-minute step down")
    check(MacPressure.Thresholds(preferences: { _ in nil }) == .defaults, "nothing set: the defaults")
}

// Agents' builds: half the cores at OK, a quarter under pressure, as CMake, make and Cargo read them.
do {
    check(MacPressure.buildJobs(level: .ok, cores: 16) == 8 && MacPressure.buildJobs(level: .busy, cores: 16) == 4
          && MacPressure.buildJobs(level: .overloaded, cores: 16) == 4 && MacPressure.buildJobs(level: .busy, cores: 2) == 1, "build jobs: 8 / 4 / 4 on 16 cores, at least 1")
    let env = MacPressure.agentBuildEnvironment(level: .busy, cores: 16)
    check(env == ["CMAKE_BUILD_PARALLEL_LEVEL": "4", "MAKEFLAGS": "-j4", "CARGO_BUILD_JOBS": "4"], "an agent's environment at Busy: \(env)")
}

// Renicing: only build processes under a Chatterbox host (real or Dev), only under pressure,
// only those not already that nice. Yours (Xcode's clang, your Terminal's make) are never named.
do {
    let ps = """
      1     0   0 /sbin/launchd
    500     1   0 /Applications/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost
    501   500  10 /Users/x/.local/bin/claude
    502   501  10 /bin/zsh
    503   502  10 /opt/homebrew/bin/cmake
    504   503  10 /opt/homebrew/bin/ninja
    505   504  10 /usr/bin/clang
    506   504  10 /Library/Developer/CommandLineTools/usr/bin/clang
    507   504  15 /usr/bin/clang
    508   501  10 /opt/homebrew/bin/node
    600     1   0 /Applications/Chatterbox Dev.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost
    601   600  10 /opt/homebrew/bin/codex
    602   601  10 /Users/x/.cargo/bin/cargo
    603   602  10 /Users/x/.rustup/toolchains/stable/bin/rustc
    700     1   0 /Applications/Xcode.app/Contents/MacOS/Xcode
    701   700   0 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend
    702   700   0 /usr/bin/clang
    800     1   0 /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
    801   800   0 /bin/zsh
    802   801   0 /usr/bin/make
    garbage line
    """
    let rows = MacPressure.processRows(fromPS: ps)
    check(rows.count == 20 && rows.first { $0.pid == 600 }?.name == "ChatterboxHost" && rows.first { $0.pid == 506 }?.name == "clang",
          "ps rows: pid, parent, nice and the program's name, a path with spaces included")
    check(MacPressure.reniceTargets(rows, level: .ok).isEmpty, "at OK nothing is reniced")
    let targets = Set(MacPressure.reniceTargets(rows, level: .busy))
    check(targets == [503, 504, 505, 506, 508, 602, 603], "Busy: the builds under both hosts (cmake, ninja, clang, node, cargo, rustc): \(targets.sorted())")
    check(!targets.contains(507), "one already at +15 is left")
    check(!targets.contains(501) && !targets.contains(502) && !targets.contains(601), "the agents and their shells aren't build tools: left at +10")
    check(targets.isDisjoint(with: [700, 701, 702, 800, 801, 802]), "Xcode's swift-frontend and clang, and make in your Terminal, are never touched")
    check(Set(MacPressure.reniceTargets(rows, level: .overloaded)) == targets, "Overloaded: the same")
}

if failures > 0 { print("\(failures) failed"); exit(1) }
print("All pressure level checks passed")

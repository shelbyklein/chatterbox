import Foundation
// The service's pressure level (Core/ChatterboxRuntime/MacPressure.swift) from recorded readings,
// one every 10 s as PressureMonitor takes them: Overloaded once CPU or memory has been over 95%
// for 2 minutes, back to OK after 3 calm minutes.
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
func calm(_ t: Int) -> R { R(memory: .normal, swapUsed: 2 * GB, load1: 6, cores: 16, cpuBusy: 0.3, memoryUsed: 0.6) }
func use(cpu: Double?, memory: Double?) -> (Int) -> R { { _ in R(memory: .normal, swapUsed: 2 * GB, load1: 6, cores: 16, cpuBusy: cpu, memoryUsed: memory) } }

// Only truly critical counts (Shelby, 2026-11-09): CPU or memory over 95% for 2 minutes.
// Calm: OK, no change.
do {
    var e = MacPressure.Evaluator()
    let changes = run(&e, from: 0, to: 600, calm)
    check(changes.isEmpty && e.level == .ok, "calm readings stay OK")
    check(e.summary.contains("CPU 30% in use, memory 60% used"), "at OK the summary is the readings: \(e.summary)")
}

// What used to trip it no longer does: high load, swap growing, memory warning, running hot.
do {
    var e = MacPressure.Evaluator()
    var swap: Int64 = 0
    let changes = run(&e, from: 0, to: 900) { t in
        swap += GB / 2
        return R(memory: .warning, swapUsed: swap, load1: 113, cores: 16, thermal: t > 300 ? .critical : .serious, cpuBusy: 0.9, memoryUsed: 0.9)
    }
    check(changes.isEmpty && e.level == .ok, "load 113, swap growing, memory warning, critical heat, CPU and memory at 90%: still OK")
}

// CPU over 95% for 2 minutes: Overloaded, straight from OK (never Busy); back to OK after 3 calm minutes.
do {
    var e = MacPressure.Evaluator()
    var changes = run(&e, from: 0, to: 110, use(cpu: 0.97, memory: 0.5))
    check(changes.isEmpty && e.level == .ok, "CPU 97% for under 2 min: still OK")
    changes = run(&e, from: 120, to: 120, use(cpu: 0.97, memory: 0.5))
    check(changes.first?.0 == 120 && changes.first?.1 == MacPressure.Change(from: .ok, to: .overloaded, reasons: e.reasons), "2 min: Overloaded, from OK")
    check(e.reasons == ["CPU 97% in use for 2 min"], "with why: \(e.reasons)")
    changes = run(&e, from: 130, to: 300, use(cpu: 0.5, memory: 0.5))
    check(changes.isEmpty && e.level == .overloaded, "calm for under 3 min: still Overloaded")
    changes = run(&e, from: 310, to: 310, use(cpu: 0.5, memory: 0.5))
    check(changes.first?.1 == MacPressure.Change(from: .overloaded, to: .ok, reasons: e.reasons), "calm for 3 min: straight back to OK")
}

// Memory over 95% alone counts too, with the CPU idle.
do {
    var e = MacPressure.Evaluator()
    let changes = run(&e, from: 0, to: 120, use(cpu: 0.05, memory: 0.96))
    check(changes.first?.0 == 120 && changes.first?.1.to == .overloaded && e.reasons == ["memory 96% used for 2 min"], "memory 96% for 2 min: Overloaded (\(e.reasons))")
}

// 95% exactly counts; a dip under it restarts the 2 minutes.
do {
    var edge = MacPressure.Evaluator()
    check(run(&edge, from: 0, to: 120, use(cpu: 0.95, memory: 0.2)).first?.1.to == .overloaded, "CPU at exactly 95%: counts")
    var e = MacPressure.Evaluator()
    let changes = run(&e, from: 0, to: 240) { t in t == 90 ? calm(t) : R(cores: 16, cpuBusy: 0.99, memoryUsed: 0.5) }
    check(changes.first?.0 == 220 && changes.first?.1.to == .overloaded, "a dip at 90 s restarts the clock: Overloaded at 220 s")
}

// Memory use unknown (an older reading): the kernel's critical pressure counts in its place.
do {
    var e = MacPressure.Evaluator()
    check(run(&e, from: 0, to: 120) { _ in R(memory: .critical, cores: 16, cpuBusy: 0.1) }.first?.1.to == .overloaded, "memory use unknown, kernel critical for 2 min: Overloaded")
    var unknown = MacPressure.Evaluator()
    check(run(&unknown, from: 0, to: 600) { _ in R(memory: .warning, load1: 80, cores: 16) }.isEmpty, "nothing known and no critical memory: OK")
}

// Busy is off by default; set, it works as before (tests and the hold machinery use it).
do {
    var t = MacPressure.Thresholds(); t.busyCPU = 0.8
    var e = MacPressure.Evaluator(thresholds: t)
    var changes = run(&e, from: 0, to: 120, use(cpu: 0.85, memory: 0.5))
    check(changes.first?.1.to == .busy && e.reasons == ["CPU 85% in use for 2 min"], "busyCPU 80%: CPU 85% for 2 min is Busy")
    changes = run(&e, from: 130, to: 250, use(cpu: 0.97, memory: 0.5))
    check(changes.first?.1.to == .overloaded, "then over 95% for 2 min: Overloaded")
}

// Thresholds from the preferences; nonsense values keep the defaults.
do {
    let set = { (prefs: [String: Any]) in MacPressure.Thresholds(preferences: { prefs[$0] }) }
    let t = set(["pressure.criticalCPUPercent": 90, "pressure.criticalMemoryPercent": "92", "pressure.criticalSeconds": 60, "pressure.stepDownMinutes": 1])
    check(t.criticalCPU == 0.9 && t.criticalMemory == 0.92 && t.criticalFor == 60 && t.stepDownAfter == 60 && t.busyCPU == nil, "set from the preferences")
    let bad = set(["pressure.criticalCPUPercent": 150, "pressure.criticalMemoryPercent": 10, "pressure.criticalSeconds": -5])
    check(bad == .defaults, "out of range: the defaults")
    check(set([:]) == .defaults && MacPressure.Thresholds.defaults.criticalCPU == 0.95 && MacPressure.Thresholds.defaults.criticalMemory == 0.95, "nothing set: 95% / 95%")
}

do {
    // The CPU share from the kernel's tick counters [user, system, idle, nice].
    check(MacPressure.cpuBusy(from: nil, to: [1, 1, 1, 1]) == nil, "no earlier reading: unknown")
    check(MacPressure.cpuBusy(from: [10, 10, 10, 10], to: [10, 10, 10, 10]) == nil, "no ticks between: unknown")
    check(MacPressure.cpuBusy(from: [0, 0, 0, 0], to: [150, 30, 800, 20]) == 0.2, "200 busy of 1000 ticks: 20%")
    let wrap = UInt64(UInt32.max)
    check(MacPressure.cpuBusy(from: [wrap - 99, 0, 0, 0], to: [100, 0, 200, 0]) == 0.5, "a counter that wrapped: 200 busy of 400 ticks")
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

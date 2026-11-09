import Foundation
import Darwin

/// Watches how hard the Mac is working and holds Chatterbox's own work back before it's too
/// much (MacPressure has the levels). Every 10 s, and at once on a memory pressure event, it
/// reads memory pressure, swap (and its growth), the load averages against the cores, how much
/// of the CPU was in use since the last look (load counts only while the CPU is busy too) and the
/// thermal state, and works out OK, Busy or Overloaded. On a change it logs the level with the
/// readings (chatterboxd.log), tells the app ("pressure.changed") and lets held work threads go
/// (ChatSession+Pressure). Entering Overloaded sends one push (at most every 30 minutes).
///
/// Busy: builds one at a time (build-lock.sh reads pressure.json), idle simulators shut down
/// after 5 minutes, new work threads wait to start. Overloaded: also new builds wait, unused
/// simulators shut down at once, work threads don't start their next turn. Never a build
/// killed, a reply stopped, or anything outside Chatterbox touched.
///
/// Both services (real and Dev) monitor and hold their own work threads; only the one that acts
/// for the Mac (as SimulatorSweeper decides) writes pressure.json, sweeps simulators and pushes.
/// A test's service never writes the Mac's file (CHATTERBOX_PRESSURE_FILE names its own).
@MainActor final class PressureMonitor {
    static var shared: PressureMonitor?
    static let holdsWorkKey = "pressureHoldsWork"
    /// Where build-lock.sh looks.
    static var stateFile: URL {
        if let path = ProcessInfo.processInfo.environment["CHATTERBOX_PRESSURE_FILE"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/Chatterbox/pressure.json")
    }

    let runtime: ConversationRuntime
    private let reader: () -> MacPressure.Readings
    private(set) var evaluator: MacPressure.Evaluator
    private let interval: TimeInterval
    private var timer: Timer?
    private var memoryEvents: DispatchSourceMemoryPressure?
    private var lastPush: Date?
    private(set) var snapshot: Companion.Pressure?
    /// Work threads held now.
    private(set) var waiting = 0
    /// Whether this service writes pressure.json, sweeps simulators and pushes (checked each look).
    var actsForMac: () -> Bool = { SimulatorSweeper.isInstalledService && SimulatorSweeper.actsForThisMac }
    /// After a change, or held work threads changed: the app is told.
    var onChange: (Companion.Pressure) -> Void = { _ in }

    init(runtime: ConversationRuntime, reader: @escaping () -> MacPressure.Readings = PressureMonitor.readMac, interval: TimeInterval = 10,
         thresholds: MacPressure.Thresholds? = nil) {
        self.runtime = runtime
        self.reader = reader
        self.interval = interval
        evaluator = MacPressure.Evaluator(thresholds: thresholds ?? MacPressure.Thresholds(preferences: { AppPreferences.defaults.object(forKey: $0) }))
        fixedThresholds = thresholds != nil
    }

    static var holdsWorkPreference: Bool { AppPreferences.defaults.object(forKey: holdsWorkKey) as? Bool ?? true }

    func start() {
        PressureHooks.snapshot = { [weak self] in self?.snapshot }
        PressureHooks.holdsChanged = { [weak self] in self?.holdsChanged() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // A memory pressure event looks at once, rather than up to 10 s later.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        source.resume()
        memoryEvents = source
        tick()
    }

    func stop() { timer?.invalidate(); timer = nil; memoryEvents?.cancel(); memoryEvents = nil }

    /// One look: read, decide, act.
    func tick(now: Date = Date()) {
        // Thresholds follow Settings as they change.
        if !fixedThresholds {
            let thresholds = MacPressure.Thresholds(preferences: { AppPreferences.defaults.object(forKey: $0) })
            if thresholds != evaluator.thresholds { evaluator.thresholds = thresholds }
        }
        let readings = reader()
        let change = evaluator.update(readings, now: now)
        apply(change, now: now)
    }

    /// Thresholds handed in (tests) stay; else they follow Settings.
    private var fixedThresholds = false

    private func apply(_ change: MacPressure.Change?, now: Date) {
        let level = evaluator.level
        MacPressure.current = level
        MacPressure.holdsWork = Self.holdsWorkPreference
        let acts = actsForMac()
        if let change, let readings = evaluator.last {
            RuntimeHooks.note("Mac pressure \(change.from.label) \u{2192} \(change.to.label): \(change.reasons.joined(separator: "; ")) [\(MacPressure.Evaluator.readingsLine(readings)), load \(MacPressure.Evaluator.load(readings.load5))/\(MacPressure.Evaluator.load(readings.load15)) over 5/15 min, swap +\(MacPressure.Evaluator.gigabytes(evaluator.swapGrowth)) in 5 min]")
            if acts { SimulatorSweeper.shared?.pressureChanged(level) }
            if change.to == .overloaded, acts, lastPush.map({ now.timeIntervalSince($0) >= 30 * 60 }) ?? true {
                lastPush = now
                MobilePush.shared.post(title: "Mac overloaded", body: "Chatterbox is holding its own work back: \(evaluator.summary)", chat: nil, kind: "pressure")
            }
        }
        // Agents' builds go nicer still while the Mac is under pressure (never stopped).
        if acts, level != .ok { reniceAgentBuilds(level) }
        waiting = ChatSession.releasePressureHolds(in: runtime.sessions)
        let previous = snapshot
        snapshot = makeSnapshot(now: now)
        if acts, let snapshot { write(snapshot) }
        if change != nil || previous?.waiting != snapshot?.waiting || previous?.holding != snapshot?.holding, let snapshot { onChange(snapshot) }
    }

    private func holdsChanged() {
        waiting = runtime.sessions.filter { $0.record.pressureHold != nil }.count
        guard let previous = snapshot else { return }
        let updated = makeSnapshot(now: previous.updatedAt)
        snapshot = updated
        if updated?.waiting != previous.waiting, let updated { onChange(updated) }
    }

    func makeSnapshot(now: Date) -> Companion.Pressure? {
        guard let r = evaluator.last else { return nil }
        let gb = { (bytes: Int64) in (Double(bytes) / Double(1 << 30) * 10).rounded() / 10 }
        return Companion.Pressure(level: evaluator.level.rawValue, since: evaluator.since, updatedAt: now, updated: Int(now.timeIntervalSince1970),
                                  summary: evaluator.summary, reasons: evaluator.level == .ok ? [] : evaluator.reasons,
                                  memory: r.memory.rawValue, swapUsedGB: gb(r.swapUsed), swapGrowthGB: gb(evaluator.swapGrowth),
                                  compressedGB: r.compressed.map(gb), load1: (r.load1 * 100).rounded() / 100, load5: (r.load5 * 100).rounded() / 100,
                                  load15: (r.load15 * 100).rounded() / 100, cores: r.cores, thermal: r.thermal.rawValue,
                                  holding: Self.holding(evaluator.level, waiting: waiting, holdsWork: MacPressure.holdsWork), waiting: waiting,
                                  cpuPercent: r.cpuBusy.map { Int(($0 * 100).rounded()) }, memoryPercent: r.memoryUsed.map { Int(($0 * 100).rounded()) })
    }

    /// What's held back at `level`, one line each.
    static func holding(_ level: MacPressure.Level, waiting: Int, holdsWork: Bool) -> [String] {
        var lines: [String] = []
        switch level {
        case .ok: break
        case .busy:
            lines.append("Builds run one at a time; agents' builds get a quarter of the cores, at lower priority")
            if SimulatorSweeper.enabled { lines.append("Simulators idle 5 minutes are shut down") }
            if holdsWork { lines.append("New work threads wait to start until the Mac is OK") }
        case .overloaded:
            lines.append("New builds wait (running ones carry on, at lower priority)")
            if SimulatorSweeper.enabled { lines.append("Simulators no build or test is using are shut down") }
            if holdsWork { lines.append("Work threads don't start their next turn; new ones wait to start") }
        }
        if waiting > 0 { lines.append(waiting == 1 ? "1 work thread waiting" : "\(waiting) work threads waiting") }
        return lines
    }

    private var renicing = false
    /// Build processes descending from a Chatterbox host (any: real, Dev) go to nice +15
    /// (MacPressure.reniceTargets); nothing else on the Mac is touched, and nothing is stopped.
    private func reniceAgentBuilds(_ level: MacPressure.Level) {
        guard !renicing else { return }
        renicing = true
        Task.detached(priority: .utility) {
            let rows = MacPressure.processRows(fromPS: String(decoding: SimulatorSweeper.run(["/bin/ps", "-axo", "pid=,ppid=,nice=,comm="]), as: UTF8.self))
            let names = Dictionary(rows.map { ($0.pid, $0.name) }, uniquingKeysWith: { a, _ in a })
            var reniced: [String: Int] = [:]
            for pid in MacPressure.reniceTargets(rows, level: level) where setpriority(PRIO_PROCESS, id_t(pid), MacPressure.buildNice) == 0 {
                reniced[names[pid] ?? "?", default: 0] += 1
            }
            let counts = reniced
            await MainActor.run {
                self.renicing = false
                guard !counts.isEmpty else { return }
                let list = counts.sorted { $0.value > $1.value }.map { "\($0.key) \u{00D7}\($0.value)" }.joined(separator: ", ")
                RuntimeHooks.note("Made agents' build processes nicer (+\(MacPressure.buildNice)), the Mac being \(level == .overloaded ? "overloaded" : "busy"): \(list)")
            }
        }
    }

    /// Written whole, then moved into place, so build-lock.sh never reads half of it.
    private func write(_ snapshot: Companion.Pressure) {
        let url = Self.stateFile
        guard let data = try? Companion.encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Reading the Mac

    nonisolated static func readMac() -> MacPressure.Readings {
        var r = MacPressure.Readings()
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            r.memory = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { r.swapUsed = Int64(swap.xsu_used) }
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { r.load1 = loads[0]; r.load5 = loads[1]; r.load15 = loads[2] }
        r.cores = ProcessInfo.processInfo.activeProcessorCount
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: r.thermal = .nominal
        case .fair: r.thermal = .fair
        case .serious: r.thermal = .serious
        case .critical: r.thermal = .critical
        @unknown default: r.thermal = .nominal
        }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if result == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            r.compressed = Int64(stats.compressor_page_count) * page
            // Used, as Activity Monitor counts it: app memory (internal less purgeable), wired
            // and compressed, of all the Mac's memory.
            let app = max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count))
            let used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
            let total = Int64(ProcessInfo.processInfo.physicalMemory)
            if total > 0 { r.memoryUsed = min(1, max(0, Double(used) / Double(total))) }
        }
        r.cpuBusy = cpuBusySinceLastLook()
        return r
    }

    /// The CPU ticks (user, system, idle, nice; all cores) at the last look.
    nonisolated(unsafe) private static var lastCPUTicks: [UInt64]?

    /// How much of all the cores' time was in use since the last look, 0...1; nil the first time
    /// (or if the counters can't be read). Called from the main thread only (tick).
    nonisolated static func cpuBusySinceLastLook() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3].map { UInt64($0) }
        defer { lastCPUTicks = ticks }
        return MacPressure.cpuBusy(from: lastCPUTicks, to: ticks)
    }
}

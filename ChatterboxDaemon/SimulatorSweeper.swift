import Foundation
import Darwin

/// Shuts down booted iOS simulators nothing on this Mac is using any more (SimulatorSweep has
/// the decision): every ten minutes, each booted device that no running process names, that
/// Simulator.app doesn't have open, that no Chatterbox test run has on record, and that has been
/// that way for half an hour. For the whole Mac, since other projects' test runs leave generic
/// devices booted for days. Devices are only ever shut down, never deleted; each shutdown is
/// logged (chatterboxd.log) with the device's name and the reason.
///
/// Only one service acts: the real one, or Chatterbox Dev's when the real service isn't running.
/// A service with its data folder redirected (a test's) never acts. Settings → Background service
/// turns it off ("idleSimulatorShutdown", a runtime preference, on by default).
/// CHATTERBOX_SIMULATOR_SWEEP_DRY_RUN=1 logs what would be shut down instead.
@MainActor final class SimulatorSweeper {
    static var shared: SimulatorSweeper?
    static let preferenceKey = "idleSimulatorShutdown"
    static var enabled: Bool { AppPreferences.defaults.object(forKey: preferenceKey) as? Bool ?? true }

    private var sweep = SimulatorSweep()
    private var timer: Timer?
    private var sweeping = false
    private let interval: TimeInterval
    private let dryRun = ProcessInfo.processInfo.environment["CHATTERBOX_SIMULATOR_SWEEP_DRY_RUN"] == "1"
    /// Where test runs record the simulators they booted (scripts/lib/test-hygiene.sh).
    static let registry = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/Chatterbox/simulators", isDirectory: true)

    init(interval: TimeInterval = 600) { self.interval = interval }

    func start() {
        guard Self.isInstalledService else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // The first look a minute in, once the service has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + min(60, interval)) { [weak self] in self?.tick() }
    }

    /// The installed service, on its own data folder: a test's service (CHATTERBOX_DATA_DIR
    /// under /tmp) must never touch the Mac's simulators.
    static var isInstalledService: Bool {
        ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"].map { $0.isEmpty } ?? true
    }

    /// Dev steps aside while the real service runs (its socket answers).
    static var actsForThisMac: Bool {
        guard Flavor.current.isDev else { return true }
        return !socketAnswers(Flavor.real.dataDirectory.appendingPathComponent("daemon.sock"))
    }

    private func tick() {
        guard Self.enabled, !sweeping else { return }
        guard Self.actsForThisMac else { return }
        sweeping = true
        Task.detached(priority: .utility) { [registry = Self.registry] in
            let booted = SimulatorSweep.devices(fromSimctlJSON: Self.run(["/usr/bin/xcrun", "simctl", "list", "devices", "booted", "-j"]))
            guard !booted.isEmpty else { return await self.finish([], registered: []) }
            let arguments = String(decoding: Self.run(["/bin/ps", "-axo", "args="]), as: UTF8.self).split(separator: "\n").map(String.init)
            var open: [String] = []
            let simulatorPIDs = String(decoding: Self.run(["/usr/bin/pgrep", "-x", "Simulator"]), as: UTF8.self).split(separator: "\n")
            for pid in simulatorPIDs {
                open += String(decoding: Self.run(["/usr/sbin/lsof", "-p", String(pid), "-Fn"]), as: UTF8.self).split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
            }
            let registered = Set((try? FileManager.default.contentsOfDirectory(atPath: registry.path)) ?? [])
            await self.decide(booted: booted, arguments: arguments, open: open, registered: registered)
        }
    }

    private func finish(_ decisions: [SimulatorSweep.Decision], registered: Set<String>) { sweeping = false }

    private func decide(booted: [SimulatorSweep.Device], arguments: [String], open: [String], registered: Set<String>) {
        let decisions = sweep.evaluate(booted: booted, processArguments: arguments, simulatorAppPaths: open, registered: registered, now: Date())
        for decision in decisions where decision.action == .shutDown {
            let device = decision.device
            if dryRun {
                RuntimeHooks.note("Would shut down simulator \u{201C}\(device.name)\u{201D} (\(device.udid)): \(decision.reason) (dry run)")
                continue
            }
            Task.detached(priority: .utility) {
                _ = Self.run(["/usr/bin/xcrun", "simctl", "shutdown", device.udid])
                await MainActor.run { RuntimeHooks.note("Shut down simulator \u{201C}\(device.name)\u{201D} (\(device.udid)): \(decision.reason)") }
            }
        }
        sweeping = false
    }

    /// Runs a command and returns its output (empty when it fails), waiting at most 30 s.
    nonisolated static func run(_ command: [String]) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Data() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate() }
        return data
    }

    /// Whether a Unix socket at `url` accepts a connection.
    nonisolated static func socketAnswers(_ url: URL) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = url.path
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { strcpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0) }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) == 0 }
        }
    }
}

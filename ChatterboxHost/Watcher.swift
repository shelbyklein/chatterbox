import Foundation

/// `ChatterboxHost --watch <pid> <diagnostics folder>`: watches the app from outside. The app
/// touches `heartbeat` in that folder from its main thread every half second; when it goes
/// quiet for 5 seconds while the app is still alive, this samples the app (its own watchdog
/// may be stuck too) and writes a report, then notes when the app recovered or went away.
/// It exits when the app does.
struct Watcher {
    let pid: pid_t
    let folder: URL

    func run() -> Never {
        let heartbeat = folder.appendingPathComponent("heartbeat")
        var report: URL?
        var stalledSince: Date?
        var staleChecks = 0
        var lastWall = Date(), lastUptime = ProcessInfo.processInfo.systemUptime
        while true {
            sleep(2)
            let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
            // The Mac slept: the heartbeat is stale for a good reason.
            let slept = now.timeIntervalSince(lastWall) - (uptime - lastUptime) > 3
            lastWall = now
            lastUptime = uptime
            if kill(pid, 0) != 0 {
                if let report, let since = stalledSince {
                    append(report, "\n## Outcome\nThe app went away (quit, force-quit, or crashed) after \(Int(now.timeIntervalSince(since))) seconds.\n")
                }
                exit(0)
            }
            let modified = (try? FileManager.default.attributesOfItem(atPath: heartbeat.path)[.modificationDate] as? Date) ?? now
            let silent = now.timeIntervalSince(modified)
            if slept { staleChecks = 0; continue }
            if silent > 5 {
                staleChecks += 1
                if staleChecks == 2, report == nil {
                    stalledSince = modified
                    notify("Chatterbox stopped responding \(Int(silent)) seconds ago. Recording what it's doing.")
                    let sample = Self.sample(pid)
                    let url = folder.appendingPathComponent("\(stamp()) hang (seen from outside).txt")
                    let text = """
                    # Not responding for \(Int(silent))s (seen from outside)
                    \(now.formatted(date: .complete, time: .standard))

                    Chatterbox's main thread stopped touching its heartbeat at \(modified.formatted(date: .omitted, time: .standard)) and was still stuck \(Int(silent)) seconds later, so the background host sampled it from outside. The main thread's stack ("Main Thread" below) is where it was stuck.

                    ## macOS sample (3 seconds)
                    \(sample.isEmpty ? "Couldn't sample." : sample)

                    """
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                    report = url
                }
            } else {
                if let report, let since = stalledSince {
                    append(report, "\n## Outcome\nRecovered after \(Int(now.timeIntervalSince(since))) seconds.\n")
                    notify("Chatterbox is responding again. A report of the freeze is in Settings → Diagnostics.")
                }
                report = nil
                stalledSince = nil
                staleChecks = 0
            }
        }
    }

    private func append(_ url: URL, _ text: String) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
        try? handle.close()
    }

    private func stamp() -> String { ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") }

    private func notify(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(escaped)\" with title \"Chatterbox\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func sample(_ pid: pid_t) -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chatterbox-outside-\(UUID().uuidString).txt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(pid), "3", "-mayDie", "-file", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: file) }
        return String(((try? String(contentsOf: file, encoding: .utf8)) ?? "").prefix(150_000))
    }
}

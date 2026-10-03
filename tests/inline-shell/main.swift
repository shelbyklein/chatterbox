import AppKit
import Darwin
@testable import ChatterboxTestEngine

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("PASS \(message)") } else { print("FAIL \(message)"); exit(1) }
}

/// The process's physical memory footprint, as Activity Monitor counts it.
func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
}

/// How many processes (whoever started them) have this text in their command line.
func processCount(_ marker: String) -> Int {
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-f", marker]
    let out = Pipe()
    pgrep.standardOutput = out
    try? pgrep.run()
    pgrep.waitUntilExit()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return text.split(separator: "\n").count
}

@MainActor func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

@MainActor func expect(_ seconds: Double, _ message: String, _ condition: () -> Bool) async {
    let ok = await waitUntil(seconds, condition)
    check(ok, message)
}

@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-inline-shell."))
    UserDefaults.standard.setVolatileDomain(["codexFolder": root.path, "dotCheckIns": false, "dotWatchWaiting": false, "dotSummarizeFinished": false, "dotEmailWatch": false, "companionEnabled": false, "keepMacAwake": false, "mobilePushConfigured": false], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let session = model.newChat(backend: .codex)

    func row(_ command: String) -> DisplayItem? { session.record.items.last { $0.kind == .shell && $0.text == command } }
    func finished(_ command: String) -> Bool { row(command)?.toolState != .running && row(command) != nil && !session.hasShellJobs }

    // Small commands keep their full output and exit codes.
    session.send("!echo hello; echo oops >&2")
    await expect(15, "small command finishes") { finished("echo hello; echo oops >&2") }
    var small = row("echo hello; echo oops >&2")!
    check(small.toolState == .done && small.detail == "hello\noops\n", "small output is complete and marked done")
    session.send("!echo bad; exit 3")
    await expect(15, "failing command finishes") { finished("echo bad; exit 3") }
    small = row("echo bad; exit 3")!
    check(small.toolState == .failed && small.detail == "bad\n", "non-zero exit marks the row failed")
    check(session.record.pendingShellContext?.contains("exit_code=\"3\"") == true, "the agent is told the exit code")
    check(session.record.pendingShellContext?.contains("stopped=") == false, "a normal exit is not marked stopped")
    _ = session.takeShellContext()

    // 200 MB of output stays bounded.
    let big = "yes | head -c 200000000"
    let before = footprint()
    var peak = before
    session.send("!" + big)
    let sampler = Task { @MainActor in while !Task.isCancelled { peak = max(peak, footprint()); try? await Task.sleep(for: .milliseconds(20)) } }
    await expect(120, "200 MB command finishes") { finished(big) }
    sampler.cancel()
    let bigRow = row(big)!
    let growthMB = (peak - before) / 1_000_000
    print("INFO footprint \(before / 1_000_000) MB -> peak \(peak / 1_000_000) MB (growth \(growthMB) MB)")
    check(growthMB < 40, "memory stays bounded while 200 MB is printed")
    check(bigRow.toolState == .done, "a large-output command still ends done")
    let shown = bigRow.detail ?? ""
    check(shown.utf8.count <= ChatSession.shellOutputLimit + ChatSession.shellCutOffNote.utf8.count && shown.hasSuffix(ChatSession.shellCutOffNote), "display is cut at the limit with the notice")
    let context = session.takeShellContext() ?? ""
    check(context.utf8.count < ChatSession.shellTailLimit + 1000 && context.contains("earlier output cut off"), "the agent gets only the bounded tail")

    // Stop ends an endless command and everything it started.
    let endless = "yes zzinline1"
    session.send("!" + endless)
    await expect(10, "endless command is running") { session.hasShellJobs && processCount("zzinline1") > 0 }
    check(session.canStop && session.hasBackgroundWork && session.backgroundTasks.contains { $0.kind == .shell && $0.title == endless }, "it counts as stoppable background work")
    check(!session.isRunning, "it does not pretend an agent reply is running")
    session.interrupt()
    await expect(10, "Stop settles the row") { finished(endless) }
    check(row(endless)?.toolState == .failed && row(endless)?.detail?.hasSuffix("(stopped)") == true, "the stopped row says so")
    await expect(5, "the process is gone") { processCount("zzinline1") == 0 }
    check(!session.canStop && !session.hasBackgroundWork, "status clears")
    _ = session.takeShellContext()

    // Descendants die with it, even ones that ignore SIGTERM (escalates to SIGKILL).
    let family = "trap '' TERM; sleep 1000.7771 & sleep 1000.7772"
    session.send("!" + family)
    await expect(10, "command with children is running") { processCount("sleep 1000.777") >= 2 }
    let stopped = Date()
    session.interrupt()
    await expect(10, "Stop settles a command that ignores SIGTERM") { finished(family) }
    await expect(6, "children are killed too (took \(Int(Date().timeIntervalSince(stopped) * 1000)) ms)") { processCount("sleep 1000.777") == 0 }
    _ = session.takeShellContext()

    // Deleting or archiving the chat (shutdown) stops them.
    let sleeper = "sleep 1000.4441"
    session.send("!" + sleeper)
    await expect(10, "sleep is running") { processCount("sleep 1000.4441") > 0 }
    session.shutdown()
    await expect(10, "shutdown stops it") { processCount("sleep 1000.4441") == 0 }
    await expect(5, "shutdown settles its row") { finished(sleeper) }

    // Quitting kills at once.
    let quitter = "sleep 1000.4442"
    session.send("!" + quitter)
    await expect(10, "second sleep is running") { processCount("sleep 1000.4442") > 0 }
    session.killShellJobs()
    await expect(5, "quitting kills it immediately") { processCount("sleep 1000.4442") == 0 }
    _ = await waitUntil(5) { finished(quitter) }

    // A row left running by a previous launch settles instead of spinning forever.
    var record = session.record
    record.items.append(DisplayItem(kind: .shell, text: "sleep 99", toolState: .running, detail: ""))
    let reopened = ChatSession(record: record)
    let orphan = reopened.record.items.last!
    check(orphan.toolState == .failed && orphan.detail?.contains("Chatterbox quit") == true && !reopened.hasShellJobs, "a stale running row settles on relaunch")

    print("ALL PASS")
}
Task { do { try await run(); exit(0) } catch { print(error); exit(1) } }
app.run()

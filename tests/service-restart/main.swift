import Foundation
import Darwin

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    print("PASS \(message)")
}

Task { @MainActor in
    do {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let script = root.appendingPathComponent("safe helper with spaces.sh")
        try "printf '%s\\n' \"$#\" > \"$(dirname \"$0\")/called\"\n".write(to: script, atomically: true, encoding: .utf8)
        let controller = BackgroundServiceRestart(scriptURL: script, diagnostics: root, isolated: false)
        controller.refresh()
        try check(controller.phase == .idle && !controller.pending, "no prior restart is idle")
        await controller.restart()
        let called = root.appendingPathComponent("called")
        let argumentCount = try String(contentsOf: called, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        try check(argumentCount == "0", "launcher executes the script without immediate or host flags")
        try check(controller.pending, "queue feedback stays visible before worker report arrives")
        try FileManager.default.removeItem(at: called)
        await controller.restart()
        try check(!FileManager.default.fileExists(atPath: called.path), "repeated clicks do not stack restart jobs")

        let report = controller.reportURL
        let lock = root.appendingPathComponent("service-restart.pid")
        try String(getpid()).write(to: lock, atomically: true, encoding: .utf8)
        try "2026-10-20 12:00:00 waiting for every chat to finish its reply\n".write(to: report, atomically: true, encoding: .utf8)
        controller.refresh()
        try check(controller.phase == .waiting && controller.pending, "live worker reports waiting for replies")
        let reopened = BackgroundServiceRestart(scriptURL: script, diagnostics: root, isolated: false)
        reopened.refresh()
        try check(reopened.phase == .waiting, "reopening Settings recovers the existing queued restart")
        try "2026-10-20 12:00:01 restarting chatterboxd (was pid 123)\n".write(to: report, atomically: true, encoding: .utf8)
        controller.refresh()
        try check(controller.phase == .restarting && controller.pending, "restart phase remains pending")
        try FileManager.default.removeItem(at: lock)
        try "2026-10-20 12:00:02 chatterboxd pid 456, health ok; app pid 789\n".write(to: report, atomically: true, encoding: .utf8)
        controller.refresh()
        try check(controller.phase == .completed && !controller.pending && controller.message.contains("successfully"), "successful health check enables the control again")
        try "2026-10-20 12:00:03 chatterboxd pid 456, health failed; app pid 789\n".write(to: report, atomically: true, encoding: .utf8)
        controller.refresh()
        try check(controller.phase == .failed && !controller.pending, "failed health check is shown as failure")
        try "2026-10-20 12:00:04 waiting for every chat to finish its reply\n".write(to: report, atomically: true, encoding: .utf8)
        try "2147483647".write(to: lock, atomically: true, encoding: .utf8)
        controller.refresh()
        try check(controller.phase == .failed && !controller.pending, "stale worker does not disable restarting forever")
        try "2026-10-20 12:00:05 gave up after 4 hours: replies still running; no restart\n".write(to: report, atomically: true, encoding: .utf8)
        controller.refresh()
        try check(controller.message.contains("timed out"), "idle-wait timeout explains recovery")

        let isolated = BackgroundServiceRestart(scriptURL: script, diagnostics: root, isolated: true)
        await isolated.restart()
        try check(isolated.phase == .failed && !FileManager.default.fileExists(atPath: called.path), "isolated app cannot restart installed services")
        let missing = BackgroundServiceRestart(scriptURL: nil, diagnostics: root, isolated: false)
        await missing.restart()
        try check(missing.phase == .failed && missing.message.contains("Reinstall"), "missing helper gives a recovery action")
        try "echo 'Fixture queue failure' >&2\nexit 23\n".write(to: script, atomically: true, encoding: .utf8)
        let failing = BackgroundServiceRestart(scriptURL: script, diagnostics: root, isolated: false)
        await failing.restart()
        try check(failing.phase == .failed && failing.message.contains("Fixture queue failure"), "launcher failure surfaces the helper output")
        print("All service restart checks passed; no installed service was touched.")
        exit(0)
    } catch { print("FAIL \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()

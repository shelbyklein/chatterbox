import Foundation

/// The always-on Desk (plans/always-on-desk.md), in the service: on while Settings says so
/// (`deskAlwaysOn`), it runs the ClickUp and Mail watchers, and gives each batch from the inbox
/// to a short Desk run (CompanionServer.runDeskEvents), waiting for that run to submit its
/// findings before the batch counts as done.
@MainActor
final class DeskAgent {
    static let shared = DeskAgent()
    static let key = "deskAlwaysOn"
    static var runTimeout: TimeInterval = 30 * 60
    private var on = false
    private var timer: Timer?

    var enabled: Bool { AppPreferences.defaults.object(forKey: Self.key) as? Bool ?? false }

    /// Follows the setting: checks it now and every minute.
    func start() {
        DeskInbox.shared.runner = { events in try await DeskAgent.run(events) }
        DeskOutbox.shared.post = { title, body in MobilePush.shared.post(title: title, body: body, chat: nil, kind: "desk") }
        sync()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in MainActor.assumeIsolated { DeskAgent.shared.tick() } }
    }

    /// Every minute: follow the setting; while on, fire due follow-ups and send what's due.
    func tick() {
        sync()
        guard on else { return }
        DeskTimers.shared.fireDue()
        DeskOutbox.shared.dispatch()
    }

    func sync() {
        guard enabled != on else { return }
        on = enabled
        if on {
            RuntimeHooks.note("Always-on Desk started: watching ClickUp and Apple Mail")
            ClickUpWatcher.shared.start()
            MailWatcher.shared.start()
            DeskInbox.shared.wake(now: true)
        } else {
            RuntimeHooks.note("Always-on Desk stopped")
            ClickUpWatcher.shared.stop()
            MailWatcher.shared.stop()
        }
    }

    /// One batch: a Desk run, waited on until it ends. Waits its turn if a check is already running.
    static func run(_ events: [DeskEvent]) async throws {
        let deadline = Date().addingTimeInterval(runTimeout)
        var session: ChatSession?
        while session == nil {
            do { session = try CompanionServer.shared.runDeskEvents(events) }
            catch let failure as CompanionServer.Failure where failure.message.contains("still going") {
                guard Date() < deadline else { throw RuntimeFailure("Another Desk check kept running.") }
                try await Task.sleep(for: .seconds(30))
            }
        }
        guard let session else { return }
        try await Task.sleep(for: .seconds(3))
        while session.isRunning || session.record.pressureHold != nil {
            guard Date() < deadline else { throw RuntimeFailure("The Desk run took longer than \(Int(runTimeout / 60)) minutes.") }
            try await Task.sleep(for: .seconds(5))
        }
        // A run that asked Shelby something has done its part; one that ended without its
        // findings hasn't.
        guard session.isWaitingOnYou || DeskStore.shared.sourceCheckResult(session.id) != nil else {
            throw RuntimeFailure("The Desk run ended without submitting its findings.")
        }
    }
}

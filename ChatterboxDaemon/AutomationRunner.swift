import Foundation

/// Runs projects' automations on schedule, each in its project's Automation thread.
@MainActor final class AutomationRunner {
    static var shared: AutomationRunner?
    private let model: DaemonContext
    private var timer: Timer?

    init(_ model: DaemonContext) { self.model = model }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func tick() {
        let state = ProjectAutomations.loadState()
        for automation in ProjectAutomations.load() where ProjectAutomations.isDue(automation, state: state[automation.id.uuidString]) {
            do { _ = try run(automation, manual: false) }
            catch { RuntimeHooks.note("Automation \u{201C}\(automation.title)\u{201D} didn't run: \(error.localizedDescription)") }
        }
    }

    /// Runs it now, as a sidequest of its project's main chat with the automation's own agent,
    /// model and effort: its report goes back to that chat and the run archives itself. The
    /// last run still working is left alone: a scheduled run waits for the next minute.
    func run(_ automation: ProjectAutomation, manual: Bool) throws -> UUID {
        var all = ProjectAutomations.loadState()
        var state = all[automation.id.uuidString] ?? AutomationRunState()
        if let last = state.threadID, let thread = model.sessions.first(where: { $0.id == last }),
           thread.record.archivedAt == nil, thread.isRunning || thread.isWaitingOnYou {
            throw RuntimeFailure("Its last run is still going.")
        }
        guard let project = model.sessions.first(where: {
            $0.record.projectFolder == automation.projectFolder && $0.record.worktreeOf == nil && $0.record.sidechatOf == nil
                && $0.record.archivedAt == nil && !$0.isDot
        }) else { throw RuntimeFailure("Its project isn't open in Chatterbox anymore.") }
        let quest = try model.newAutomationRun(automation, of: project, manual: manual)
        state.lastRun = Date()
        state.threadID = quest.id
        all[automation.id.uuidString] = state
        try ProjectAutomations.saveState(all)
        RuntimeHooks.note("Ran automation \u{201C}\(automation.title)\u{201D}")
        return quest.id
    }
}

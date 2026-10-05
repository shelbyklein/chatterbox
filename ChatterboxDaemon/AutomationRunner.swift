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

    /// Runs it now, in its thread (made the first time, or again if you ended it). A thread
    /// still busy with the last run is left alone: a scheduled run waits for the next minute.
    func run(_ automation: ProjectAutomation, manual: Bool) throws -> UUID {
        var all = ProjectAutomations.loadState()
        var state = all[automation.id.uuidString] ?? AutomationRunState()
        let thread = try self.thread(for: automation, existing: state.threadID)
        guard !thread.isRunning else { throw RuntimeFailure("Its thread is still working on the last run.") }
        if let id = automation.preset, let preset = ModelPresets.shared.presets.first(where: { $0.id == id }) {
            ModelPresets.shared.apply(preset, to: thread)
        }
        thread.send(ProjectAutomations.message(for: automation, manual: manual))
        if let index = thread.record.items.lastIndex(where: { $0.kind == .user }) {
            thread.record.items[index].automatic = true
            thread.record.items[index].detail = "Automation \u{00B7} \(automation.title)"
        }
        thread.onChange?(thread)
        state.lastRun = Date()
        state.threadID = thread.id
        all[automation.id.uuidString] = state
        try ProjectAutomations.saveState(all)
        RuntimeHooks.note("Ran automation \u{201C}\(automation.title)\u{201D}")
        return thread.id
    }

    private func thread(for automation: ProjectAutomation, existing: UUID?) throws -> ChatSession {
        if let existing, let thread = model.sessions.first(where: { $0.id == existing }), thread.record.archivedAt == nil {
            return thread
        }
        guard let project = model.sessions.first(where: {
            $0.record.projectFolder == automation.projectFolder && $0.record.worktreeOf == nil && $0.record.sidechatOf == nil
                && $0.record.archivedAt == nil && !$0.isDot
        }) else { throw RuntimeFailure("Its project isn't open in Chatterbox anymore.") }
        let thread = try model.newSidechat(of: project)
        thread.record.automationID = automation.id
        thread.setTitle("Automation \u{00B7} \(automation.title)")
        thread.onChange?(thread)
        return thread
    }
}

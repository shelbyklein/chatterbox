import Foundation

/// Runs projects' automations on schedule, each in its project's Automation thread.
@MainActor final class AutomationRunner {
    static var shared: AutomationRunner?
    private let model: DaemonContext
    private var timer: Timer?
    /// Starts a run's session and sends it its task. Tests replace it, so no agent starts.
    var startRun: (ProjectAutomation, ChatSession, Bool) throws -> ChatSession

    init(_ model: DaemonContext) {
        self.model = model
        startRun = { automation, project, manual in try model.newAutomationRun(automation, of: project, manual: manual) }
    }

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
        let routine = ProjectAutomations.routines(in: ProjectAutomations.load()).first { $0.contains { $0.id == automation.id } } ?? [automation]
        for day in routine {
            if let last = all[day.id.uuidString]?.threadID, let thread = model.sessions.first(where: { $0.id == last }),
               thread.record.archivedAt == nil, thread.isRunning || thread.isWaitingOnYou {
                throw RuntimeFailure("Its last run is still going.")
            }
        }
        let project = try reportSession(for: automation)
        let quest = try startRun(automation, project, manual)
        state.lastRun = Date()
        state.threadID = quest.id
        all[automation.id.uuidString] = state
        try ProjectAutomations.saveState(all)
        RuntimeHooks.note("Ran automation \u{201C}\(automation.title)\u{201D}")
        return quest.id
    }
    /// Preparing a reporting session never starts an agent or a source review.
    func reportSession(for automation: ProjectAutomation) throws -> ChatSession {
        try automation.validateTarget()
        if let folder = automation.projectFolder {
            guard let project = model.activeSessions.first(where: {
                $0.record.projectFolder == folder && $0.record.worktreeOf == nil && $0.record.sidechatOf == nil
            }) else { throw RuntimeFailure("Its project isn't open in Chatterbox anymore.") }
            return project
        }
        guard let id = automation.reportSessionID else { throw RuntimeFailure("The general automation needs a reporting session.") }
        if let session = model.sessions.first(where: { $0.id == id }) {
            let r = session.record
            guard r.projectFolder == nil, r.convertedProjectFolder == nil, r.worktreeOf == nil,
                  r.sidechatOf == nil, r.sidequestOf == nil, r.studioID == nil, r.studioFolder == nil,
                  r.sidechatProjectFolder == nil else {
                throw RuntimeFailure("Its reporting session now belongs to a project or Studio. Choose another general reporting session.")
            }
            if r.archivedAt != nil { session.setArchived(false) }
            return session
        }
        let defaults = AppPreferences.defaults
        var record = ConversationRecord(model: defaults.string(forKey: "defaultModel") ?? "default",
                                        effort: defaults.string(forKey: "defaultEffort") ?? "", personality: .friendly)
        record.id = id
        record.title = automation.reportingTitle
        record.activeBackend = automation.backend.flatMap(Backend.init(rawValue:))
            ?? (automation.model == nil ? automation.preset.flatMap { id in ModelPresets.shared.presets.first { $0.id == id }?.backend } : nil)
            ?? Backend(rawValue: defaults.string(forKey: "defaultBackend") ?? "") ?? .claude
        record.claudeMode = PermissionModes.defaultClaude
        if record.backend == .codex {
            record.codex = CodexSettings(folder: RuntimePaths.data.path, canEdit: false, mode: PermissionModes.defaultCodex)
            record.codex?.model = defaults.string(forKey: "codexDefaultModel").flatMap { $0.isEmpty ? nil : $0 }
            record.codex?.effort = defaults.string(forKey: "codexDefaultEffort").flatMap { $0.isEmpty ? nil : $0 }
        }
        return try model.runtime.insert(record)
    }

}

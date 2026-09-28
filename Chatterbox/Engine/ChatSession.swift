import Foundation
import Observation

/// Runs one conversation on Claude Code or Codex. Both agents run their own loop and keep
/// their own history; this maps what they do onto one transcript and adds the chat mechanics:
///
/// - Commentary vs. final: text written before a tool call is shown as a dim inline note;
///   only the text that ends a turn is shown as the reply.
/// - Steering: messages sent while a turn is running join that turn.
/// - Interrupt: stopping keeps what was said so far.
/// - Personality: sent as a tagged block only when it changes.
/// - Handoff: switching agents catches the new one up on what it missed.
@MainActor
@Observable
final class ChatSession: Identifiable {
    var record: ConversationRecord
    var isRunning = false

    @ObservationIgnored var onChange: ((ChatSession) -> Void)?
    @ObservationIgnored var pendingSteering: [UserMessage] = []

    // Claude Code state (see ChatSession+Claude.swift).
    @ObservationIgnored var claudeProcess: ClaudeCodeProcess?
    @ObservationIgnored var claudeRender = ResponseRender()
    @ObservationIgnored var claudeToolItems: [String: UUID] = [:]
    @ObservationIgnored var claudeApprovals: [String: (tool: String, input: JSON, suggestions: JSON?)] = [:]
    @ObservationIgnored var claudePlanItem: UUID?
    @ObservationIgnored var claudeStopRequested = false

    // Codex state (see ChatSession+Codex.swift).
    @ObservationIgnored var codexTurnID: String?
    @ObservationIgnored var codexItems: [String: UUID] = [:]
    @ObservationIgnored var codexPlanItems: [String: UUID] = [:]
    @ObservationIgnored var codexTurnMessageItems: [UUID] = []
    @ObservationIgnored var codexStopRequested = false

    nonisolated let id: UUID
    var items: [DisplayItem] { record.items }
    var title: String { record.title }
    var projectName: String { record.projectFolder.map { ($0 as NSString).lastPathComponent } ?? "" }

    init(record: ConversationRecord) {
        self.id = record.id
        self.record = record
    }

    // MARK: - Public API

    func send(_ raw: String, attachments: [Attachment] = []) {
        let message = UserMessage(text: raw.trimmingCharacters(in: .whitespacesAndNewlines), attachments: attachments)
        guard !message.text.isEmpty || !attachments.isEmpty else { return }
        switch record.backend {
        case .codex: codexSend(message)
        case .claude: claudeSend(message)
        }
    }

    func interrupt() {
        switch record.backend {
        case .codex: codexInterrupt()
        case .claude: claudeInterrupt()
        }
    }

    func resolveApproval(_ itemID: UUID, _ decision: DisplayItem.ApprovalState) {
        switch record.backend {
        case .codex: codexResolveApproval(itemID, decision)
        case .claude: claudeResolveApproval(itemID, decision)
        }
    }

    /// Stops any agent process this chat owns, e.g. when the chat is deleted.
    func shutdown() {
        interrupt()
        claudeProcess?.terminate()
        claudeProcess = nil
    }

    @discardableResult
    func appendUserItem(_ message: UserMessage, steered: Bool = false) -> UUID {
        appendItem(DisplayItem(kind: .user, text: message.text, steered: steered,
                               attachments: message.attachments.isEmpty ? nil : message.attachments))
    }

    /// Every attachment in this chat, for cleanup when the chat is deleted.
    var allAttachments: [Attachment] { record.items.flatMap { $0.attachments ?? [] } }

    func setTitleIfNeeded(_ message: UserMessage) {
        guard record.title == "New chat" else { return }
        let text = message.text.isEmpty ? message.attachments.map(\.name).joined(separator: ", ") : message.text
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        record.title = firstLine.count > 48 ? String(firstLine.prefix(47)) + "\u{2026}" : firstLine
    }

    // MARK: - Agent switching

    /// Switches which agent answers. Mid-chat, the incoming agent is handed a transcript of
    /// whatever it missed, since Claude and Codex keep separate histories.
    func setBackend(_ backend: Backend) {
        guard !isRunning, backend != record.backend else { return }
        let leaving = record.backend
        if !record.items.isEmpty {
            let last = record.items.last?.id
            if leaving == .claude { record.claudeSeenThrough = last } else { record.codexSeenThrough = last }
            let seen = backend == .claude ? record.claudeSeenThrough : record.codexSeenThrough
            let start = seen.flatMap { id in record.items.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
            let transcript = Self.transcript(record.items[start...])
            record.pendingHandoff = transcript.isEmpty ? nil
                : Prompts.handoff(from: leaving.label, transcript: transcript, isWholeConversation: seen == nil)
        }
        if backend == .codex, record.codex == nil {
            let defaults = UserDefaults.standard
            record.codex = CodexSettings(
                folder: record.projectFolder ?? defaults.string(forKey: "codexFolder") ?? NSHomeDirectory(),
                canEdit: record.claudeCanEdit ?? defaults.object(forKey: "codexCanEdit") as? Bool ?? false
            )
            record.codex?.model = defaults.string(forKey: "codexDefaultModel").flatMap { $0.isEmpty ? nil : $0 }
            record.codex?.effort = defaults.string(forKey: "codexDefaultEffort").flatMap { $0.isEmpty ? nil : $0 }
        }
        record.activeBackend = backend
        // The incoming agent may not have seen the current tone.
        record.sentPersonality = nil
        if !record.items.isEmpty { notice("Switched to \(backend.label). It has been caught up on this chat.") }
        onChange?(self)
    }

    /// A plain-text record of the conversation for handing it to another agent.
    static func transcript(_ items: ArraySlice<DisplayItem>, limit: Int = 150_000) -> String {
        var parts: [String] = []
        for item in items {
            switch item.kind {
            case .user:
                var text = "User: " + item.text
                if let files = item.attachments, !files.isEmpty {
                    text += (item.text.isEmpty ? "" : "\n") + "[Attached: " + files.map { "\($0.name) (\($0.path))" }.joined(separator: ", ") + "]"
                }
                parts.append(text)
            case .assistant where item.phase == .final:
                parts.append("Assistant: " + item.text)
            case .plan:
                parts.append("Plan: " + item.planSteps.map { "[\($0.status)] \($0.step)" }.joined(separator: "; "))
            default:
                break
            }
        }
        let joined = parts.joined(separator: "\n\n")
        return joined.count > limit ? "(earlier messages omitted)\n\n" + String(joined.suffix(limit)) : joined
    }

    // MARK: - Settings

    /// Binds this chat to a folder. AppModel checks that no other chat owns it.
    func bindProject(_ folder: String) {
        guard folder != record.projectFolder else { return }
        record.projectFolder = folder
        record.codex?.folder = folder
        claudeWorkingFolderChanged()
        onChange?(self)
    }

    func unbindProject() {
        guard record.projectFolder != nil else { return }
        record.projectFolder = nil
        claudeWorkingFolderChanged()
        onChange?(self)
    }

    var canEdit: Bool {
        record.backend == .codex ? record.codex?.canEdit ?? false : record.claudeCanEdit ?? false
    }

    /// One "Can edit" switch per chat, shared by both agents.
    func setCanEdit(_ on: Bool) {
        record.claudeCanEdit = on
        record.codex?.canEdit = on
        claudeApplyPermissionMode()
        onChange?(self)
    }

    func setPersonality(_ personality: Personality) {
        record.personality = personality
        onChange?(self)
    }

    func setModel(_ model: String) {
        record.model = model
        let efforts = ClaudeModels.shared.info(model).efforts
        if !record.effort.isEmpty, !efforts.contains(record.effort) { record.effort = "" }
        claudeApplyModel()
        onChange?(self)
    }

    func setEffort(_ effort: String) {
        record.effort = effort
        claudeApplyEffort()
        onChange?(self)
    }

    // MARK: - Display items

    @discardableResult
    func appendItem(_ item: DisplayItem) -> UUID {
        record.items.append(item)
        return item.id
    }

    func updateItem(_ id: UUID, _ change: (inout DisplayItem) -> Void) {
        guard let index = record.items.lastIndex(where: { $0.id == id }) else { return }
        change(&record.items[index])
    }

    func notice(_ text: String) {
        record.items.append(DisplayItem(kind: .notice, text: text))
    }

    func markRunningToolsFailed() {
        for index in record.items.indices where record.items[index].kind == .tool && record.items[index].toolState == .running {
            record.items[index].toolState = .failed
        }
    }

    func expirePendingApprovals() {
        for index in record.items.indices where record.items[index].approvalState == .pending {
            record.items[index].approvalState = .expired
        }
    }
}

/// Per-response bookkeeping that maps streamed block indexes to transcript rows.
struct ResponseRender {
    var itemForIndex: [Int: UUID] = [:]
    var textItems: [UUID] = []
}

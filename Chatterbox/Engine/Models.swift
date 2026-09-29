import Foundation

enum Personality: String, Codable, CaseIterable, Identifiable {
    case friendly, pragmatic, neutral
    var id: String { rawValue }
    var label: String {
        switch self {
        case .friendly: "Friendly"
        case .pragmatic: "Pragmatic"
        case .neutral: "Neutral"
        }
    }
}

enum Backend: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var label: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

/// Per-chat settings for the Codex backend. Codex keeps the conversation history itself.
struct CodexSettings: Codable, Equatable {
    var threadId: String?
    /// nil means Codex's own default model.
    var model: String?
    var effort: String?
    var folder: String
    /// Older setting, used when `mode` is unset: true meant workspace-write.
    var canEdit: Bool
    /// One of `PermissionModes.codex`.
    var mode: String?

    var modeID: String { mode ?? (canEdit ? "ask" : "readOnly") }
}

struct PlanStep: Codable, Equatable, Hashable {
    var step: String
    var status: String // pending | in_progress | completed
}

/// One row in the transcript. The API history is stored separately; this is only what the user sees.
struct DisplayItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case user, assistant, thought, tool, plan, notice, approval, image }
    /// Assistant text is either narration mid-task (commentary) or the reply that ends a turn (final).
    enum Phase: String, Codable { case streaming, commentary, final }
    enum ToolState: String, Codable { case running, done, failed }
    enum ApprovalState: String, Codable { case pending, approved, approvedForSession, denied, expired }

    var id = UUID()
    var kind: Kind
    var text: String = ""
    var phase: Phase = .final
    var steered = false
    var toolState: ToolState = .running
    var planSteps: [PlanStep] = []
    /// Approval rows: extra detail (command, files), the pending server request, and its outcome.
    var detail: String?
    var requestID: JSON?
    var approvalState: ApprovalState?
    /// Files attached to a user message.
    var attachments: [Attachment]?
    /// The agent a user message was sent to. Older rows leave it unset.
    var agent: Backend?
    /// Approval rows: which buttons to show. nil is the usual Allow / Allow for This Chat / Deny.
    var approvalStyle: ApprovalStyle?

    enum ApprovalStyle: String, Codable { case plan }
}

/// Everything persisted for a conversation.
struct ConversationRecord: Codable {
    var id = UUID()
    var title = "New chat"
    var createdAt = Date()
    /// Set when the chat is archived: hidden from the main lists, but kept intact.
    var archivedAt: Date?
    var updatedAt = Date()
    /// Claude Code `--model` value: an alias ("opus", "default") or a full model id.
    var model: String
    /// Claude Code effort level; empty means the model's default.
    var effort: String
    var personality: Personality
    /// The personality most recently sent to the agent, so it's re-sent only when it changes.
    var sentPersonality: Personality?
    var items: [DisplayItem] = []
    /// The Claude Code session this chat continues, so it survives app restarts.
    var claudeSessionID: String?
    /// Codex settings, present once this chat has used Codex. Kept when switching back to
    /// Claude so the Codex thread can resume.
    var codex: CodexSettings?
    /// Which agent answers next. Older records leave this unset: Codex if `codex` exists.
    var activeBackend: Backend?

    /// The project folder this chat is bound to. At most one chat per folder.
    var projectFolder: String?
    /// "owner/name" of the GitHub repo the project folder's remote points to. Read from
    /// git, not set by hand; kept here so the sidebar and "From GitHub" can find it.
    var githubRepo: String?
    /// Which remote to use when the folder has more than one on GitHub.
    var gitRemote: String?
    /// Labels for sorting projects, shown as pills in the sidebar.
    var tags: [String]?
    /// Older setting, used when `claudeMode` is unset: true meant accept edits.
    var claudeCanEdit: Bool?
    /// Claude Code permission mode, one of `PermissionModes.claude`.
    var claudeMode: String?

    var claudeModeID: String { claudeMode ?? (claudeCanEdit == true ? "acceptEdits" : "default") }

    /// The last transcript row each agent has seen, so switching agents can hand over
    /// just the part of the conversation the new one missed.
    var claudeSeenThrough: UUID?
    var codexSeenThrough: UUID?
    /// Transcript of what the incoming agent missed, delivered with its next message.
    var pendingHandoff: String?

    var backend: Backend { activeBackend ?? (codex == nil ? .claude : .codex) }
}

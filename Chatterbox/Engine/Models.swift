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
    /// A forked chat's source thread: Codex branches it on the next message.
    var forkFrom: String?

    var modeID: String { mode ?? (canEdit ? "ask" : "readOnly") }
}

/// One question an agent asks you: from Claude Code's AskUserQuestion tool or Codex's
/// request_user_input. Answered in a card, one question at a time.
struct AgentQuestion: Codable, Equatable, Hashable, Identifiable {
    struct Option: Codable, Equatable, Hashable {
        var label: String
        var detail: String
    }
    var id: String
    var header: String
    var question: String
    var options: [Option]
    var multiSelect: Bool
    var isSecret: Bool
}

struct PlanStep: Codable, Equatable, Hashable {
    var step: String
    var status: String // pending | in_progress | completed
}

/// One row in the transcript. The API history is stored separately; this is only what the user sees.
struct DisplayItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case user, assistant, thought, tool, plan, notice, approval, image, questions, shell }
    /// Assistant text is either narration mid-task (commentary) or the reply that ends a turn (final).
    enum Phase: String, Codable { case streaming, commentary, final }
    enum ToolState: String, Codable { case running, done, failed }
    enum ApprovalState: String, Codable { case pending, approved, approvedForSession, denied, expired }

    var id = UUID()
    var kind: Kind
    var text: String = ""
    var phase: Phase = .final
    var steered = false
    /// A steered message the agent hasn't picked up yet. Optional so older chats still load.
    var queued: Bool?
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
    /// On a turn's final reply: how long the turn took, shown as "Worked for 4m 12s".
    var workedSeconds: Int?
    /// Notices marking a change of agent, model, or effort. Back-to-back changes share one.
    var isSettingsChange: Bool?
    /// Question rows: what the agent asked, and your answers by question id once sent.
    var questions: [AgentQuestion]?
    var answers: [String: [String]]?
    /// Approval rows: which buttons to show. nil is the usual Allow / Allow for This Chat / Deny.
    var approvalStyle: ApprovalStyle?
    /// A user row Chatterbox sent for Dot (a check-in), shown by its label in `detail`.
    var automatic: Bool?

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
    /// Which version of the app's agent instructions this chat has seen (see Prompts).
    var instructionsVersion: Int?
    /// Your every-chat instructions as last given to this chat's agent.
    var sentUserInstructions: String?
    /// The Studio's instructions as last given to this chat's agent.
    var sentStudioInstructions: String?
    /// Set on a forked chat: the next Claude Code session branches off `claudeSessionID`
    /// instead of continuing it, so the original chat is left as it was.
    var claudeForkPending: Bool?
    /// The chat this one was forked from.
    var forkedFrom: UUID?
    /// Remote Control for this chat, overriding the setting; nil follows the setting.
    var remoteControl: Bool?
    /// Claude Code's tasks for this session, shown as the plan (see ChatSession+Tasks).
    var claudeTasks: [ClaudeTask]?
    /// This is Dot's chat (see Dot.swift).
    var isDot: Bool?
    /// The name Dot was last told it has, so a rename reaches it with the next message.
    var sentDotName: String?
    /// Dot handed this chat work, and tells you when it's done (see DotActivity).
    var dotFollowing: Bool?
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
    /// The Studio this chat belongs to, and that Studio's folder, which the chat works in.
    /// The folder is kept here too so the chat can start its agent without looking it up.
    var studioID: UUID?
    var studioFolder: String?
    /// "owner/name" of the GitHub repo the project folder's remote points to. Read from
    /// git, not set by hand; kept here so the sidebar and "From GitHub" can find it.
    var githubRepo: String?
    /// Which remote to use when the folder has more than one on GitHub.
    var gitRemote: String?
    /// The GitHub issue this chat is working on, shown in the toolbar. Set by "Work on This".
    var currentIssue: CurrentIssue?
    /// A friendlier name for the project ("Tracker Trapper" for tracker-trapper). The folder isn't renamed.
    var projectNickname: String?
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
    /// When the reply in progress started, so its running time survives a restart.
    var turnStartedAt: Date?
    /// Context usage per agent ("claude"/"codex") as last reported, so the meter shows at once.
    var savedContext: [String: ContextUsage]?
    /// "!" commands you ran and their output, delivered with your next message to the agent.
    var pendingShellContext: String?

    var backend: Backend { activeBackend ?? (codex == nil ? .claude : .codex) }

    /// The folder this chat is tied to: its project's, or its Studio's.
    var boundFolder: String? { projectFolder ?? studioFolder }

    /// The agent processes this chat has in the background host, so a relaunch can pick up
    /// a reply that kept going while the app was closed. Older records leave these unset.
    var claudeHost: HostLink?
    var codexHost: HostLink?
    /// Subagents and background commands still running (see BackgroundTasks.swift).
    var backgroundTasks: [BackgroundTask]?
}

/// Where a chat's agent runs in ChatterboxHost and how far its output had been handled when
/// the chat was last saved. The turn bookkeeping is saved with it, so replaying from `offset`
/// continues exactly where the saved transcript stops: no repeated or half-built rows.
struct HostLink: Codable, Equatable {
    var processID: String
    var offset: Int
    /// A turn was in progress.
    var running: Bool
    var claude: ClaudeTurnState?
    var codex: CodexTurnState?
}

/// The Claude side's per-turn bookkeeping (see ChatSession+Claude).
struct ClaudeTurnState: Codable, Equatable {
    struct ToolCall: Codable, Equatable {
        var name: String
        var input: JSON
    }
    var render: ResponseRender
    var toolItems: [String: UUID]
    var toolCalls: [String: ToolCall]
    var planItem: UUID?
    var streamedMessages: [String]
    var stopRequested: Bool
}

/// The Codex side's per-turn bookkeeping (see ChatSession+Codex).
struct CodexTurnState: Codable, Equatable {
    var turnID: String?
    var items: [String: UUID]
    var planItems: [String: UUID]
    var turnMessageItems: [UUID]
    var stopRequested: Bool
}

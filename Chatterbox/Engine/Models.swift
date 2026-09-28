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
    var canEdit: Bool
}

/// One Claude model as reported by GET /v1/models.
struct ClaudeModelInfo: Identifiable, Hashable {
    var id: String
    var displayName: String
    /// Effort levels the model accepts, weakest first. Empty means no effort control.
    var efforts: [String]
    var adaptiveThinking: Bool
    var manualThinking: Bool
    var maxInputTokens: Int
    var maxOutputTokens: Int

    static let effortOrder = ["low", "medium", "high", "xhigh", "max"]

    /// Used until the Models API answers, and for a chat whose model is no longer listed.
    static func fallback(_ id: String) -> ClaudeModelInfo {
        let old = id.contains("haiku") || id.contains("claude-3")
        return ClaudeModelInfo(
            id: id, displayName: id, efforts: old ? [] : effortOrder,
            adaptiveThinking: !old, manualThinking: old,
            maxInputTokens: old ? 200_000 : 1_000_000, maxOutputTokens: 64_000
        )
    }

    /// Server-side refusal fallbacks are offered for these models.
    var supportsDefaultFallbacks: Bool { ["claude-opus-5", "claude-fable-5-1"].contains(id) }

    /// The dynamic-filtering web tools need Opus/Sonnet 4.6 or later.
    var usesBasicWebTools: Bool {
        id.contains("haiku") || id.contains("claude-3")
            || ["claude-opus-4-", "claude-sonnet-4-"].contains { prefix in
                id.hasPrefix(prefix) && ["0", "1", "5", "2"].contains(String(id.dropFirst(prefix.count).prefix(1)))
            }
    }

    /// Keeps `effort` if this model accepts it, otherwise picks the nearest sensible level.
    func coerce(effort: String) -> String {
        if efforts.isEmpty || efforts.contains(effort) { return efforts.isEmpty ? "" : effort }
        return efforts.contains("high") ? "high" : efforts.last ?? ""
    }
}

struct PlanStep: Codable, Equatable, Hashable {
    var step: String
    var status: String // pending | in_progress | completed
}

/// One row in the transcript. The API history is stored separately; this is only what the user sees.
struct DisplayItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case user, assistant, thought, tool, plan, notice, approval }
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
}

/// Everything persisted for a conversation.
struct ConversationRecord: Codable {
    var id = UUID()
    var title = "New chat"
    var createdAt = Date()
    var updatedAt = Date()
    /// Claude model id, e.g. "claude-opus-5".
    var model: String
    /// Claude effort level; empty when the model has no effort control.
    var effort: String
    var webAccess: Bool
    var personality: Personality
    /// The personality most recently sent to the model, so it's re-sent only when it changes.
    var sentPersonality: Personality?
    /// Raw Messages API history, append-only except for compaction.
    var apiMessages: [JSON] = []
    var items: [DisplayItem] = []
    /// Blocks to prepend to the next user message (interrupt notes, orphaned tool results).
    var carryover: [JSON] = []
    /// Summary produced by compaction, delivered with the next user message.
    var pendingSummary: String?
    var lastInputTokens = 0
    /// Present when this chat runs on Codex instead of Claude.
    var codex: CodexSettings?

    var backend: Backend { codex == nil ? .claude : .codex }
}

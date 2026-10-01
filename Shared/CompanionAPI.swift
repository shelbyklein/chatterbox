import Foundation

/// What Chatterbox on the Mac and the Chatterbox iPhone app say to each other. The Mac
/// serves this over HTTP on the home network and Tailscale; every call but pairing carries
/// the token the phone got when it paired.
enum Companion {
    static let port: UInt16 = 47_321
    /// Bonjour service type, for finding the Mac on the same Wi-Fi.
    static let serviceType = "_chatterbox._tcp"
    static let tokenHeader = "X-Chatterbox-Token"
    /// The newest items a chat sends at once; older ones are left out.
    static let itemLimit = 300

    struct PairRequest: Codable {
        var code: String
        var deviceName: String
    }

    struct PairResponse: Codable {
        var token: String
        var macName: String
        /// Where else the Mac can be reached, such as its Tailscale address.
        var addresses: [String]
    }

    /// The chat list, grouped the way the Mac's sidebar is.
    struct ChatList: Codable {
        var revision: Int
        var groups: [ChatGroup]
    }

    struct ChatGroup: Codable, Identifiable {
        enum Kind: String, Codable { case projects, studio, chats }
        var id: String
        var kind: Kind
        var title: String
        var chats: [ChatSummary]
    }

    struct ChatSummary: Codable, Identifiable, Hashable {
        var id: UUID
        var title: String
        /// A project's name, shown above the chat's title.
        var project: String?
        /// What happened last, or the chat's title.
        var subtitle: String?
        var backend: String
        var isRunning: Bool
        var isWaitingOnYou: Bool
        var updatedAt: Date
    }

    /// One chat, with its recent transcript.
    struct ChatDetail: Codable {
        var revision: Int
        var summary: ChatSummary
        /// e.g. "Claude · Opus 5.5 · Medium effort"
        var settings: String
        var items: [Item]
        /// Items before these that were left out.
        var earlierCount: Int
        /// What can be changed: agent, model, effort, mode, presets.
        var options: ChatOptions? = nil
        var isArchived: Bool? = nil
        /// A project's chat: there's one per folder, so it isn't forked.
        var canFork: Bool? = nil
        /// When the reply in progress started, for its running time.
        var turnStartedAt: Date? = nil
        var backgroundTasks: [BackgroundTask]? = nil
        /// How full the agent's context is, 0–1, once known.
        var contextFraction: Double? = nil
        var contextTokens: Int? = nil
    }

    /// A chat's settings and the choices for each, as on the Mac.
    struct ChatOptions: Codable, Hashable {
        /// "claude" or "codex": who answers next.
        var backend: String
        /// The current model's id; for Codex, empty means Codex's default.
        var model: String
        /// Empty means the model's default.
        var effort: String
        var claudeModels: [ModelOption]
        var codexModels: [ModelOption]
        /// Modes for the current agent.
        var modes: [ModeOption]
        var mode: String
        var presets: [PresetOption]
    }

    struct ModelOption: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var detail: String
        /// Effort levels, weakest first; empty when the model has none.
        var efforts: [String]
        var defaultEffort: String?
    }

    struct ModeOption: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var systemImage: String
        /// Can do anything without asking: shown in orange.
        var isUnrestricted: Bool
    }

    struct PresetOption: Codable, Hashable, Identifiable {
        var id: UUID
        var title: String
        var backend: String
        var isActive: Bool
    }

    /// Change any of a chat's settings; leave the rest nil.
    struct SettingsRequest: Codable {
        var backend: String? = nil
        var model: String? = nil
        var effort: String? = nil
        var mode: String? = nil
        var preset: UUID? = nil
    }

    /// A new chat, in a Studio or on its own.
    struct NewChatRequest: Codable {
        var studio: UUID? = nil
        var backend: String? = nil
    }

    struct RenameRequest: Codable {
        var title: String
    }

    struct Item: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case user, assistant, thought, tool, plan, notice, approval, image, questions, shell }
        var id: UUID
        var kind: Kind
        var text: String
        /// An agent's reply still being written.
        var isStreaming: Bool
        /// Narration mid-task rather than the reply.
        var isCommentary: Bool
        /// For tool rows: running, done, or failed.
        var toolState: String?
        /// Waiting for an answer on the Mac (approvals and question cards).
        var isPending: Bool
        var attachments: [File]
        /// Queued while the agent works, not yet picked up.
        var isQueued: Bool
        /// Approval rows: the decision asked for, and what was decided.
        var approval: Approval? = nil
        /// Question rows: what the agent asked, and the answers once sent.
        var questions: [Question]? = nil
        var answers: [String: [String]]? = nil
        /// Approval detail (the command, or the plan) and `!` command output.
        var detail: String? = nil
        /// A plan's steps.
        var planSteps: [PlanStep]? = nil
        /// On a reply that ended a turn: how long the turn took.
        var workedSeconds: Int? = nil
    }

    struct PlanStep: Codable, Hashable {
        var step: String
        /// "pending", "in_progress", or "completed".
        var status: String
    }

    /// A subagent or background command still running apart from the reply.
    struct BackgroundTask: Codable, Hashable, Identifiable {
        var id: String
        /// "agent" or "shell".
        var kind: String
        var title: String
        var detail: String?
        var startedAt: Date
    }

    struct Approval: Codable, Hashable {
        /// A plan to start building, rather than a single action to allow.
        var isPlan: Bool
        /// "pending", "approved", "approvedForSession", "denied", or "expired".
        var state: String
    }

    struct Question: Codable, Hashable, Identifiable {
        struct Option: Codable, Hashable {
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

    /// Allow or deny an action, or start building a plan.
    struct DecisionRequest: Codable {
        /// "approved", "approvedForSession", or "denied".
        var decision: String
    }

    /// Answers by question id; nil skips the questions.
    struct AnswersRequest: Codable {
        var answers: [String: [String]]?
    }

    struct File: Codable, Identifiable, Hashable {
        var id: UUID
        var name: String
        var mediaType: String
        var isImage: Bool
    }

    struct SendRequest: Codable {
        var text: String
        /// Images sent with the message, such as a sketch (PNG or JPEG).
        var images: [Upload]? = nil
        /// Stop the agent and send this right away ("Send Now"), rather than adding it to
        /// the reply in progress.
        var now: Bool? = nil
    }

    struct Upload: Codable {
        var name: String
        var data: Data
    }

    /// Requests can carry images, so allow this much.
    static let maxRequestBytes = 40_000_000

    struct Unchanged: Codable {
        var unchanged = true
        var revision: Int
    }

    struct ErrorResponse: Codable {
        var error: String
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

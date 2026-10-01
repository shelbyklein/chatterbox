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
    }

    struct File: Codable, Identifiable, Hashable {
        var id: UUID
        var name: String
        var mediaType: String
        var isImage: Bool
    }

    struct SendRequest: Codable {
        var text: String
    }

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

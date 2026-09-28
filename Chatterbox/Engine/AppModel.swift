import Foundation
import Observation

/// Owns the list of conversations and saves each one as JSON in Application Support.
@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [ChatSession] = []
    var selectedID: UUID?
    var hasAPIKey = Keychain.readAPIKey() != nil

    @ObservationIgnored private let directory: URL

    var selected: ChatSession? { sessions.first { $0.id == selectedID } }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Chatterbox/Conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        if sessions.isEmpty { newChat() } else { selectedID = sessions.first?.id }
    }

    @discardableResult
    func newChat(backend: Backend? = nil) -> ChatSession {
        let defaults = UserDefaults.standard
        let backend = backend ?? Backend(rawValue: defaults.string(forKey: "defaultBackend") ?? "") ?? .claude
        if let empty = sessions.first(where: { $0.items.isEmpty && !$0.isRunning }) {
            empty.setBackend(backend)
            selectedID = empty.id
            return empty
        }
        var record = ConversationRecord(
            model: defaults.string(forKey: "defaultModel") ?? "claude-opus-5",
            effort: defaults.string(forKey: "defaultEffort") ?? "high",
            webAccess: defaults.object(forKey: "webAccess") as? Bool ?? true,
            personality: Personality(rawValue: defaults.string(forKey: "defaultPersonality") ?? "") ?? .friendly
        )
        if backend == .codex {
            record.codex = CodexSettings(
                folder: defaults.string(forKey: "codexFolder") ?? NSHomeDirectory(),
                canEdit: defaults.object(forKey: "codexCanEdit") as? Bool ?? false
            )
            record.codex?.model = defaults.string(forKey: "codexDefaultModel").flatMap { $0.isEmpty ? nil : $0 }
            record.codex?.effort = defaults.string(forKey: "codexDefaultEffort").flatMap { $0.isEmpty ? nil : $0 }
        }
        let session = makeSession(record)
        sessions.insert(session, at: 0)
        selectedID = session.id
        return session
    }

    func delete(_ session: ChatSession) {
        session.interrupt()
        sessions.removeAll { $0.id == session.id }
        try? FileManager.default.removeItem(at: fileURL(session.id))
        if selectedID == session.id { selectedID = sessions.first?.id }
        if sessions.isEmpty { newChat() }
    }

    func refreshAPIKeyState() {
        hasAPIKey = Keychain.readAPIKey() != nil
    }

    // MARK: - Persistence

    private func makeSession(_ record: ConversationRecord) -> ChatSession {
        let session = ChatSession(record: record)
        session.onChange = { [weak self] session in self?.save(session) }
        return session
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ session: ChatSession) {
        guard !session.items.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(session.record).write(to: fileURL(session.id), options: .atomic)
        } catch {
            NSLog("Chatterbox: failed to save conversation: \(error)")
        }
        // Keep the most recently active conversation at the top.
        if let index = sessions.firstIndex(where: { $0.id == session.id }), index != 0, !sessions[0].items.isEmpty {
            sessions.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        sessions = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ConversationRecord.self, from: Data(contentsOf: $0)) }
            .map { record in
                // Requests from a previous run can't be answered anymore.
                var record = record
                for index in record.items.indices where record.items[index].approvalState == .pending {
                    record.items[index].approvalState = .expired
                }
                return record
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(makeSession)
    }
}

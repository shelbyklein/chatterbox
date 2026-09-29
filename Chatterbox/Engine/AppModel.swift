import Foundation
import Observation

/// Owns the list of conversations and saves each one as JSON in Application Support.
@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [ChatSession] = []
    var selectedID: UUID?
    var showingCloneFromGitHub = false

    var activeSessions: [ChatSession] { sessions.filter { $0.record.archivedAt == nil } }

    /// Projects by name, then other chats by most recent: the sidebar's order, which the
    /// ⌘1–⌘9 shortcuts follow.
    var sidebarProjects: [ChatSession] {
        activeSessions.filter { $0.record.projectFolder != nil }
            .sorted { $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending }
    }
    var sidebarChats: [ChatSession] { activeSessions.filter { $0.record.projectFolder == nil } }
    var sidebarOrder: [ChatSession] { sidebarProjects + sidebarChats }

    /// Every tag in use, for the Tags menu.
    var allTags: [String] {
        var seen: [String: String] = [:]
        for tag in sessions.flatMap(\.tags) where seen[tag.lowercased()] == nil { seen[tag.lowercased()] = tag }
        return seen.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Selects the chat at a 1-based position in the sidebar.
    func selectChat(number: Int) {
        let order = sidebarOrder
        guard order.indices.contains(number - 1) else { return }
        selectedID = order[number - 1].id
    }

    /// Moves the selection up or down the sidebar, wrapping around.
    func selectAdjacentChat(_ offset: Int) {
        let order = sidebarOrder
        guard !order.isEmpty else { return }
        let current = order.firstIndex { $0.id == selectedID } ?? 0
        selectedID = order[(current + offset + order.count) % order.count].id
    }
    var archivedSessions: [ChatSession] {
        sessions.filter { $0.record.archivedAt != nil }
            .sorted { ($0.record.archivedAt ?? .distantPast) > ($1.record.archivedAt ?? .distantPast) }
    }

    @ObservationIgnored private let directory: URL

    var selected: ChatSession? { sessions.first { $0.id == selectedID } }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Chatterbox/Conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        if activeSessions.isEmpty { newChat() } else { selectedID = activeSessions.first?.id }
    }

    @discardableResult
    func newChat(backend: Backend? = nil) -> ChatSession {
        let defaults = UserDefaults.standard
        let backend = backend ?? Backend(rawValue: defaults.string(forKey: "defaultBackend") ?? "") ?? .claude
        if let empty = sessions.first(where: { $0.items.isEmpty && !$0.isRunning && $0.record.projectFolder == nil && $0.record.archivedAt == nil }) {
            empty.setBackend(backend)
            selectedID = empty.id
            return empty
        }
        var record = ConversationRecord(
            model: defaults.string(forKey: "defaultModel") ?? "default",
            effort: defaults.string(forKey: "defaultEffort") ?? "",
            personality: Personality(rawValue: defaults.string(forKey: "defaultPersonality") ?? "") ?? .friendly
        )
        record.claudeMode = PermissionModes.defaultClaude
        if backend == .codex {
            record.codex = CodexSettings(
                folder: defaults.string(forKey: "codexFolder") ?? NSHomeDirectory(),
                canEdit: false,
                mode: PermissionModes.defaultCodex
            )
            record.codex?.model = defaults.string(forKey: "codexDefaultModel").flatMap { $0.isEmpty ? nil : $0 }
            record.codex?.effort = defaults.string(forKey: "codexDefaultEffort").flatMap { $0.isEmpty ? nil : $0 }
        }
        let session = makeSession(record)
        sessions.insert(session, at: 0)
        selectedID = session.id
        return session
    }

    /// Hides a chat from the main lists and stops its agent. Nothing is removed; a project
    /// chat keeps its folder, and opening that folder again brings the chat back.
    func archive(_ session: ChatSession) {
        guard !session.items.isEmpty || session.record.projectFolder != nil else { return delete(session) }
        session.shutdown()
        session.setArchived(true)
        if selectedID == session.id { selectedID = activeSessions.first?.id }
        if activeSessions.isEmpty { newChat() }
    }

    func unarchive(_ session: ChatSession) {
        session.setArchived(false)
        selectedID = session.id
    }

    func delete(_ session: ChatSession) {
        session.shutdown()
        Attachments.remove(session.allAttachments)
        sessions.removeAll { $0.id == session.id }
        try? FileManager.default.removeItem(at: fileURL(session.id))
        if selectedID == session.id { selectedID = activeSessions.first?.id }
        if activeSessions.isEmpty { newChat() }
    }

    // MARK: - Projects

    static func normalize(_ folder: String) -> String {
        URL(fileURLWithPath: folder).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The chat bound to `folder`, if any. Each folder has at most one.
    func session(boundTo folder: String) -> ChatSession? {
        let target = Self.normalize(folder)
        return sessions.first { $0.record.projectFolder.map(Self.normalize) == target }
    }

    /// Binds `session` to `folder`, unless another chat already owns it; that chat is returned instead.
    @discardableResult
    func bind(_ session: ChatSession, to folder: String) -> ChatSession? {
        if let owner = self.session(boundTo: folder), owner.id != session.id { return owner }
        session.bindProject(Self.normalize(folder))
        return nil
    }

    /// Opens the folder's chat, creating one if the folder doesn't have one yet.
    func openProject(_ folder: String, backend: Backend? = nil) {
        if let existing = session(boundTo: folder) {
            if existing.record.archivedAt != nil { existing.setArchived(false) }
            selectedID = existing.id
            return
        }
        let session = newChat(backend: backend)
        session.bindProject(Self.normalize(folder))
    }

    /// The chat whose project folder is a clone of `repo` ("owner/name").
    func session(forRepo repo: String) -> ChatSession? {
        sessions.first { $0.record.githubRepo?.lowercased() == repo.lowercased() }
    }

    /// Reads each project's git remote at launch, so repos show without opening every chat.
    func refreshProjectRepos() async {
        for session in sessions {
            guard let folder = session.record.projectFolder else { continue }
            await GitStatusStore.shared.refresh(folder)
            session.updateGitHubRepo(from: GitStatusStore.shared.status(for: folder))
        }
    }

    func chooseAndOpenProject() {
        if let folder = FolderPicker.choose(startingAt: nil, message: "Choose a project folder. Its chat opens, or a new one starts.") {
            openProject(folder)
        }
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
        Attention.shared.update(session, model: self)
        // A project chat is kept even before its first message, so the binding survives.
        guard !session.items.isEmpty || session.record.projectFolder != nil else { return }
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
                for index in record.items.indices {
                    if record.items[index].approvalState == .pending { record.items[index].approvalState = .expired }
                    if record.items[index].kind == .tool, record.items[index].toolState == .running {
                        record.items[index].toolState = .failed
                    }
                    if record.items[index].phase == .streaming { record.items[index].phase = .final }
                    record.items[index].queued = nil
                }
                return record
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(makeSession)
    }
}

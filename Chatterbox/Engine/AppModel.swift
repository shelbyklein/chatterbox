import AppKit
import Foundation
import Observation

/// Owns the list of conversations and saves each one as JSON in Application Support.
@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [ChatSession] = []
    /// Groups of chats sharing a folder (see Studios.swift).
    var studios: [Studio] = []
    var selectedID: UUID?
    var showingCloneFromGitHub = false

    var activeSessions: [ChatSession] { sessions.filter { $0.record.archivedAt == nil } }

    /// Projects by name, then each open Studio's chats, then other chats by most recent: the
    /// sidebar's order, which the ⌘1–⌘9 shortcuts follow.
    var sidebarProjects: [ChatSession] {
        activeSessions.filter { $0.record.projectFolder != nil }
            .sorted { $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending }
    }
    /// Chats in neither a project nor a Studio. A chat whose Studio is gone shows here too.
    var sidebarChats: [ChatSession] {
        let studioIDs = Set(activeStudios.map(\.id))
        return activeSessions.filter { session in
            session.record.projectFolder == nil && !(session.record.studioID.map(studioIDs.contains) ?? false)
        }
    }
    var sidebarOrder: [ChatSession] {
        sidebarProjects + activeStudios.filter { $0.collapsed != true }.flatMap(chats(in:)) + sidebarChats
    }

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

    /// Chats with changes not yet written, saved together shortly after (see `scheduleSave`).
    @ObservationIgnored private var unsaved: Set<UUID> = []
    @ObservationIgnored private var saveSoonScheduled = false
    @ObservationIgnored private var saveLaterScheduled = false

    /// Settings > General: when off, quitting stops any reply still running.
    static let keepRepliesRunningKey = "keepRepliesRunning"
    static var keepRepliesRunning: Bool { UserDefaults.standard.object(forKey: keepRepliesRunningKey) as? Bool ?? true }

    init() {
        // CHATTERBOX_DATA_DIR keeps tests away from the user's real chats.
        if let dir = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], !dir.isEmpty {
            directory = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("Conversations", isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            directory = base.appendingPathComponent("Chatterbox/Conversations", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadStudios()
        load()
        if activeSessions.isEmpty { newChat() } else { selectedID = activeSessions.first?.id }
        Task { await resumeBackgroundReplies() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
    }

    /// Replies keep running in the background host after the app quits, unless turned off.
    private func applicationWillTerminate() {
        saveUnsaved()
        guard !Self.keepRepliesRunning else { return }
        for session in sessions { session.claudeProcess?.terminate() }
        CodexAppServer.shared.terminate()
    }

    @discardableResult
    func newChat(backend: Backend? = nil) -> ChatSession {
        let defaults = UserDefaults.standard
        let backend = backend ?? Backend(rawValue: defaults.string(forKey: "defaultBackend") ?? "") ?? .claude
        if let empty = sessions.first(where: { $0.items.isEmpty && !$0.isRunning && $0.record.projectFolder == nil && $0.record.studioID == nil && $0.record.archivedAt == nil }) {
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
        if let studio = studio(for: session), studio.archivedAt != nil { unarchiveStudio(studio.id) }
        session.setArchived(false)
        selectedID = session.id
    }

    func delete(_ session: ChatSession) {
        session.shutdown()
        unsaved.remove(session.id)
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

    /// The folder the selected chat works in: its project, or else the working folder.
    var selectedFolder: String? {
        guard let session = selected else { return nil }
        return session.record.boundFolder ?? session.record.codex?.folder
            ?? UserDefaults.standard.string(forKey: "codexFolder") ?? NSHomeDirectory()
    }

    /// Opens a Terminal window in the selected chat's folder.
    func openTerminal() {
        guard let folder = selectedFolder else { return }
        openTerminal(at: folder)
    }

    func chooseAndOpenProject() {
        if let folder = FolderPicker.choose(startingAt: nil, message: "Choose a project folder. Its chat opens, or a new one starts.") {
            openProject(folder)
        }
    }

    // MARK: - Persistence

    private func makeSession(_ record: ConversationRecord) -> ChatSession {
        let session = ChatSession(record: record)
        session.onChange = { [weak self] session in self?.scheduleSave(session, soon: true) }
        session.onStreamed = { [weak self] session in self?.scheduleSave(session, soon: false) }
        return session
    }

    /// Saves are batched and always run between two agent output lines, so each saved record
    /// matches how far its agent's output was read. Changes save on the next turn of the run
    /// loop; streamed text at most once a second.
    private func scheduleSave(_ session: ChatSession, soon: Bool) {
        unsaved.insert(session.id)
        if soon {
            guard !saveSoonScheduled else { return }
            saveSoonScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.saveSoonScheduled = false
                self?.saveUnsaved()
            }
        } else {
            guard !saveLaterScheduled else { return }
            saveLaterScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.saveLaterScheduled = false
                self?.saveUnsaved()
            }
        }
    }

    private func saveUnsaved() {
        guard !unsaved.isEmpty else { return }
        let ids = unsaved
        unsaved = []
        for session in sessions where ids.contains(session.id) { save(session) }
        // After the chats, so each chat's saved state is at least as far along as this.
        if CodexAppServer.shared.isRunning { CodexAppServer.shared.saveResumeState() }
    }

    /// Reattaches chats to replies that kept running (or finished) while the app was closed.
    /// Runs once at launch; without a host running there's nothing to find.
    private func resumeBackgroundReplies() async {
        let linked = sessions.filter(\.awaitingHostResume)
        let processes = (try? await HostClient.shared.list()) ?? []
        for session in linked {
            session.resumeFromHost(processes)
            scheduleSave(session, soon: true)
        }
        CodexAppServer.shared.resume(processes)
        // Logs of ended processes no chat points at anymore. Running ones are left alone: the
        // host lets an agent go once it's idle with no app attached.
        var known = Set(sessions.compactMap { $0.claudeProcess?.hostID })
        if let codex = CodexAppServer.shared.hostID { known.insert(codex) }
        for process in processes where !process.running && !known.contains(process.id) {
            HostClient.shared.forget(id: process.id)
        }
    }

    private var studiosFile: URL { directory.deletingLastPathComponent().appendingPathComponent("Studios.json") }

    func saveStudios() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(studios).write(to: studiosFile, options: .atomic)
        } catch {
            NSLog("Chatterbox: failed to save Studios: \(error)")
        }
    }

    private func loadStudios() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        studios = (try? Data(contentsOf: studiosFile)).flatMap { try? decoder.decode([Studio].self, from: $0) } ?? []
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ session: ChatSession) {
        Attention.shared.update(session, model: self)
        // A project chat is kept even before its first message, so the binding survives.
        guard !session.items.isEmpty || session.record.projectFolder != nil else { return }
        session.prepareForSave()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(session.record).write(to: fileURL(session.id), options: .atomic)
        } catch {
            NSLog("Chatterbox: failed to save conversation: \(error)")
        }
        // Saved, so the host may trim that much of a long log.
        if let link = session.record.claudeHost, HostClient.shared.isConnected {
            HostClient.shared.ack(id: link.processID, offset: link.offset)
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
                var record = record
                for index in record.items.indices { record.items[index].queued = nil }
                return record
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { record in
                let session = makeSession(record)
                // A chat whose agent may still be running in the background host keeps its
                // pending requests and running rows until `resumeBackgroundReplies` checks.
                // Otherwise requests from a previous run can't be answered anymore.
                if session.hasHostLinks { session.awaitingHostResume = true } else { session.settleInterruptedWork() }
                return session
            }
    }
}

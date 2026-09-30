import AppKit
import Foundation

/// A place for messy work that isn't a project: several chats sharing one folder, like a run
/// of creative asks across different apps. Chatterbox makes the folder, and it needn't be a
/// git repo. Each chat in it works in that folder.
struct Studio: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var folder: String
    var createdAt = Date()
    var archivedAt: Date?
    /// Collapsed in the sidebar. Optional so older saves still load.
    var collapsed: Bool?
    /// What the Studio is for and where to look (sites, brand guides, tools), given to every
    /// chat in it.
    var instructions: String?

    var trimmedInstructions: String { instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

extension AppModel {
    /// Studios by name, leaving out archived ones.
    var activeStudios: [Studio] {
        studios.filter { $0.archivedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func studio(_ id: UUID?) -> Studio? {
        guard let id else { return nil }
        return studios.first { $0.id == id }
    }

    func studio(for session: ChatSession) -> Studio? { studio(session.record.studioID) }

    /// A Studio's open chats, most recent first.
    func chats(in studio: Studio) -> [ChatSession] {
        activeSessions.filter { $0.record.studioID == studio.id }
    }

    /// Where new Studio folders go: ~/Chatterbox/Studios (inside the data folder under tests).
    static var studiosBase: URL {
        if let dir = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("Studios", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Chatterbox/Studios", isDirectory: true)
    }

    /// Makes a Studio with its own new folder (or `folder`, if given) and opens its first chat.
    /// `moving` goes in as that first chat instead, when making a Studio from a chat.
    @discardableResult
    func newStudio(named name: String, folder: String? = nil, moving session: ChatSession? = nil) -> Studio? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Studio" : trimmed
        guard let path = folder ?? Self.makeStudioFolder(named: name) else { return nil }
        let studio = Studio(name: name, folder: Self.normalize(path))
        studios.append(studio)
        saveStudios()
        if let session { move(session, to: studio) } else { newChat(in: studio) }
        return studio
    }

    /// A new folder named after the Studio, numbered if the name is taken.
    private static func makeStudioFolder(named name: String) -> String? {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fm = FileManager.default
        var url = studiosBase.appendingPathComponent(safe, isDirectory: true)
        var number = 2
        while fm.fileExists(atPath: url.path) {
            url = studiosBase.appendingPathComponent("\(safe) \(number)", isDirectory: true)
            number += 1
        }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url.path
        } catch {
            NSLog("Chatterbox: couldn't make a Studio folder: \(error)")
            return nil
        }
    }

    /// Opens a new chat in the Studio, reusing an empty one that's already there.
    @discardableResult
    func newChat(in studio: Studio, backend: Backend? = nil) -> ChatSession {
        if let empty = chats(in: studio).first(where: { $0.items.isEmpty && !$0.isRunning }) {
            if let backend { empty.setBackend(backend) }
            selectedID = empty.id
            return empty
        }
        let session = newChat(backend: backend)
        session.setStudio(studio)
        setStudio(studio.id, collapsed: false)
        return session
    }

    /// Puts a chat in a Studio, or takes it out with nil. A chat that's mid-reply, or a
    /// project's chat, stays put.
    func move(_ session: ChatSession, to studio: Studio?) {
        // Project chats belong to their project folder.
        guard !session.isRunning, studio == nil || session.record.projectFolder == nil else { return }
        session.setStudio(studio)
        if let studio { setStudio(studio.id, collapsed: false) }
    }

    /// Whether a chat can be forked: not mid-reply, and not a project's chat (a project
    /// folder has one chat).
    func canFork(_ session: ChatSession) -> Bool {
        !session.isRunning && session.record.projectFolder == nil && !session.items.isEmpty
    }

    /// Copies a chat into a new one beside it (in the same Studio, if it's in one) that
    /// carries on from the same point. Each agent branches its own memory of the
    /// conversation on the fork's next message; the original is left as it was.
    @discardableResult
    func fork(_ session: ChatSession) -> ChatSession? {
        guard canFork(session) else { return nil }
        var record = session.record
        record.id = UUID()
        record.title = session.title.hasSuffix("(fork)") ? session.title : session.title + " (fork)"
        record.createdAt = Date()
        record.updatedAt = Date()
        record.archivedAt = nil
        record.forkedFrom = session.id
        record.currentIssue = nil
        record.turnStartedAt = nil
        record.backgroundTasks = nil
        record.claudeHost = nil
        record.codexHost = nil
        record.claudeForkPending = record.claudeSessionID != nil ? true : nil
        if let thread = record.codex?.threadId {
            record.codex?.forkFrom = thread
            record.codex?.threadId = nil
        }
        for index in record.items.indices {
            record.items[index].queued = nil
            if record.items[index].approvalState == .pending { record.items[index].approvalState = .expired }
        }
        record.items.append(DisplayItem(kind: .notice, text: "Forked from \u{201C}\(session.title)\u{201D}. Nothing here changes the original."))
        let fork = insertSession(record)
        selectedID = fork.id
        return fork
    }

    func renameStudio(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateStudio(id) { $0.name = trimmed }
    }

    func setInstructions(_ text: String, forStudio id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateStudio(id) { $0.instructions = trimmed.isEmpty ? nil : trimmed }
    }

    func setStudio(_ id: UUID, collapsed: Bool) {
        guard studio(id)?.collapsed ?? false != collapsed else { return }
        updateStudio(id) { $0.collapsed = collapsed }
    }

    /// Archives the Studio and its chats. Its folder and files stay where they are, and
    /// unarchiving any of its chats brings the Studio back.
    func archiveStudio(_ id: UUID) {
        guard let studio = studio(id) else { return }
        updateStudio(id) { $0.archivedAt = Date() }
        for session in chats(in: studio) { archive(session) }
    }

    func unarchiveStudio(_ id: UUID) {
        updateStudio(id) { $0.archivedAt = nil }
    }

    func openTerminal(at folder: String) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func updateStudio(_ id: UUID, _ change: (inout Studio) -> Void) {
        guard let index = studios.firstIndex(where: { $0.id == id }) else { return }
        change(&studios[index])
        saveStudios()
    }
}

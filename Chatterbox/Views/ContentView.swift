import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showArchived") private var showArchived = false
    @State private var pendingDelete: ChatSession?
    @State private var addingPin = false
    @State private var renamingProject: ChatSession?
    @State private var projectNickname = ""
    @State private var renamingChat: ChatSession?
    @State private var chatTitle = ""
    /// True while ⌘ is held on its own: the sidebar shows each chat's ⌘-number.
    @State private var showShortcuts = false
    @State private var flagsMonitor: Any?
    @State private var taggingSession: ChatSession?
    @State private var newTag = ""
    @State private var searchText = ""
    @State private var namingStudio = false
    @State private var studioName = ""
    /// The chat that goes into the Studio being named, when making one from a chat.
    @State private var studioFromChat: ChatSession?
    @State private var renamingStudio: Studio?
    /// Show only projects with this tag; empty shows everything.
    @AppStorage("sidebarTagFilter") private var tagFilter = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            // No list selection: macOS would paint the selected row in the system accent (blue).
            // Rows select on click and draw their own subtle highlight instead.
            List {
                // ⌘-numbers follow the full sidebar, so they don't shift while filtering.
                let numbers = Dictionary(uniqueKeysWithValues: model.sidebarOrder.prefix(9).enumerated().map { ($1.id, $0 + 1) })
                let projects = model.sidebarProjects.filter(isShown)
                let chats = model.sidebarChats.filter(isShown)
                let archived = model.archivedSessions.filter(isShown)
                if !isFiltering { PinsSection(addingPin: $addingPin) }
                if isFiltering, projects.isEmpty, chats.isEmpty, archived.isEmpty {
                    Text("No matching chats").foregroundStyle(.secondary)
                }
                // The heading stays while a tag filter is on, so the filter can always be cleared.
                if !projects.isEmpty || activeTag != nil {
                    Section {
                        ForEach(projects) { session in row(session, number: numbers[session.id]) }
                    } header: {
                        HStack {
                            Text("Projects")
                            Spacer()
                            if !model.allTags.isEmpty { tagFilterMenu }
                        }
                    }
                }
                let studios = model.activeStudios.filter(isShown)
                if !studios.isEmpty || !isFiltering {
                    Section {
                        ForEach(studios) { studio in studioGroup(studio, numbers: numbers) }
                        if studios.isEmpty {
                            Text("A Studio groups chats that share one folder, for messy work that isn't a project.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack {
                            Text("Studios")
                            Spacer()
                            Button { beginNewStudio() } label: { Image(systemName: "plus") }
                                .buttonStyle(.borderless)
                                .help("New Studio")
                        }
                    }
                }
                if !chats.isEmpty || !isFiltering {
                    Section(projects.isEmpty && studios.isEmpty ? "" : "Chats") {
                        ForEach(chats) { session in row(session, number: numbers[session.id]) }
                    }
                }
                if !archived.isEmpty {
                    Section("Archived (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { session in row(session, number: nil) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New Claude Chat") { model.newChat(backend: .claude) }
                        Button("New Codex Chat") { model.newChat(backend: .codex) }
                        Divider()
                        Button("New Project Chat\u{2026}") { model.chooseAndOpenProject() }
                        Button("New Project from GitHub\u{2026}") { model.showingCloneFromGitHub = true }
                        Divider()
                        Button("New Studio\u{2026}") { beginNewStudio() }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    } primaryAction: {
                        model.newChat()
                    }
                    .help("New chat (\u{2318}N). Hold to pick Claude, Codex, or a project folder.")
                }
            }
        } detail: {
            if let session = model.selected {
                ChatView(session: session)
                    .id(session.id)
            } else {
                Text("No chat selected").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $model.showingCloneFromGitHub) { CloneFromGitHubView() }
        .sheet(isPresented: $addingPin) { AddPinSheet() }
        .alert("Rename Chat", isPresented: Binding(get: { renamingChat != nil }, set: { if !$0 { renamingChat = nil } })) {
            TextField("Title", text: $chatTitle)
            Button("Rename") { renamingChat?.setTitle(chatTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(studioFromChat == nil ? "New Studio" : "New Studio from Chat", isPresented: $namingStudio) {
            TextField("Name", text: $studioName)
            Button("Create") {
                model.newStudio(named: studioName, moving: studioFromChat)
                studioFromChat = nil
            }
            Button("Cancel", role: .cancel) { studioFromChat = nil }
        } message: {
            Text("Its chats share a new folder in \(AppModel.studiosBase.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")), and can save work there.")
        }
        .alert("Rename Studio", isPresented: Binding(get: { renamingStudio != nil }, set: { if !$0 { renamingStudio = nil } })) {
            TextField("Name", text: $studioName)
            Button("Rename") { if let studio = renamingStudio { model.renameStudio(studio.id, to: studioName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder itself isn't renamed.")
        }
        .alert("Rename Project", isPresented: Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } })) {
            TextField("Name", text: $projectNickname)
            Button("Rename") { renamingProject?.setProjectNickname(projectNickname) }
            if renamingProject?.record.projectNickname != nil {
                Button("Use Folder Name") { renamingProject?.setProjectNickname("") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown in the sidebar and toolbar. The folder itself isn't renamed.")
        }
        .background {
            Color.clear.sheet(isPresented: Binding(get: { ChatCommands.shared.showingQuickSwitcher },
                                                   set: { ChatCommands.shared.showingQuickSwitcher = $0 })) {
                QuickSwitcher().environment(model)
            }
        }
        .alert("New Tag", isPresented: Binding(get: { taggingSession != nil }, set: { if !$0 { taggingSession = nil } })) {
            TextField("Tag name", text: $newTag)
            Button("Add") {
                let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tag.isEmpty, let session = taggingSession, !session.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    session.toggleTag(tag)
                }
                newTag = ""
            }
            Button("Cancel", role: .cancel) { newTag = "" }
        } message: {
            Text("Tags show as pills under the project name.")
        }
        .confirmationDialog("Delete \u{201C}\(pendingDelete?.title ?? "")\u{201D}?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { session in
            Button("Delete Chat", role: .destructive) { model.delete(session) }
            Button("Archive Instead") { model.archive(session) }
        } message: { _ in
            Text("The conversation and its attachments are removed permanently. Archiving keeps them out of the way instead.")
        }
        .task { await model.refreshProjectRepos() }
        .task { Attention.shared.start(model: model) }
        .onChange(of: model.selectedID) { _, id in
            Attention.shared.markSeen(id)
            // A chat you open (like a new one) never hides behind the search or tag filter.
            if let session = model.sessions.first(where: { $0.id == id }), !isShown(session) {
                searchText = ""
                tagFilter = ""
            }
        }
        .onAppear(perform: watchCommandKey)
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
    }
}

extension ContentView {
    /// The tag filter, ignored once no chat has that tag anymore.
    private var activeTag: String? {
        tagFilter.isEmpty ? nil : model.allTags.first { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }
    }

    private var isFiltering: Bool {
        activeTag != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Search matches every word against the chat title, project name, and tags.
    private func isShown(_ session: ChatSession) -> Bool {
        if let tag = activeTag, !session.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            return false
        }
        let text = ([session.title, session.projectName, model.studio(for: session)?.name ?? ""] + session.tags).joined(separator: " ")
        return matchesSearch(text)
    }

    private func matchesSearch(_ text: String) -> Bool {
        searchText.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains($0) }
    }

    /// A Studio shows while any of its chats do, or, with no tag filter, when it has none yet.
    private func isShown(_ studio: Studio) -> Bool {
        let chats = model.chats(in: studio)
        if chats.contains(where: isShown) { return true }
        return activeTag == nil && chats.isEmpty && matchesSearch(studio.name)
    }

    private func beginNewStudio(from session: ChatSession? = nil) {
        studioFromChat = session
        studioName = ""
        namingStudio = true
    }

    /// A Studio as a group that opens to show its chats.
    private func studioGroup(_ studio: Studio, numbers: [UUID: Int]) -> some View {
        let chats = model.chats(in: studio)
        let expanded = Binding(get: { isFiltering || studio.collapsed != true },
                               set: { model.setStudio(studio.id, collapsed: !$0) })
        return DisclosureGroup(isExpanded: expanded) {
            ForEach(chats.filter(isShown)) { session in row(session, number: numbers[session.id]) }
            if chats.isEmpty {
                Button { model.newChat(in: studio) } label: {
                    Label("New Chat", systemImage: "square.and.pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } label: {
            StudioRow(studio: studio, chats: chats, collapsed: !expanded.wrappedValue)
                .contentShape(Rectangle())
                .onTapGesture { expanded.wrappedValue.toggle() }
                // Drop a chat here to move it in.
                .dropDestination(for: String.self) { ids, _ in
                    let moved = ids.compactMap(UUID.init(uuidString:)).compactMap { id in model.sessions.first { $0.id == id } }
                    for session in moved { model.move(session, to: studio) }
                    return !moved.isEmpty
                }
                .contextMenu {
                    Button("New Claude Chat") { model.newChat(in: studio, backend: .claude) }
                    Button("New Codex Chat") { model.newChat(in: studio, backend: .codex) }
                    Divider()
                    Button("Rename Studio\u{2026}") {
                        studioName = studio.name
                        renamingStudio = studio
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: studio.folder)]) }
                    Button("Open Terminal Here") { model.openTerminal(at: studio.folder) }
                    Divider()
                    Button("Archive Studio") { model.archiveStudio(studio.id) }
                }
                .help(studio.folder)
        }
    }

    private var tagFilterMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { activeTag ?? "" }, set: { tagFilter = $0 })) {
                Text("All Chats").tag("")
                if !model.allTags.isEmpty {
                    Section("Projects Tagged") {
                        ForEach(model.allTags, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: activeTag == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(activeTag.map { "Showing projects tagged \u{201C}\($0)\u{201D}" } ?? "Show only projects with a tag")
    }

    /// Holding ⌘ alone shows the ⌘1–⌘9 badges right away; any other key or release hides them.
    private func watchCommandKey() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let onlyCommand = event.type == .flagsChanged
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            if showShortcuts != onlyCommand { showShortcuts = onlyCommand }
            return event
        }
    }

    private func row(_ session: ChatSession, number: Int?) -> some View {
        SidebarRow(session: session, shortcut: showShortcuts ? number : nil)
            .contentShape(Rectangle())
            .onTapGesture { model.selectedID = session.id }
            // Drag onto a Studio to move the chat in.
            .draggable(session.id.uuidString)
            .listRowBackground(
                // Waiting on you wins over selection: the whole row turns yellow.
                RoundedRectangle(cornerRadius: 8)
                    .fill(session.isWaitingOnYou ? Color.yellow.opacity(0.22)
                          : Color.highlight.opacity(model.selectedID == session.id ? 0.10 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.yellow.opacity(session.isWaitingOnYou ? 0.7 : 0), lineWidth: 1))
                    .padding(.horizontal, 10)
            )
            .contextMenu {
                Button("Rename Chat\u{2026}") {
                    chatTitle = session.title
                    renamingChat = session
                }
                if let folder = session.record.projectFolder {
                    Button("Rename Project\u{2026}") {
                        projectNickname = session.projectName
                        renamingProject = session
                    }
                    Menu("Tags") {
                        ForEach(model.allTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(get: { session.tags.contains(tag) }, set: { _ in session.toggleTag(tag) }))
                        }
                        if !model.allTags.isEmpty { Divider() }
                        Button("New Tag\u{2026}") { taggingSession = session }
                    }
                    Divider()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                    Button("Unbind from Folder") { session.unbindProject() }
                    Divider()
                }
                if session.record.archivedAt == nil {
                    Menu("Move to Studio") {
                        ForEach(model.activeStudios) { studio in
                            Button(studio.name) { model.move(session, to: studio) }
                                .disabled(studio.id == session.record.studioID)
                        }
                        if !model.activeStudios.isEmpty { Divider() }
                        Button("New Studio\u{2026}") { beginNewStudio(from: session) }
                        if model.studio(for: session) != nil {
                            Divider()
                            Button("Remove from Studio") { model.move(session, to: nil) }
                        }
                    }
                    .disabled(session.isRunning)
                    Button("Archive Chat") { model.archive(session) }
                } else {
                    Button("Unarchive Chat") { model.unarchive(session) }
                }
                Divider()
                Button("Delete Chat\u{2026}", role: .destructive) { pendingDelete = session }
            }
    }
}

/// A Studio's heading in the sidebar. While it's collapsed it shows whether a chat inside
/// is working or waiting on you.
private struct StudioRow: View {
    let studio: Studio
    let chats: [ChatSession]
    let collapsed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintpalette")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(studio.name).lineLimit(1)
            Spacer(minLength: 0)
            if collapsed {
                if chats.contains(where: \.isWaitingOnYou) {
                    Circle().fill(Color.yellow).frame(width: 7, height: 7).help("A chat here is waiting on you")
                } else if chats.contains(where: { $0.isRunning || $0.hasBackgroundWork }) {
                    ActivitySpinner(color: .secondary).frame(width: 10, height: 10).help("A chat here is working")
                } else if !chats.isEmpty {
                    Text("\(chats.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct SidebarRow: View {
    let session: ChatSession
    /// Shown while ⌘ is held.
    var shortcut: Int?
    private let appearance = ReaderStyleSettings()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: session.record.backend == .codex ? "terminal" : "sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(session.record.backend.label)
            if session.record.projectFolder != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName).lineLimit(1)
                    if !session.tags.isEmpty {
                        TagPills(tags: session.tags)
                    }
                    // What happened last, rather than the chat's title.
                    if let summary = session.lastActionSummary ?? (session.title != "New chat" ? session.title : nil) {
                        Text(summary).font(.caption.weight(session.isWaitingOnYou ? .semibold : .regular))
                            .foregroundStyle(session.isWaitingOnYou ? Color.yellow : Color.secondary).lineLimit(1)
                            .help(session.title)
                    }
                }
                .help(session.record.projectFolder ?? "")
            } else {
                Text(session.title)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Waiting on you, or a finished reply you haven't seen.
            if Attention.shared.unread.contains(session.id)
                || session.items.contains(where: { ($0.kind == .approval || $0.kind == .questions) && $0.approvalState == .pending }) {
                Circle().fill(Color.highlight).frame(width: 7, height: 7)
                    .help("Needs your attention")
            }
            if let shortcut {
                Text("\u{2318}\(shortcut)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                    .foregroundStyle(.secondary)
            } else if session.isRunning {
                if let started = session.record.turnStartedAt {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let minutes = Int(context.date.timeIntervalSince(started)) / 60
                        if minutes >= 1 {
                            Text("\(minutes)m").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                ActivitySpinner(color: appearance.style.color(for: session.record.backend))
                    .frame(width: 10, height: 10)
                    .help("\(session.record.backend.label) is working")
            } else if session.hasBackgroundWork {
                // The reply is done, but a subagent or command is still going.
                ActivitySpinner(color: .secondary)
                    .frame(width: 10, height: 10)
                    .help("Running in the background: \(session.backgroundTasks.map(\.title).joined(separator: ", "))")
            }
        }
    }
}

/// A project's tags as small colored pills, wrapping onto more lines if needed.
struct TagPills: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Self.color(for: tag).opacity(0.22)))
                    .foregroundStyle(Self.color(for: tag))
            }
        }
    }

    /// The same tag always gets the same color.
    static func color(for tag: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .mint, .brown]
        let hash = tag.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

/// Lays children out left to right, wrapping to a new line when a row fills up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

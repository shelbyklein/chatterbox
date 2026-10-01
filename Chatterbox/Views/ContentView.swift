import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showArchived") private var showArchived = false
    @State private var pendingDelete: ChatSession?
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
    @State private var renamingDot = false
    @State private var dotName = ""
    /// The Studio a dragged chat is over, which lights up.
    @State private var dropStudio: UUID?
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
                if !isFiltering {
                    Section { dotRow }
                    PinsSection(place: model.selectedPinPlace) { model.pinSheet = $0 }
                }
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
                    Button { model.showingSettings.toggle() } label: { Label("Settings", systemImage: "gearshape") }
                        .help("Settings (\u{2318},)")
                }
                ToolbarItem {
                    Menu {
                        if let studio = model.selected.flatMap(model.studio(for:)), studio.archivedAt == nil {
                            Button("New Chat in \u{201C}\(studio.name)\u{201D}") { model.newChat(in: studio) }
                            Divider()
                        }
                        Button("New Claude Chat") { model.newChat(backend: .claude) }
                        Button("New Codex Chat") { model.newChat(backend: .codex) }
                        Divider()
                        Button("New Project\u{2026}") { model.showingNewProject = true }
                        Button("Open Project\u{2026}") { model.chooseAndOpenProject() }
                        Button("New Project from GitHub\u{2026}") { model.showingCloneFromGitHub = true }
                        Divider()
                        if !model.activeStudios.isEmpty {
                            Menu("New Chat in Studio") {
                                ForEach(model.activeStudios) { studio in
                                    Button(studio.name) { model.newChat(in: studio) }
                                }
                            }
                        }
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
            if model.showingSettings {
                SettingsPage()
            } else if let page = model.webPage {
                // A website pin: the page takes the chat's place, and the chat floats over it.
                ZStack(alignment: .bottomTrailing) {
                    WebPaneView(page: page) { model.webPage = nil }
                    if let session = model.selected {
                        FloatingChat(session: session) { model.webPage = nil }
                            .padding(16)
                    }
                }
            } else if let session = model.selected {
                ChatView(session: session)
                    .id(session.id)
                    // ⌘J: Dot floats over the chat you're in.
                    .overlay(alignment: .bottomTrailing) {
                        if model.showingDot, !session.isDot, let dot = model.dot {
                            FloatingChat(session: dot, icon: "circle.circle.fill", storageKey: "dotCollapsed") { model.openDot() }
                                .padding(16)
                        }
                    }
            } else {
                Text("No chat selected").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $model.showingCloneFromGitHub) { CloneFromGitHubView() }
        .sheet(isPresented: $model.showingNewProject) { NewProjectSheet().environment(model) }
        .sheet(isPresented: $model.editingDotMemory) { DotMemorySheet() }
        .sheet(item: $model.pinSheet) { AddPinSheet(request: $0) }
        .sheet(isPresented: Binding(get: { model.editingStudioInstructions != nil },
                                    set: { if !$0 { model.editingStudioInstructions = nil } })) {
            if let studio = model.studio(model.editingStudioInstructions) {
                StudioInstructionsSheet(studio: studio).environment(model)
            }
        }
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
            // Picking a chat leaves Settings.
            model.showingSettings = false
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
            ForEach(chats.filter(isShown)) { session in
                // Dropping onto a chat in the Studio moves the dragged one in too.
                row(session, number: numbers[session.id])
                    .dropDestination(for: String.self) { ids, _ in drop(ids, into: studio) }
            }
            if chats.isEmpty {
                Button { model.newChat(in: studio) } label: {
                    Label("New Chat", systemImage: "square.and.pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } label: {
            let place = PinPlace(key: "studio:" + studio.id.uuidString, name: studio.name)
            StudioRow(studio: studio, chats: chats, collapsed: !expanded.wrappedValue,
                      isDropTarget: dropStudio == studio.id, pins: PinStore.shared.pins(in: place),
                      onOpenPin: {
                          // Beside a page, the Studio's own chat (the one open, or its latest).
                          if model.selected?.record.studioID != studio.id, let latest = chats.first { model.selectedID = latest.id }
                      },
                      onNewChat: { model.newChat(in: studio) })
                .contentShape(Rectangle())
                .onTapGesture { expanded.wrappedValue.toggle() }
                // Drop a chat here to move it in.
                .dropDestination(for: String.self) { ids, _ in
                    drop(ids, into: studio)
                } isTargeted: { over in
                    if over { dropStudio = studio.id } else if dropStudio == studio.id { dropStudio = nil }
                }
                .contextMenu {
                    Button("New Claude Chat") { model.newChat(in: studio, backend: .claude) }
                    Button("New Codex Chat") { model.newChat(in: studio, backend: .codex) }
                    Divider()
                    Button("Studio Instructions\u{2026}") { model.editingStudioInstructions = studio.id }
                    Button("Add Pin\u{2026}") { model.pinSheet = PinSheetRequest(place: place, current: place) }
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

    /// Dot at the top of the sidebar: click to open it full size.
    private var dotRow: some View {
        let dot = model.dot
        let selected = dot != nil && model.selectedID == dot?.id
        return HStack(spacing: 8) {
            Image(systemName: "circle.circle.fill").foregroundStyle(Color.highlight)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.dotName).fontWeight(.medium)
                Text(dot?.lastActionSummary ?? "Runs your chats for you. \u{2318}J from anywhere.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if dot?.isWaitingOnYou == true {
                Circle().fill(Color.yellow).frame(width: 7, height: 7)
            } else if dot?.isRunning == true {
                ActivitySpinner(color: .secondary).frame(width: 10, height: 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openDot() }
        .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(Color.highlight.opacity(selected ? 0.10 : 0)).padding(.horizontal, 10))
        .contextMenu {
            Button("Open \(model.dotName)") { model.openDot() }
            Button("Rename\u{2026}") { dotName = model.dotName; renamingDot = true }
            Button(model.showingDot ? "Hide Floating Dot" : "Float Over Chats  \u{2318}J") { _ = model.ensureDot(); model.showingDot.toggle() }
        }
        .help("\(model.dotName) runs your other chats: ask it to check on a project, hand work to a chat, or start one.")
        .alert("Rename \(model.dotName)", isPresented: $renamingDot) {
            TextField("Name", text: $dotName)
            Button("Rename") { model.renameDot(dotName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its name everywhere in Chatterbox, and what it's told it's called.")
        }
    }

    /// Moves dragged chats into a Studio. Project chats stay with their projects.
    private func drop(_ ids: [String], into studio: Studio) -> Bool {
        dropStudio = nil
        let moved = ids.compactMap(UUID.init(uuidString:))
            .compactMap { id in model.sessions.first { $0.id == id } }
            .filter { $0.record.projectFolder == nil && $0.record.studioID != studio.id }
        for session in moved { model.move(session, to: studio) }
        return !moved.isEmpty
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
        let place = session.record.projectFolder != nil ? model.pinPlace(for: session) : nil
        return SidebarRow(session: session, shortcut: showShortcuts ? number : nil, pins: PinStore.shared.pins(in: place),
                          onOpenPin: { model.selectedID = session.id })
            // Drop a link or file on a project to pin it there.
            .onDrop(of: [.url, .fileURL], isTargeted: nil) { providers in
                guard let place else { return false }
                return PinPills.drop(providers, into: place)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selectedID = session.id }
            // Drag onto a Studio to move the chat in. Project chats stay put.
            .modifier(ChatDrag(id: session.record.projectFolder == nil ? session.id : nil))
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
                if session.record.projectFolder == nil, !session.items.isEmpty {
                    Button("Fork Chat") { model.fork(session) }
                        .disabled(!model.canFork(session))
                }
                if let folder = session.record.projectFolder {
                    if let place {
                        Button("Add Pin\u{2026}") { model.pinSheet = PinSheetRequest(place: place, current: place) }
                    }
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
                if session.record.archivedAt == nil, session.record.projectFolder == nil {
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
                }
                if session.record.archivedAt == nil {
                    Button("Archive Chat") { model.archive(session) }
                } else {
                    Button("Unarchive Chat") { model.unarchive(session) }
                }
                Divider()
                Button("Delete Chat\u{2026}", role: .destructive) { pendingDelete = session }
            }
    }
}

/// Lets a chat row be dragged onto a Studio; `nil` (a project chat) isn't draggable.
private struct ChatDrag: ViewModifier {
    let id: UUID?

    func body(content: Content) -> some View {
        if let id { content.draggable(id.uuidString) } else { content }
    }
}

/// A Studio's heading in the sidebar. While it's collapsed it shows whether a chat inside
/// is working or waiting on you.
private struct StudioRow: View {
    let studio: Studio
    let chats: [ChatSession]
    let collapsed: Bool
    var isDropTarget = false
    var pins: [Pin] = []
    var onOpenPin: () -> Void = {}
    var onNewChat: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            heading
            if !pins.isEmpty { PinPills(pins: pins, onOpen: onOpenPin).padding(.leading, 20) }
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color.highlight.opacity(isDropTarget ? 0.12 : 0))
            .padding(.horizontal, -6))
    }

    private var heading: some View {
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
            Button(action: onNewChat) { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("New chat in \(studio.name)")
                .accessibilityLabel("New Chat in \(studio.name)")
        }
    }
}

private struct SidebarRow: View {
    /// Centers a shape (spinner, dot) on the first line of text, which it's baseline-aligned
    /// with; shapes have no baseline, so they'd otherwise sit on it and look low.
    static func centerOnTextLine(_ d: ViewDimensions) -> CGFloat { d.height / 2 + 4 }

    let session: ChatSession
    /// Shown while ⌘ is held.
    var shortcut: Int?
    /// A project's own pins, shown as pills under its name.
    var pins: [Pin] = []
    /// Called before a pill opens, so the page opens with this chat beside it.
    var onOpenPin: () -> Void = {}
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
                    if !pins.isEmpty {
                        PinPills(pins: pins, onOpen: onOpenPin)
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
                    .alignmentGuide(.firstTextBaseline, computeValue: Self.centerOnTextLine)
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
                    .alignmentGuide(.firstTextBaseline, computeValue: Self.centerOnTextLine)
                    .help("\(session.record.backend.label) is working")
            } else if session.hasBackgroundWork {
                // The reply is done, but a subagent or command is still going.
                ActivitySpinner(color: .secondary)
                    .frame(width: 10, height: 10)
                    .alignmentGuide(.firstTextBaseline, computeValue: Self.centerOnTextLine)
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

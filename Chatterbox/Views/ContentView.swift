import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showArchived") private var showArchived = false
    @State private var pendingDelete: ChatSession?
    /// True while ⌘ is held on its own: the sidebar shows each chat's ⌘-number.
    @State private var showShortcuts = false
    @State private var flagsMonitor: Any?
    @State private var taggingSession: ChatSession?
    @State private var newTag = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedID) {
                let projects = model.sidebarProjects
                let chats = model.sidebarChats
                let numbers = Dictionary(uniqueKeysWithValues: (projects + chats).prefix(9).enumerated().map { ($1.id, $0 + 1) })
                let archived = model.archivedSessions
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { session in row(session, number: numbers[session.id]) }
                    }
                }
                Section(projects.isEmpty ? "" : "Chats") {
                    ForEach(chats) { session in row(session, number: numbers[session.id]) }
                }
                if !archived.isEmpty {
                    Section("Archived (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { session in row(session, number: nil) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New Claude Chat") { model.newChat(backend: .claude) }
                        Button("New Codex Chat") { model.newChat(backend: .codex) }
                        Divider()
                        Button("New Project Chat\u{2026}") { model.chooseAndOpenProject() }
                        Button("New Project from GitHub\u{2026}") { model.showingCloneFromGitHub = true }
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
        .onAppear(perform: watchCommandKey)
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
    }
}

extension ContentView {
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
            .tag(session.id)
            .contextMenu {
                if let folder = session.record.projectFolder {
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
                    Button("Archive Chat") { model.archive(session) }
                } else {
                    Button("Unarchive Chat") { model.unarchive(session) }
                }
                Divider()
                Button("Delete Chat\u{2026}", role: .destructive) { pendingDelete = session }
            }
    }
}

private struct SidebarRow: View {
    let session: ChatSession
    /// Shown while ⌘ is held.
    var shortcut: Int?

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
                    if session.title != "New chat" {
                        Text(session.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .help(session.record.projectFolder ?? "")
            } else {
                Text(session.title)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let shortcut {
                Text("\u{2318}\(shortcut)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                    .foregroundStyle(.secondary)
            } else if session.isRunning {
                ProgressView().controlSize(.mini)
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

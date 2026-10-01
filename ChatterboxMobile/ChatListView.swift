import SwiftUI

/// The Mac's chats, grouped like its sidebar: projects, each Studio, then other chats. On
/// iPad the open chat sits beside them; on iPhone it opens over them.
struct ChatListView: View {
    @Environment(MobileStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: UUID?
    /// The chat that's open, kept if it drops out of the list (archived on the Mac).
    @State private var opened: Companion.ChatSummary?
    /// On iPad, the chat list stays beside the chat, in portrait too.
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var search = ""
    /// The Studio whose instructions are open.
    @State private var editingStudio: Companion.ChatGroup?

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationTitle(store.connection?.macName ?? "Chatterbox")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable { await store.loadChats() }
                .searchable(text: $search, prompt: "Search chats")
                .sheet(item: $editingStudio) { group in
                    if let id = group.studioID {
                        StudioInstructionsEditor(title: group.title, studio: id, initial: group.instructions ?? "")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { connectionMenu }
                    ToolbarItem(placement: .topBarTrailing) { newChatMenu }
                }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, id in
            if let found = id.flatMap({ id in allChats.first { $0.id == id } }) { opened = found }
        }
        // Keeps the list current while it's on screen.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.loadChats()
                #if DEBUG
                // Simulator tests: open the first chat.
                if selection == nil, ProcessInfo.processInfo.environment["CHATTERBOX_TEST_OPEN"] != nil,
                   let first = allChats.first { selection = first.id }
                #endif
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// iPad's sidebar style beside the chat; the iPhone's grouped list on its own.
    @ViewBuilder
    private var sidebar: some View {
        if sizeClass == .regular {
            chatList.listStyle(.sidebar)
        } else {
            chatList.listStyle(.insetGrouped)
        }
    }

    private var chatList: some View {
        List(selection: $selection) {
            if let problem = store.problem {
                Section {
                    Label(problem, systemImage: "wifi.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            if let list = store.chatList {
                if search.isEmpty, let pins = list.pins, !pins.isEmpty {
                    Section("Pins") { MobilePinPills(pins: pins) }
                }
                ForEach(filtered(list.groups)) { group in
                    Section {
                        if search.isEmpty, let pins = group.pins, !pins.isEmpty {
                            MobilePinPills(pins: pins)
                        }
                        ForEach(group.chats) { chat in
                            ChatRow(chat: chat).tag(chat.id)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { archive(chat) } label: { Label("Archive", systemImage: "archivebox") }
                                }
                        }
                    } header: {
                        HStack {
                            Label(group.title, systemImage: group.kind == .dot ? "circle.circle.fill"
                                  : group.kind == .studio ? "paintpalette" : group.kind == .projects ? "folder" : "bubble.left.and.bubble.right")
                            Spacer()
                            if group.kind == .studio {
                                Button { editingStudio = group } label: { Image(systemName: "text.book.closed") }
                                    .accessibilityLabel("\(group.title) instructions")
                            }
                        }
                    }
                }
            } else if store.problem == nil {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
    }

    private var connectionMenu: some View {
        Menu {
            if let connection = store.connection {
                Section("Connected to \(connection.macName)") {
                    ForEach(connection.hosts, id: \.self) { Text($0) }
                }
            }
            Button("Unpair This \(UIDevice.current.model)", role: .destructive) { store.forget() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let chat = selectedChat {
            NavigationStack { ChatDetailView(chat: chat, open: open) }
                .id(chat.id)
        } else {
            ContentUnavailableView("Choose a Chat", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Your chats from \(store.connection?.macName ?? "your Mac") are in the sidebar."))
        }
    }

    /// New chats: on their own, or in a Studio.
    private var newChatMenu: some View {
        Menu {
            Button { newChat(studio: nil, backend: "claude") } label: { Label("New Claude Chat", systemImage: "sparkle") }
            Button { newChat(studio: nil, backend: "codex") } label: { Label("New Codex Chat", systemImage: "terminal") }
            let studios = (store.chatList?.groups ?? []).filter { $0.kind == .studio }
            if !studios.isEmpty {
                Section("In a Studio") {
                    ForEach(studios) { group in
                        Button { newChat(studio: UUID(uuidString: String(group.id.dropFirst("studio-".count))), backend: nil) } label: {
                            Label(group.title, systemImage: "paintpalette")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("New Chat")
    }

    private func newChat(studio: UUID?, backend: String?) {
        Task {
            if let detail = try? await store.newChat(in: studio, backend: backend) { open(detail.summary) }
            await store.loadChats()
        }
    }

    private func archive(_ chat: Companion.ChatSummary) {
        Task {
            _ = try? await store.setArchived(true, chat: chat.id)
            if selection == chat.id { selection = nil }
            await store.loadChats()
        }
    }

    /// Opens a chat, even one the list doesn't show yet (a new, empty chat).
    private func open(_ chat: Companion.ChatSummary) {
        opened = chat
        selection = chat.id
    }

    /// Chats whose title, project, Studio, or latest line has every word searched for.
    private func filtered(_ groups: [Companion.ChatGroup]) -> [Companion.ChatGroup] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return groups }
        return groups.compactMap { group in
            var group = group
            group.chats = group.chats.filter { chat in
                let text = [chat.title, chat.project ?? "", chat.subtitle ?? "", group.title].joined(separator: " ")
                return words.allSatisfy { text.localizedStandardContains($0) }
            }
            return group.chats.isEmpty ? nil : group
        }
    }

    private var allChats: [Companion.ChatSummary] { store.chatList?.groups.flatMap(\.chats) ?? [] }

    private var selectedChat: Companion.ChatSummary? {
        guard let selection else { return nil }
        return allChats.first { $0.id == selection } ?? (opened?.id == selection ? opened : nil)
    }
}

private struct ChatRow: View {
    let chat: Companion.ChatSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: chat.backend == "codex" ? "terminal" : "sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.project ?? chat.title).lineLimit(1)
                if let subtitle = chat.subtitle ?? (chat.project != nil ? chat.title : nil) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(chat.isWaitingOnYou ? .yellow : .secondary)
                        .lineLimit(2)
                }
                if let pins = chat.pins, !pins.isEmpty {
                    MobilePinPills(pins: pins)
                }
            }
            Spacer(minLength: 0)
            if chat.isWaitingOnYou {
                Circle().fill(.yellow).frame(width: 8, height: 8)
            } else if chat.isRunning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

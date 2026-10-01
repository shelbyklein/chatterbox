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

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationTitle(store.connection?.macName ?? "Chatterbox")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable { await store.loadChats() }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { connectionMenu } }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, id in
            opened = id.flatMap { id in allChats.first { $0.id == id } }
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
                ForEach(list.groups) { group in
                    Section {
                        ForEach(group.chats) { chat in
                            ChatRow(chat: chat).tag(chat.id)
                        }
                    } header: {
                        Label(group.title, systemImage: group.kind == .studio ? "paintpalette" : group.kind == .projects ? "folder" : "bubble.left.and.bubble.right")
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
            NavigationStack { ChatDetailView(chat: chat) }
                .id(chat.id)
        } else {
            ContentUnavailableView("Choose a Chat", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Your chats from \(store.connection?.macName ?? "your Mac") are in the sidebar."))
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

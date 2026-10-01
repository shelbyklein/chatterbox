import SwiftUI

/// The Mac's chats, grouped like its sidebar: projects, each Studio, then other chats.
struct ChatListView: View {
    @Environment(MobileStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Companion.ChatSummary] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
                                NavigationLink(value: chat) { ChatRow(chat: chat) }
                            }
                        } header: {
                            Label(group.title, systemImage: group.kind == .studio ? "paintpalette" : group.kind == .projects ? "folder" : "bubble.left.and.bubble.right")
                        }
                    }
                } else if store.problem == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(store.connection?.macName ?? "Chatterbox")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Companion.ChatSummary.self) { chat in ChatDetailView(chat: chat) }
            .refreshable { await store.loadChats() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let connection = store.connection {
                            Section("Connected to \(connection.macName)") {
                                ForEach(connection.hosts, id: \.self) { Text($0) }
                            }
                        }
                        Button("Unpair This iPhone", role: .destructive) { store.forget() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Keeps the list current while it's on screen.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await store.loadChats()
                    #if DEBUG
                    // Simulator tests: open the first chat.
                    if path.isEmpty, ProcessInfo.processInfo.environment["CHATTERBOX_TEST_OPEN"] != nil,
                       let first = store.chatList?.groups.first?.chats.first { path = [first] }
                    #endif
                    try? await Task.sleep(for: .seconds(4))
                }
            }
        }
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

import SwiftUI
import UIKit

/// The iPhone's home: Golem first, full screen, with the chat list a tab away. (The iPad
/// keeps the list beside the chat.)
struct MobileHome: View {
    enum Tab: Hashable { case golem, chats }
    @Environment(MobileStore.self) private var store
    @AppStorage("mobileHomeTab") private var tab = "golem"

    var body: some View {
        TabView(selection: Binding(get: { tab == "chats" ? Tab.chats : .golem }, set: { tab = $0 == .chats ? "chats" : "golem" })) {
            GolemHome()
                .tabItem { Label { Text(golemName) } icon: { golemIcon } }
                .tag(Tab.golem)
            ChatListView(hidesAssistant: true)
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .badge(waitingCount)
                .tag(Tab.chats)
        }
        // A tapped notification opens the tab its chat lives in.
        .onChange(of: MobilePushNotifications.shared.pendingChat) { _, id in
            guard let id else { return }
            if id == assistant?.id {
                tab = "golem"
                MobilePushNotifications.shared.pendingChat = nil
            } else {
                tab = "chats"
            }
        }
    }

    private var assistant: Companion.ChatSummary? {
        store.chatList?.groups.first { $0.kind == .dot }?.chats.first
    }

    private var golemName: String { assistant?.title ?? "Golem" }

    /// Chats (other than Golem) waiting on you.
    private var waitingCount: Int {
        (store.chatList?.groups ?? []).filter { $0.kind != .dot }.flatMap(\.chats).filter(\.isWaitingOnYou).count
    }

    /// His head, sized for the tab bar; a plain symbol until it has downloaded.
    private var golemIcon: Image {
        guard let head = MobileGolem.shared.head else { return Image(systemName: "circle.circle.fill") }
        let size = CGSize(width: 30, height: 19)
        let image = UIGraphicsImageRenderer(size: size).image { _ in head.draw(in: CGRect(origin: .zero, size: size)) }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}

/// Golem's chat as the home screen, kept current while it's showing.
private struct GolemHome: View {
    @Environment(MobileStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var history: MobileChatHistory?

    private var assistant: Companion.ChatSummary? {
        store.chatList?.groups.first { $0.kind == .dot }?.chats.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let chat = assistant, let history, history.id == chat.id {
                    ChatDetailView(chat: chat, history: history)
                        .id(chat.id)
                        .onAppear { MobilePushNotifications.shared.readingChat = chat.id }
                        .onDisappear {
                            if MobilePushNotifications.shared.readingChat == chat.id { MobilePushNotifications.shared.readingChat = nil }
                        }
                } else if let problem = store.problem {
                    ContentUnavailableView("Can't reach \(store.connection?.macName ?? "your Mac")", systemImage: "wifi.exclamationmark",
                                           description: Text(problem))
                } else {
                    ProgressView()
                }
            }
        }
        .onChange(of: assistant?.id) { attach() }
        .onAppear { attach() }
        // The list and Golem's transcript, refreshed while the app is open.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await MobileGolem.shared.load(from: store) }
            while !Task.isCancelled {
                if store.chatList == nil { await store.loadChats() }
                attach()
                if let history { await history.refresh(in: store).value }
                do { try await Task.sleep(for: .seconds(history?.detail?.summary.isRunning == true ? 1.2 : 4)) }
                catch { return }
            }
        }
    }

    private func attach() {
        guard let chat = assistant, history?.id != chat.id else { return }
        history?.cancel()
        let fresh = MobileChatHistory(id: chat.id)
        history = fresh
        fresh.refresh(in: store, force: true)
    }
}

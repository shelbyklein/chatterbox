import SwiftUI

#if !GOLEM_APP
@main
struct ChatterboxMobileApp: App {
    @UIApplicationDelegateAdaptor(MobilePushAppDelegate.self) private var delegate
    @State private var store = MobileStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isPaired {
                    ChatterboxTabs()
                } else {
                    ConnectView()
                }
            }
            .environment(store).defaultAppStorage(AppPreferences.defaults)
            // Replies read like on the Mac, at a phone's size.
            .environment(\.readerStyle, .mobile)
            .onOpenURL { url in
                guard url.scheme == "chatterbox", url.host == "chat",
                      let id = UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { return }
                MobilePushNotifications.shared.pendingChat = id
            }
            #if DEBUG
            .task { await CompanionTransportProbe.runIfRequested() }
            .task {
                // Simulator tests: pair from the environment instead of typing.
                let env = ProcessInfo.processInfo.environment
                if !store.isPaired, let host = env["CHATTERBOX_TEST_HOST"], let code = env["CHATTERBOX_TEST_CODE"] {
                    try? await store.pair(host: host, code: code)
                }
            }
            #endif
        }
    }
}


/// The home's bottom tabs: Projects, Studios and Chats, like the Mac's Home pages.
struct ChatterboxTabs: View {
    @Environment(MobileStore.self) private var store
    @AppStorage("mobileChatListPage") private var tab = ChatListView.Page.projects.rawValue

    var body: some View {
        TabView(selection: $tab) {
            ForEach(ChatListView.Page.allCases) { page in
                ChatListView(hidesAssistant: true, fixedPage: page)
                    .tabItem { Label(page.title, systemImage: page.icon) }
                    .badge(waiting(on: page))
                    .tag(page.rawValue)
            }
        }
        // A tapped notification opens the tab its chat lives in.
        .onChange(of: MobilePushNotifications.shared.pendingChat) { _, id in
            guard let id else { return }
            let kind = store.chatList?.groups.first { $0.chats.contains { $0.id == id } }?.kind
            tab = (ChatListView.Page.allCases.first { $0.kind == kind } ?? .chats).rawValue
        }
    }

    private func waiting(on page: ChatListView.Page) -> Int {
        (store.chatList?.groups ?? []).filter { $0.kind == page.kind }.flatMap(\.chats).filter(\.isWaitingOnYou).count
    }
}

#endif

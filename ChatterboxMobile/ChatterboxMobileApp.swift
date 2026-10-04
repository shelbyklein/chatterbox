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
                    ChatListView(hidesAssistant:true)
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

#endif

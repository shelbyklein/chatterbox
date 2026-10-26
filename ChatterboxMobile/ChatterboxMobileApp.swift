import SwiftUI

#if !GOLEM_APP
@main
struct ChatterboxMobileApp: App {
    @UIApplicationDelegateAdaptor(MobilePushAppDelegate.self) private var delegate
    @State private var store = MobileStore()
    @AppStorage(MobileAppearance.schemeKey, store: AppPreferences.defaults) private var scheme = "system"
    @AppStorage(MobileAppearance.claudeKey, store: AppPreferences.defaults) private var claudeColor = ReaderStyle.claudeDefault
    @AppStorage(MobileAppearance.codexKey, store: AppPreferences.defaults) private var codexColor = ReaderStyle.codexDefault

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isPaired {
                    // Redrawn when the agents' colors change (Appearance).
                    ChatterboxTabs().id(claudeColor + "|" + codexColor)
                        .modifier(TabletLayoutOnBigScreens())
                        #if DEBUG
                        // A native safe-area fixture for keyboard-sized occlusion on an
                        // open screen. The window stays large while usable height shrinks.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if let raw = ProcessInfo.processInfo.environment["CHATTERBOX_TEST_BOTTOM_OCCLUSION"],
                               let height = Double(raw) {
                                Color.clear.frame(height: height)
                            }
                        }
                        #endif
                } else {
                    ConnectView()
                }
            }
            .environment(store).defaultAppStorage(AppPreferences.defaults)
            .preferredColorScheme(MobileAppearance.colorScheme(scheme))
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


/// The iPad layout (sessions beside the open one) on any screen big enough in both directions,
/// whatever width class iOS reports: an open iPhone Duo is "compact" in portrait, like a phone,
/// though it has an iPad mini's room. Phones on their side (short) and narrow iPad windows keep
/// the phone layout.
struct TabletLayoutOnBigScreens: ViewModifier {
    static let minimumSide: CGFloat = 600
    @State private var windowSize: CGSize?

    func body(content: Content) -> some View {
        let layout = GeometryReader { geometry in
            // The keyboard reduces usable height, not the size of the open phone.
            // Window bounds also respect narrow iPad/Stage Manager windows, unlike
            // UIScreen bounds. Keep keyboard avoidance on the content itself.
            let size = windowSize ?? geometry.size
            let big = min(size.width, size.height) >= Self.minimumSide
            content.transformEnvironment(\.horizontalSizeClass) { if big { $0 = .regular } }
        }
        .background { SessionWindowSizeProbe(size: $windowSize).allowsHitTesting(false) }
        #if DEBUG
        // Tests: report compact width on an iPad, as an open iPhone Duo does in portrait.
        if ProcessInfo.processInfo.environment["CHATTERBOX_TEST_COMPACT_WIDTH"] != nil {
            return AnyView(layout.environment(\.horizontalSizeClass, .compact))
        }
        #endif
        return AnyView(layout)
    }
}

/// Measures the app window independently of keyboard/safe-area occlusion. Bounds
/// change when the Duo opens/closes or the iPad window resizes, but not when typing.
private struct SessionWindowSizeProbe: UIViewRepresentable {
    @Binding var size: CGSize?

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.report = { value in if size != value { size = value } }
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.report = { value in if size != value { size = value } }
        probe.check()
    }

    final class Probe: UIView {
        var report: (CGSize) -> Void = { _ in }
        override func didMoveToWindow() { super.didMoveToWindow(); check() }
        override func layoutSubviews() { super.layoutSubviews(); check() }

        func check() {
            guard let value = window?.bounds.size, value.width > 0, value.height > 0 else { return }
            DispatchQueue.main.async { [weak self] in self?.report(value) }
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
        // Mac Screen: the Mac's own Screen Sharing, at the address the app last reached it.
        .fullScreenCover(isPresented: Binding(get: { store.showingMacScreen }, set: { store.showingMacScreen = $0 })) {
            MacScreenView(hosts: store.connection?.hosts ?? [])
        }
        // Feedback: the screenshot in Mark Up, then into the Chatterbox session's message box.
        .fullScreenCover(item: Binding(get: { store.feedbackSketch }, set: { store.feedbackSketch = $0 })) { request in
            SketchView(request: request) { image in store.placeFeedback(image) }
        }
        .alert("Couldn't Send Feedback", isPresented: Binding(get: { store.feedbackProblem != nil }, set: { if !$0 { store.feedbackProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.feedbackProblem ?? "") }
        // Activity moved into the ⋯ menu; a saved tab from before lands on Projects.
        .onAppear { if ChatListView.Page(rawValue: tab) == nil { tab = ChatListView.Page.projects.rawValue } }
        // A tapped notification opens the tab its chat lives in.
        .onChange(of: MobilePushNotifications.shared.pendingChat) { _, id in
            guard let id else { return }
            let kind = store.chatList?.groups.first { $0.chats.contains { $0.id == id } }?.kind
            // All lists every chat already; otherwise go to the chat's own tab.
            if tab != ChatListView.Page.all.rawValue {
                tab = (ChatListView.Page.allCases.first { $0 != .all && $0.kind == kind } ?? .chats).rawValue
            }
        }
    }

    private func waiting(on page: ChatListView.Page) -> Int {
        (store.chatList?.groups ?? []).filter { page.includes($0.kind) }.flatMap(\.chats).filter(\.isWaitingOnYou).count
    }
}

#endif

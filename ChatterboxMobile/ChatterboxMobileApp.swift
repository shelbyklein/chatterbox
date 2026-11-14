import SwiftUI

@main
struct ChatterboxMobileApp: App {
    @UIApplicationDelegateAdaptor(MobilePushAppDelegate.self) private var delegate
    @State private var store = MobileStore()
    @State private var widgetChat: WidgetChatShortcut?
    @State private var widgetChatResult: UUID?
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
                        .safeAreaInset(edge: .trailing, spacing: 0) {
                            if let raw = ProcessInfo.processInfo.environment["CHATTERBOX_TEST_TRAILING_OCCLUSION"],
                               let width = Double(raw) {
                                Color.clear.frame(width: width)
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
            .sheet(isPresented: Binding(get: { store.showingUsage || (store.isPaired && widgetChat != nil) }, set: {
                if !$0 { store.showingUsage = false; widgetChat = nil }
            }), onDismiss: {
                // Open only after the sheet closes, as with other mobile navigation actions.
                if let id = widgetChatResult {
                    widgetChatResult = nil
                    store.pendingComposerFocus = id
                    MobilePushNotifications.shared.pendingChat = id
                }
            }) {
                if let shortcut = widgetChat {
                    MobileWidgetNewChat(shortcut: shortcut) { widgetChatResult = $0 }.environment(store)
                } else {
                    MobileUsageView().environment(store)
                }
            }
            .onOpenURL { url in
                guard url.scheme == Flavor.current.urlScheme else { return }
                if let shortcut = WidgetChatShortcut(url: url) {
                    guard widgetChat == nil else { return }
                    store.showingUsage = false
                    widgetChat = shortcut
                    return
                }
                if url.host == "usage" {
                    guard widgetChat == nil else { return }
                    store.showingUsage = true
                    return
                }
                guard url.host == "chat",
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

/// The home's bottom tabs: the Desk first (plans/front-desk.md), then Activity, Projects,
/// Studios and Chats, like the Mac's Home pages; All is Chats' other half. A phone's bar holds
/// five (iOS puts the rest behind More, inside a second navigation bar) and an iPad mini's
/// scrolls the sixth out of sight, so the bar keeps to five everywhere.
struct ChatterboxTabs: View {
    typealias Page = ChatListView.Page
    /// The Desk's tab; the others are named for their pages.
    static let desk = "desk"
    @Environment(MobileStore.self) private var store
    /// A fresh install opens on the Desk; afterwards, on the tab last used.
    @AppStorage("mobileChatListPage") private var tab = ChatterboxTabs.desk
    /// Chats or All, on the Chats tab.
    @AppStorage("mobileChatsScope") private var chatsScope = Page.chats.rawValue
    private let pages = Page.allCases.filter { $0 != .all }
    /// Resolve the removed destination before TabView can reset an unknown selection to Desk.
    private var selectedTab: String { tab == "pinned" ? Page.activity.rawValue : tab }

    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: { tab = $0 })) {
            MobileDeskView()
                .tabItem { Label("Desk", systemImage: "lamp.desk") }
                .badge(store.latestDesk.map(MobileDeskView.waiting) ?? 0)
                .tag(Self.desk)
            ForEach(pages) { page in
                Group {
                    if page == .chats {
                        ChatListView(fixedPage: chatsScope == Page.all.rawValue ? .all : .chats, isSelected: selectedTab == page.rawValue,
                                     scopes: [.chats, .all], scope: $chatsScope)
                    } else {
                        ChatListView(fixedPage: page, isSelected: selectedTab == page.rawValue)
                    }
                }
                .tabItem { Label(page.title, systemImage: page.icon) }
                .badge(waiting(on: page))
                .tag(page.rawValue)
            }
        }
        // What changed, once after an update brings new lines (Shared/Changelog.swift).
        .whatsNewNote()
        // Feedback: the screenshot in Mark Up, then into the Chatterbox session's message box.
        .fullScreenCover(item: Binding(get: { store.feedbackSketch }, set: { store.feedbackSketch = $0 })) { request in
            SketchView(request: request) { image, notes in store.placeFeedback(image, notes: notes) }
        }
        .alert("Couldn't Send Feedback", isPresented: Binding(get: { store.feedbackProblem != nil }, set: { if !$0 { store.feedbackProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.feedbackProblem ?? "") }
        .onAppear(perform: settleTab)
        // A tapped notification, or a session opened from the Desk, opens in the tab its chat
        // lives in; that tab's list opens it (ChatListView). Also at launch, from a notification.
        .onChange(of: MobilePushNotifications.shared.pendingChat, initial: true) { _, id in
            guard let id else { return }
            Task {
                // The tab comes from the chat list; a new session may not be in it yet.
                if store.chatList?.groups.contains(where: { $0.chats.contains { $0.id == id } }) != true { await store.loadChats() }
                guard MobilePushNotifications.shared.pendingChat == id else { return }
                // All lists every chat already; otherwise go to the chat's own tab.
                if tab == Page.activity.rawValue || (tab == Page.chats.rawValue && chatsScope == Page.all.rawValue) { return }
                let page = Page.home(for: store.chatList?.groups.first { $0.chats.contains { $0.id == id } }?.kind)
                if page == .chats { chatsScope = Page.chats.rawValue }
                tab = page.rawValue
            }
        }
    }

    /// Pinned is now Activity. The older All tab is Chats showing All.
    private func settleTab() {
        if tab == "pinned" { tab = Page.activity.rawValue }
        else if tab == Page.all.rawValue { chatsScope = Page.all.rawValue; tab = Page.chats.rawValue }
        else if tab != Self.desk, Page(rawValue: tab) == nil { tab = Self.desk }
        // The Desk is new: open on it once after updating, then the last tab as before.
        // Tests that launch on a set tab (-mobileChatListPage) keep it.
        if !UserDefaults.standard.bool(forKey: "deskIntroduced") {
            UserDefaults.standard.set(true, forKey: "deskIntroduced")
            if !ProcessInfo.processInfo.arguments.contains("-mobileChatListPage") { tab = Self.desk }
        }
    }

    private func waiting(on page: ChatListView.Page) -> Int {
        (store.chatList?.groups ?? []).filter { page.includes($0.kind) }.flatMap(\.chats).filter(\.isWaitingOnYou).count
    }
}

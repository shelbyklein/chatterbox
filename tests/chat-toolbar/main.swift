import AppKit
import SwiftUI

// Run through scripts/test-chat-toolbar.sh. Uses copies of saved chats; no agent is resumed.
// Checks #29: the chat's toolbar items survive a chat switch and show the new chat.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)

func save(_ window: NSWindow, _ name: String, _ out: String) {
    window.displayIfNeeded()
    let rep: NSBitmapImageRep
    if let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        rep = NSBitmapImageRep(cgImage: image)
    } else {
        // The harness may lack screen capture permission. Render the actual native
        // window frame (including its toolbar) directly instead.
        guard let frame = window.contentView?.superview,
              let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        rep = bitmap
    }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

func pressAccessible(_ label: String, in root: Any) -> Bool {
    guard let object = root as? NSObject else { return false }
    if object.responds(to: NSSelectorFromString("accessibilityLabel")),
       (object.value(forKey: "accessibilityLabel") as? String) == label,
       object.responds(to: NSSelectorFromString("accessibilityPerformPress")) {
        return object.perform(NSSelectorFromString("accessibilityPerformPress")) != nil || true
    }
    if object.responds(to: NSSelectorFromString("accessibilityChildren")),
       let kids = object.value(forKey: "accessibilityChildren") as? [Any] {
        for kid in kids where pressAccessible(label, in: kid) { return true }
    }
    return false
}

@MainActor
func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"],
          root.hasPrefix("/tmp/chatterbox-perf.") else { fatalError("Use the isolated runner") }
    let out = ProcessInfo.processInfo.environment["TOOLBAR_OUT"] ?? "/tmp"
    UserDefaults.standard.setVolatileDomain([
        "dotCheckIns": false, "dotWatchWaiting": false, "dotSummarizeFinished": false,
        "dotEmailWatch": false, "companionEnabled": false, "notifyNeeds": false,
        "notifyFinished": false, "keepMacAwake": false,
        "themeBackground": ProcessInfo.processInfo.environment["TOOLBAR_THEME"] ?? "standard", "settingsPage": ProcessInfo.processInfo.environment["TOOLBAR_PAGE"] ?? "models"
    ], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let chats = model.activeSessions.filter { !$0.isDot && $0.record.backend == .claude && $0.record.projectFolder != nil }
    let others = model.activeSessions.filter { !$0.isDot && $0.record.backend == .codex }
    guard chats.count >= 2, let codex = others.first else { fatalError("Need two Claude project chats and a Codex chat") }
    let pinned = ProcessInfo.processInfo.environment["TOOLBAR_FIRST"].flatMap { t in chats.first { $0.title.hasPrefix(t) } }
    let a = pinned ?? chats[0], b = chats.first { $0.projectName != a.projectName } ?? chats[1]

    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1400, height: 800),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: ContentView().environment(model))
    host.sizingOptions = [.minSize]
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    // The window installs its toolbar (and opens on Home) once it's on screen.
    try await Task.sleep(for: .milliseconds(1500))
    let openedOnHome = model.showingHome
    func show(_ s: ChatSession) async throws {
        model.showingHome = false; model.showingCommandCenter = false; model.showingSettings = false
        model.selectedID = s.id
        try await Task.sleep(for: .milliseconds(900))
    }
    func items() -> [ObjectIdentifier] { (window.toolbar?.items ?? []).map(ObjectIdentifier.init) }

    var failures = 0
    func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }
    func item(_ id: String) -> NSToolbarItem? { window.toolbar?.items.first { $0.itemIdentifier.rawValue == "chatterbox.\(id)" } }
    func hidden(_ id: String) -> Bool { if #available(macOS 15.0, *) { return item(id)?.isHidden ?? true } else { return item(id)?.view?.isHidden ?? true } }

    try await show(a)
    check(WindowToolbar.made.count == 1, "one toolbar for the window (\(WindowToolbar.made.map(\.debugState)))")
    let first = items()
    let titleWidth = item("title")?.view?.frame.width ?? 0
    // AppKit adds four points of field padding to the constrained 200-point label.
    check((200...205).contains(titleWidth), "fixed title width reserves navigation space (\(titleWidth))")
    func checkGlobalBar(_ page: String) {
        check(["views", "usage", "terminal", "finished", "settings", "newChat"].allSatisfy { !hidden($0) }, "same global controls on \(page)")
        check(abs((item("title")?.view?.frame.width ?? 0) - titleWidth) < 1, "title space unchanged on \(page)")
    }
    check(first.count >= 10, "toolbar has its items (\(first.count)) for \(a.projectName)")
    check(window.title == a.title, "window title is the chat's (\(window.title))")
    let order = (window.toolbar?.items ?? []).map { $0.itemIdentifier.rawValue.replacingOccurrences(of: "chatterbox.", with: "") }
    check(order.prefix(2) == ["title", "views"] && order.suffix(6) == ["usage", "terminal", "finished", "NSToolbarSpaceItem", "settings", "newChat"]
            && order.contains("newChat") && !order.contains("images") && !order.contains("remote"),
          "order: title, views; session info with library; usage and terminal; Settings then New Chat (\(order))")
    save(window, "1-\(a.projectName)", out)
    let baseline = Attention.shared.viewCounts(in: model)
    func fixture(_ title: String, project: Bool = false, studio: Bool = false, pending: Bool = false) -> ChatSession {
        var record = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
        record.title = title
        if project { record.projectFolder = root + "/badge-project" }
        if studio { record.studioID = UUID() }
        if pending { record.items = [DisplayItem(kind: .questions, text: "Choose a layout", approvalState: .pending), DisplayItem(kind: .approval, text: "Approve", approvalState: .pending)] }
        return model.insertSession(record)
    }
    let badgeProject = fixture("Badge project", project: true, pending: true)
    let badgeStudio = fixture("Badge studio", studio: true, pending: true)
    let badgeChat = fixture("Badge chat", pending: true)
    model.showingSettings = true
    badgeStudio.isRunning = true; Attention.shared.update(badgeStudio, model: model)
    badgeStudio.isRunning = false; Attention.shared.update(badgeStudio, model: model)
    let counts = Attention.shared.viewCounts(in: model)
    check(counts.projects == baseline.projects + 1 && counts.studios == baseline.studios + 1 && counts.chats == baseline.chats + 1, "view counts classify sessions and deduplicate pending requests plus unread reply")
    Attention.shared.markSeen(badgeStudio.id)
    check(Attention.shared.viewCounts(in: model) == counts, "seeing a finished Studio reply does not clear its pending requests")
    let finishedChat = fixture("Finished badge chat")
    finishedChat.isRunning = true; Attention.shared.update(finishedChat, model: model)
    finishedChat.isRunning = false; Attention.shared.update(finishedChat, model: model)
    check(Attention.shared.viewCounts(in: model).chats == counts.chats + 1, "unseen finished chat adds a view count")
    Attention.shared.markSeen(finishedChat.id)
    check(Attention.shared.viewCounts(in: model) == counts, "opening completion clears its view count")
    try await Task.sleep(for: .milliseconds(600))
    if let group = item("views") as? NSToolbarItemGroup {
        check(group.subitems[0].toolTip?.contains("sessions need you") == true && group.subitems[1].toolTip?.contains("sessions need you") == true && group.subitems[4].toolTip?.contains("sessions need you") == true, "all three view buttons expose waiting counts")
    }
    save(window, "11-view-badges", out)
    for session in [badgeProject, badgeStudio, badgeChat, finishedChat] { session.record.archivedAt = Date() }
    check(Attention.shared.viewCounts(in: model) == baseline, "archived sessions do not leave navigation badges")
    model.showingSettings = false
    try await show(b)
    check(items() == first, "same toolbar items after switching to \(b.projectName)")
    check(window.title == b.title, "title follows the switch")
    save(window, "2-\(b.projectName)", out)
    try await show(codex)
    check(items() == first, "same toolbar items for a Codex chat")
    save(window, "3-codex", out)
    try await show(a)
    check(items() == first, "same toolbar items after four switches")
    // The terminal button acts on the chat now showing.
    if let terminal = item("terminal"), let action = terminal.action { NSApp.sendAction(action, to: terminal.target, from: terminal) }
    try await Task.sleep(for: .milliseconds(700))
    save(window, "4-terminal-open", out)
    let before = WindowToolbar.reinstalls
    model.showingSettings = true
    var last = CFAbsoluteTimeGetCurrent(), worst = 0.0
    for _ in 0..<150 { try await Task.sleep(for: .milliseconds(20)); let t = CFAbsoluteTimeGetCurrent(); worst = max(worst, t - last); last = t }
    print("DIAG settings 3s: reinstalls \(WindowToolbar.reinstalls - before), worst main-thread gap \(Int(worst * 1000)) ms")
    check(WindowToolbar.reinstalls - before < 5, "Settings doesn't make the toolbar fight SwiftUI")
    check(window.title == "Settings", "title reads Settings on the Settings page")
    check(!hidden("terminal") && item("terminal")?.isEnabled == false, "Settings retains disabled Terminal")
    checkGlobalBar("Settings")
    save(window, "5-settings", out)
    model.showingSettings = false
    try await Task.sleep(for: .milliseconds(1500))
    check(items() == first && !hidden("terminal"), "chat items return, same items, after Settings")
    // Home and back.
    model.showingHome = true
    try await Task.sleep(for: .milliseconds(800))
    check(!hidden("terminal") && item("terminal")?.isEnabled == false && window.title == "Studios", "Studios retains disabled Terminal and uses its own title")
    checkGlobalBar("Studios")
    save(window, "6-home", out)
    model.showingHome = false
    try await Task.sleep(for: .milliseconds(1200))
    check(!hidden("terminal") && window.title == a.title && items() == first, "back from Home: chat items, title and same items")
    model.showingHome = true
    if let group = item("views") as? NSToolbarItemGroup, let action = group.action {
        check(group.subitems.count == 5, "five navigation views share the group")
        group.selectedIndex = 3
        NSApp.sendAction(action, to: group.target, from: group)
        check(model.showingAutomations, "Automations opens from toolbar")
        try await Task.sleep(for: .milliseconds(600))
        checkGlobalBar("Automations")
        check(item("terminal")?.isEnabled == false, "Automations Terminal is disabled")
        save(window, "7-automations", out)
        let count = model.sessions.count
        group.selectedIndex = 4
        NSApp.sendAction(action, to: group.target, from: group)
        try await Task.sleep(for: .milliseconds(500))
        checkGlobalBar("Chats")
        check(model.showingChatsSidebar && !model.showingAutomations && model.sessions.count == count, "Chats navigation shows standalone sidebar without creating a session")
        if let plus = item("newChat"), let action = plus.action {
            NSApp.sendAction(action, to: plus.target, from: plus)
            try await Task.sleep(for: .milliseconds(800))
            check(model.showingChatsSidebar && model.selected?.record.projectFolder == nil && model.selected?.items.isEmpty == true, "trailing + opens a standalone chat")
            check(group.selectedIndex == 4, "New Chat keeps Chats navigation selected")
        } else { check(false, "New Chat + has an action") }
        group.selectedIndex = 0
        NSApp.sendAction(group.action!, to: group.target, from: group)
        check(!model.showingChatsSidebar, "folder navigation returns to Projects")
        checkGlobalBar("Projects")
        group.selectedIndex = 2
        NSApp.sendAction(group.action!, to: group.target, from: group)
        try await Task.sleep(for: .milliseconds(800))
        checkGlobalBar("Command Center")
        check(item("terminal")?.isEnabled == false, "Command Center Terminal is disabled")
        save(window, "10-command-center", out)
        group.selectedIndex = 0
        NSApp.sendAction(group.action!, to: group.target, from: group)
    } else { check(false, "view group has a working action") }
    // Exercise the same ContentView sidebar entry point in both navigation pages.
    window.contentView = nil
    window.orderOut(nil)
    try await Task.sleep(for:.milliseconds(300))
    setenv("CHATTERBOX_TEST_SIDEBAR_ONLY", "520", 1)
    AppPreferences.defaults.set(false,forKey:"sidebarProjectsCollapsed")
    AppPreferences.defaults.set(false,forKey:"sidebarChatsCollapsed")
    AppPreferences.defaults.set(true,forKey:"macProjectsSidebarCards")
    AppPreferences.defaults.set("wordpress",forKey:"sidebarTagFilter")
    let sideWindow = NSWindow(contentRect:NSRect(x:60,y:80,width:520,height:900),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    sideWindow.appearance=NSAppearance(named:.darkAqua)
    sideWindow.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
    sideWindow.orderFrontRegardless()
    model.showingChatsSidebar = true
    MacHomeDebug.cards=[:]
    try await Task.sleep(for:.seconds(1))
    // SwiftUI does not expose this offscreen sidebar through the harness AX tree.
    // Inspect the native captures for section and filter parity instead.
    print("RENDER Chats sidebar with project tag filter: inspect 8-chats-sidebar.png")
    save(sideWindow,"8-chats-sidebar",out)
    AppPreferences.defaults.set("",forKey:"sidebarTagFilter")
    model.showingChatsSidebar = false
    MacHomeDebug.cards=[:]
    try await Task.sleep(for:.seconds(1))
    print("RENDER Projects sidebar: inspect 9-projects-sidebar.png")
    save(sideWindow,"9-projects-sidebar",out)
    unsetenv("CHATTERBOX_TEST_SIDEBAR_ONLY")
    print(failures == 0 ? "RESULT all passed" : "RESULT \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

Task { @MainActor in
    do { try await run() } catch { print("error", error); exit(1) }
}
app.run()

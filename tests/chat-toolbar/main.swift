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
    guard let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
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
    check(first.count >= 11, "toolbar has its items (\(first.count)) for \(a.projectName)")
    check(window.title == a.title, "window title is the chat's (\(window.title))")
    let order = (window.toolbar?.items ?? []).map { $0.itemIdentifier.rawValue.replacingOccurrences(of: "chatterbox.", with: "") }
    check(order.prefix(3) == ["title", "views", "newChat"] && order.suffix(4) == ["usage", "terminal", "NSToolbarSpaceItem", "settings"]
            && !order.contains("images") && !order.contains("remote"),
          "order: title, then the views group followed by a separate New Chat button; session info with the library; usage and terminal; Settings last (\(order))")
    save(window, "1-\(a.projectName)", out)
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
    check(hidden("terminal"), "chat items hide on the Settings page")
    save(window, "5-settings", out)
    model.showingSettings = false
    try await Task.sleep(for: .milliseconds(1500))
    check(items() == first && !hidden("terminal"), "chat items return, same items, after Settings")
    // Home and back.
    model.showingHome = true
    try await Task.sleep(for: .milliseconds(800))
    check(hidden("terminal") && window.title == "Chatterbox", "Home hides the chat's items")
    save(window, "6-home", out)
    model.showingHome = false
    try await Task.sleep(for: .milliseconds(1200))
    check(!hidden("terminal") && window.title == a.title && items() == first, "back from Home: chat items, title and same items")
    model.showingHome = true
    if let plus = item("newChat"), let action = plus.action {
        NSApp.sendAction(action, to: plus.target, from: plus)
        try await Task.sleep(for: .milliseconds(800))
        check(!model.showingHome && !model.showingCommandCenter && !model.showingSettings && model.selected?.items.isEmpty == true, "standalone plus opens an empty chat from Studios")
    } else { check(false, "standalone plus has a working action") }
    print(failures == 0 ? "RESULT all passed" : "RESULT \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

Task { @MainActor in
    do { try await run() } catch { print("error", error); exit(1) }
}
app.run()

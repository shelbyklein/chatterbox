import AppKit
import SwiftUI

// Run through scripts/test-chat-find.sh: copies of your chats, nothing resumed.
// Presses ⌘F in a long chat, types a word from an old message, presses Return, and captures.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)

@MainActor func key(_ window: NSWindow, _ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        if type == .keyDown, !flags.isEmpty, window.performKeyEquivalent(with: e) { continue }
        NSApp.sendEvent(e)
    }
}

@MainActor func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], root.hasPrefix("/tmp/chatterbox-perf.") else { fatalError("isolated runner") }
    let out = ProcessInfo.processInfo.environment["FIND_OUT"]!
    UserDefaults.standard.setVolatileDomain(["dotCheckIns": false, "dotWatchWaiting": false, "dotEmailWatch": false, "companionEnabled": false], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let chat = model.activeSessions.filter { !$0.isDot }.max { $0.items.count < $1.items.count }!
    // A word that appears in exactly one early user message.
    func words(_ text: String) -> [String] { text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) }
    var counts: [String: Int] = [:]
    for item in chat.items { for w in Set(words(item.text)) { counts[w, default: 0] += 1 } }
    var picked: String?
    for item in chat.items.prefix(chat.items.count / 3) where item.kind == .user {
        if let w = words(item.text).first(where: { $0.count >= 7 && counts[$0] == 1 }) { picked = w; break }
    }
    guard let word = picked else { fatalError("no unique word") }
    let target = chat.items.firstIndex { $0.text.lowercased().contains(word) }!
    print("chat \(chat.items.count) items; searching \u{201C}\(word)\u{201D}, at item \(target)")
    let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1300, height: 860), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: ContentView().environment(model))
    window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    try await Task.sleep(for: .seconds(2))
    model.showingHome = false; model.selectedID = chat.id
    try await Task.sleep(for: .seconds(2))
    key(window, "f", 3, .command)
    try await Task.sleep(for: .milliseconds(600))
    if let editor = window.firstResponder as? NSTextView { editor.insertText(word, replacementRange: editor.selectedRange()) }
    else { print("FAIL find field not focused (\(String(describing: window.firstResponder)))") }
    try await Task.sleep(for: .seconds(2))
    window.displayIfNeeded()
    if let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    }
    exit(0)
}
Task { @MainActor in do { try await run() } catch { print("error", error); exit(1) } }
app.run()

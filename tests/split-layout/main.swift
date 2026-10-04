import AppKit
import SwiftUI

// Run through scripts/test-split-layout.sh. Opens one saved chat (a copy) with the sidebar and
// inspector shown, resizes the window through several widths, and prints the split view's
// column frames, the inspector's limits, the window's minimum, and whether anything overflows
// the window. Captures each width to CHATTERBOX_DATA_DIR/<chat>-<width>.png.
//   SPLIT_WIDTHS=1600,900   the widths to try (default 1600,1290,1100,900,800)
//   SPLIT_OPEN_LATE=1       open a project chat's Issues panel after the first width, not before
//   SPLIT_INTRINSIC=1       also list every view with a wide intrinsic or fitting size
let app = NSApplication.shared
app.setActivationPolicy(.regular)

@MainActor
func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"],
          root.hasPrefix("/tmp/chatterbox-split.") else { fatalError("Use the isolated runner") }
    let env = ProcessInfo.processInfo.environment
    let chatID = UUID(uuidString: env["SPLIT_CHAT"] ?? "")!
    let widths = (env["SPLIT_WIDTHS"] ?? "1600,1290,1100,900,800").split(separator: ",").compactMap { Double($0) }
    UserDefaults.standard.setVolatileDomain([
        "dotCheckIns": false, "dotWatchWaiting": false, "dotSummarizeFinished": false, "dotEmailWatch": false,
        "companionEnabled": false, "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false,
        "golemPanelOpen": true
    ], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    guard let session = model.sessions.first(where: { $0.id == chatID }) else { fatalError("Chat \(chatID) not found") }
    model.selectedID = session.id
    let window = NSWindow(contentRect: NSRect(x: 40, y: 80, width: widths[0], height: 820),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: ContentView().environment(model))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    try await Task.sleep(for: .seconds(3))

    // Project chats: open the Issues panel with its own shortcut (⌘⇧I).
    func openIssues() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: "I",
                                    charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34)!
        app.sendEvent(down)
    }
    let openLate = env["SPLIT_OPEN_LATE"] != nil
    if !session.isDot, !openLate {
        openIssues()
        try await Task.sleep(for: .seconds(2))
    }

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func name(_ v: NSView) -> String { String(describing: type(of: v)) }

    func report(_ label: String) {
        let content = window.contentView!
        let width = content.bounds.width
        print("== \(session.title) \(label): window content \(content.bounds.size) minSize \(window.contentMinSize) single column allocator ==")
        let all = descendants(content)
        for split in all.compactMap({ $0 as? NSSplitView }) {
            let inWindow = split.convert(split.bounds, to: nil)
            print(" NSSplitView frame \(split.frame.integral) inWindow \(inWindow.integral)")
            for (i, v) in split.arrangedSubviews.enumerated() {
                print("   column\(i) x \(v.frame.minX) width \(v.frame.width) fitting \(v.fittingSize.width)")
            }
            if let controller = split.delegate as? NSSplitViewController {
                for (i, item) in controller.splitViewItems.enumerated() {
                    let v = item.viewController.view
                    print("   item\(i) \(name(v).prefix(60)) width \(v.frame.width) collapsed=\(item.isCollapsed) min=\(item.minimumThickness) max=\(item.maximumThickness) prio=\(item.holdingPriority.rawValue)")
                }
            }
            if inWindow.maxX > width + 0.5 || inWindow.minX < -0.5 {
                print("   OVERFLOW: split spans \(inWindow.minX)...\(inWindow.maxX) in a \(width) window")
            }
        }
        if env["SPLIT_INTRINSIC"] != nil {
            for v in all where v.intrinsicContentSize.width > 150 || v.fittingSize.width > 150 {
                print("   intrinsic \(name(v)) intrinsic \(v.intrinsicContentSize) fitting \(v.fittingSize) frame \(v.frame.integral)")
            }
        }
        capture(window, to: URL(fileURLWithPath: root).appendingPathComponent("\(session.isDot ? "golem" : "project")-\(label).png"))
    }

    for (n, width) in widths.enumerated() {
        window.setContentSize(NSSize(width: width, height: 820))
        try await Task.sleep(for: .seconds(2))
        report("\(Int(width))")
        if n == 0, openLate, !session.isDot {
            openIssues()
            try await Task.sleep(for: .seconds(2))
            report("\(Int(width))-then-issues")
        }
    }
    exit(0)
}

@MainActor
func capture(_ window: NSWindow, to url: URL) {
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
    let fn = unsafeBitCast(sym, to: Fn.self)
    guard let image = fn(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else { return }
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    print("   capture \(url.path) \(image.width)x\(image.height)")
}

Task { @MainActor in
    do { try await run() } catch { fatalError("\(error)") }
}
app.run()

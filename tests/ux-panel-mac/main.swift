@testable import Chatterbox
import AppKit
import SwiftUI
// UX panel tour (design/ux-panel/screens), Mac: not a regression check. The main window with
// projects, a Studio and chats down the left and a working session open (tool rows, a plan, a
// reply with a heading, list, code and a table), dark and light; a session with an approval
// waiting; and Settings. Stand-in sessions only; nothing runs. Evidence: ux-*.png in the fixture.
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Thread.detachNewThread { Thread.sleep(forTimeInterval: 180); print("FAIL timed out"); exit(2) }
/// The window as composited on screen, title bar and toolbar included (its own window only, as
/// tests/chat-rendering does). Settings' Form pages don't draw through cacheDisplay.
@MainActor func composited(_ window: NSWindow, _ name: String, _ root: URL) throws {
    window.displayIfNeeded()
    typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
    guard let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { fatalError("Couldn't capture \(name)") }
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
    print("wrote \(name).png")
}
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-ux-panel-mac."))
    UserDefaults.standard.setVolatileDomain(["companionEnabled": false, "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false,
                                             "sidebarProjectsCollapsed": false, "sidebarStudiosCollapsed": false, "sidebarChatsCollapsed": false,
                                             "mainSidebarWidth": 270.0], forName: UserDefaults.argumentDomain)
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    let model = AppModel()
    func project(_ title: String, _ backend: Backend, _ items: [DisplayItem]) -> ChatSession {
        var record = ConversationRecord(model: backend == .claude ? "opus" : "gpt-6.1-sol", effort: "medium", personality: .pragmatic)
        record.title = title; record.projectNickname = title; record.projectFolder = root.appendingPathComponent(title).path
        record.activeBackend = backend; record.items = items
        return model.insertSession(record)
    }
    func tool(_ text: String, _ name: String, _ state: DisplayItem.ToolState = .done) -> DisplayItem {
        var item = DisplayItem(kind: .tool, text: text); item.toolState = state; item.tool = name; return item
    }
    var plan = DisplayItem(kind: .plan)
    plan.planSteps = [PlanStep(step: "Hyphenation patterns", status: "completed"), PlanStep(step: "Kerning pairs from the font", status: "completed"),
                      PlanStep(step: "Knuth-Plass line breaking", status: "completed"), PlanStep(step: "Widow and orphan control", status: "pending")]
    var final = DisplayItem(kind: .assistant, text: """
    ## Phase 3: typography engine

    The line breaker now uses **Knuth-Plass** with hyphenation points, so paragraphs set evenly instead of filling line by line.

    - Hyphenation: Liang patterns for English, cached per word
    - Kerning: pairs read from the font's `GPOS` table
    - Line breaking: total fit, with a penalty for two hyphens in a row

    ```swift
    let breaker = LineBreaker(width: 420, tolerance: 2.0)
    let lines = breaker.lines(for: paragraph, hyphenator: .english)
    ```

    | Sample | Before | After |
    |---|---|---|
    | Body copy | 31 rivers | 4 rivers |
    | Narrow column | 12 overfull | 0 overfull |

    **Next:** widow and orphan control. Check the specimen PDF before I start it.
    """, phase: .final)
    final.workedSeconds = 754
    let galley = project("Galley", .claude, [
        DisplayItem(kind: .user, text: "Phase 3: finish the typography engine. Hyphenation, kerning pairs and the line breaker, then run the tests."),
        DisplayItem(kind: .thought, text: "The line breaker still fills greedily. Knuth-Plass needs the hyphenation points first, so do those, then kerning, then the breaker."),
        tool("Read Sources/Typography/LineBreaker.swift", "Read"),
        tool("Read Sources/Typography/Hyphenator.swift", "Read"),
        tool("Edited Sources/Typography/LineBreaker.swift", "Edit"),
        plan,
        tool("swift test --filter TypographyTests", "Bash", .failed),
        DisplayItem(kind: .assistant, text: "One test failed: a soft hyphen at the end of a line was kept. Fixing that now.", phase: .commentary),
        tool("swift test --filter TypographyTests", "Bash"),
        final])
    var approval = DisplayItem(kind: .approval, text: "Run wrangler deploy to publish the new cache rules?")
    approval.detail = "wrangler deploy --env production"; approval.approvalState = .pending
    var sdhqReply = DisplayItem(kind: .assistant, text: "The shop pages were cached for 4 hours, so price changes showed late. The new rules cache product pages for 10 minutes and bypass the cache for the cart and checkout.", phase: .final)
    sdhqReply.workedSeconds = 96
    let sdhq = project("SDHQ", .claude, [
        DisplayItem(kind: .user, text: "Tighten the cache rules for the shop pages and publish them."),
        tool("Read wrangler.toml", "Read"), tool("curl -sI https://sdhq.example/shop", "Bash"), sdhqReply, approval])
    _ = project("Chatterbox", .codex, [DisplayItem(kind: .assistant, text: "Shipped the Next Steps plugin and the new message box.", phase: .final)])
    _ = project("PlayCase Magnets", .claude, [DisplayItem(kind: .assistant, text: "Finished the product photos for the store.", phase: .final)])
    _ = project("Tracker Trapper", .codex, [DisplayItem(kind: .assistant, text: "Checked the menu-bar progress after the update.", phase: .final)])
    let usa = model.newStudio(named: "USA Archery")!
    // A Studio session with a render in it: a cover proof (a gradient with a target).
    let cover = root.appendingPathComponent("cover-proof.png")
    do {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: NSColor(hue: 0.6, saturation: 0.7, brightness: 0.85, alpha: 1), ending: NSColor(hue: 0.75, saturation: 0.8, brightness: 0.3, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1200), angle: -35)
        for ring in 0..<5 {
            let inset = CGFloat(ring) * 90
            NSColor(white: ring.isMultiple(of: 2) ? 1 : 0.1, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 350 + inset, y: 150 + inset, width: 900 - inset * 2, height: 900 - inset * 2)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: cover)
    }
    let magazine = model.chats(in: usa).first!
    magazine.setTitle("2027 Indoor Magazine")
    magazine.record.items = [
        DisplayItem(kind: .user, text: "Cover options for the 2027 Indoor magazine: the new target art, navy and red."),
        tool("Ran python render_cover.py --variant target", "Bash"),
        DisplayItem(kind: .image, text: "", attachments: [Attachment(name: "cover-proof.png", path: cover.path, mediaType: "image/png", kind: .image)]),
        DisplayItem(kind: .assistant, text: "Cover updated with the new target art. The masthead stays navy; the red is only in the rings. Review the proof before I lay out the inside pages.", phase: .final)]
    model.newChat(in: usa).setTitle("National Event Ribbons")
    model.newChat(backend: .codex).setTitle("Banner ideas")
    galley.isRunning = true

    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    func show(_ session: ChatSession, dark: Bool) async throws {
        model.selectedID = session.id
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: ContentView().environment(model).environment(\.colorScheme, dark ? .dark : .light))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(2))
    }
    try await show(galley, dark: true); try composited(window, "ux-mac-conversation", root)
    try await show(galley, dark: false); try composited(window, "ux-mac-conversation-light", root)
    try await show(sdhq, dark: true); try composited(window, "ux-mac-approval", root)
    try await show(magazine, dark: true); try composited(window, "ux-mac-studio-session", root)
    // Settings: its pages down the left.
    // (A Form's scroll view draws its backdrop from the app's appearance, not the window's.)
    for (page, dark) in [("notifications", true), ("models", true), ("models", false)] {
        UserDefaults.standard.set(page, forKey: "settingsPage")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let settings = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        settings.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        settings.contentView = NSHostingView(rootView: SettingsView().environment(model).environment(\.colorScheme, dark ? .dark : .light))
        settings.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1.5))
        try composited(settings, "ux-mac-settings-\(page)\(dark ? "" : "-light")", root)
        settings.orderOut(nil)
    }
    app.appearance = nil
    UserDefaults.standard.removeObject(forKey: "settingsPage")
    print("PASS UX panel Mac tour. Evidence: \(root.path)")
}
Task { @MainActor in do { try await run(); exit(0) } catch { print(error); exit(1) } }
app.run()

import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision
@testable import ChatterboxTestEngine

let app = NSApplication.shared
app.setActivationPolicy(.regular)
setbuf(stdout, nil)

@MainActor
func run() async throws {
    guard #available(macOS 14.4, *), let path = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"],
          path.hasPrefix("/tmp/chatterbox-mini.") else { fatalError("Use scripts/test-golem-mini.sh") }
    let root = URL(fileURLWithPath: path)
    UserDefaults.standard.setVolatileDomain([
        "themeBackground": "black", "dotCheckIns": false, "dotWatchWaiting": false,
        "dotSummarizeFinished": false, "dotEmailWatch": false, "companionEnabled": false,
        "keepMacAwake": false, "notifyNeeds": false, "notifyFinished": false,
        "readerGroupSteps": true, GolemMiniWindow.visibleKey: false
    ], forName: UserDefaults.argumentDomain)
    // The standalone executable has its own preference domain; never use the live app's.
    precondition(Bundle.main.bundleIdentifier == nil)
    for key in [GolemMiniWindow.expandedFrameKey, GolemMiniWindow.avatarFrameKey, GolemMiniWindow.collapsedKey] {
        UserDefaults.standard.removeObject(forKey: key)
    }
    if let assets = ProcessInfo.processInfo.environment["CHATTERBOX_TEST_AVATAR_DIR"] {
        let folder = root.appendingPathComponent("Dot/Avatar")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["head.png", "idle.mov", "thinking.mov"] {
            let file = URL(fileURLWithPath: assets).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(name)) }
        }
    }
    let model = AppModel()
    let selection = model.selectedID
    let dot = model.ensureDot()
    dot.setTitle("Golem")
    dot.appendItem(DisplayItem(kind: .user, text: "What needs my attention?"))
    dot.appendItem(DisplayItem(kind: .assistant, text: "Galley is ready for review. Open its chat to check the latest preview.", phase: .final))
    dot.draft = "Keep this draft"
    let main = NSWindow(contentRect: NSRect(x: 60, y: 100, width: 780, height: 560),
                        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    main.title = "Other work — regression fixture"
    main.contentView = NSHostingView(rootView: Text("Your other work stays here.").font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.2)))
    main.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    model.mainChatWindow = main
    var revealedMain = false
    model.revealMainChatWindow = { revealedMain = true }
    model.showingDot = true
    let mini = model.dotMiniWindow!
    let panel = mini.panel!
    panel.setFrame(NSRect(x: 480, y: 140, width: 400, height: 560), display: true)
    try await Task.sleep(for: .seconds(2))
    panel.makeKeyAndOrderFront(nil)
    precondition(model.selectedID == selection, "Mini changed the selected project")
    precondition(panel.level == .floating && !panel.hidesOnDeactivate && panel.styleMask.contains(.nonactivatingPanel))
    precondition(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
    precondition(panel.canBecomeKey && !panel.canBecomeMain && mini.isReading)
    precondition(Attention.shared.isWatching(dot))
    if let selected = model.selected, !selected.isDot { precondition(!Attention.shared.isWatching(selected)) }
    print("PASS floating policy, independent selection and focused unread behavior")

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func typeDraft(_ text: String, in panel: NSPanel) async throws {
        let field = descendants(panel.contentView!).compactMap { $0 as? NSTextField }.first { String(describing: type(of: $0)) == "AppKitTextField" }!
        panel.makeFirstResponder(field)
        let editor = panel.fieldEditor(true, for: field) as! NSTextView
        editor.selectAll(nil); editor.insertText(text, replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        precondition(dot.draft == text, "Draft did not reach the shared session")
    }
    @discardableResult
    func capture(_ name: String, panel: NSWindow) async throws -> String {
        let window = try await SCShareableContent.currentProcess.windows.first { $0.windowID == CGWindowID(panel.windowNumber) }!
        let config = SCStreamConfiguration(); config.width = Int(panel.frame.width) * 2; config.height = Int(panel.frame.height) * 2
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
        let recognize = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: image).perform([recognize])
        return (recognize.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
    }
    func mouse(_ type: NSEvent.EventType, at point: NSPoint, panel: NSWindow) async throws {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        app.postEvent(event, atStart: false)
        try await Task.sleep(for: .milliseconds(100))
    }
    func drag(_ region: MiniDragRegion.DragView, panel: NSWindow) async throws {
        let before = panel.frame.origin
        let point = region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil)
        try await mouse(.leftMouseDown, at: point, panel: panel)
        try await mouse(.leftMouseDragged, at: NSPoint(x: point.x + 70, y: point.y + 20), panel: panel)
        try await mouse(.leftMouseUp, at: point, panel: panel)
        precondition(abs(panel.frame.minX - before.x - 70) < 1 && abs(panel.frame.minY - before.y - 20) < 1, "Native drag did not move the window")
    }
    try await typeDraft("A draft that survives minimizing", in: panel)
    let header = descendants(panel.contentView!).compactMap { $0 as? MiniDragRegion.DragView }.first!
    try await drag(header, panel: panel)
    try await capture("expanded", panel: panel)
    print("PASS header drag and typing")

    // Click the actual minimize button in the header, rather than calling its closure.
    try await mouse(.leftMouseDown, at: NSPoint(x: panel.frame.width - 83, y: panel.frame.height - 18), panel: panel)
    try await mouse(.leftMouseUp, at: NSPoint(x: panel.frame.width - 83, y: panel.frame.height - 18), panel: panel)
    precondition(mini.collapsed && panel.frame.size == NSSize(width: 96, height: 96), "Minimize button did not make the avatar")
    precondition(!mini.isReading && !Attention.shared.isWatching(dot))
    dot.appendItem(DisplayItem(kind: .user, text: "Check for updates"))
    dot.appendItem(DisplayItem(kind: .assistant, text: "One new update is ready.", phase: .final))
    try await Task.sleep(for: .milliseconds(300))
    precondition(Attention.shared.dotUnreadCount(dot) == 1, "Collapsed avatar marked an unread reply seen")
    let avatar = descendants(panel.contentView!).compactMap { $0 as? MiniDragRegion.DragView }.first!
    try await drag(avatar, panel: panel)
    precondition(mini.collapsed, "Dragging the avatar also opened it")
    try await capture("avatar", panel: panel)
    print("PASS minimize, unread badge and avatar drag")

    main.makeKeyAndOrderFront(nil)
    app.deactivate()
    try await Task.sleep(for: .milliseconds(200))
    precondition(panel.isVisible && !mini.isReading, "Mini hid or marked itself read after deactivation")
    // Native first click reopens the nonactivating panel.
    try await mouse(.leftMouseDown, at: NSPoint(x: 48, y: 48), panel: panel)
    try await mouse(.leftMouseUp, at: NSPoint(x: 48, y: 48), panel: panel)
    precondition(!mini.collapsed && mini.isReading)
    precondition(Attention.shared.dotUnreadCount(dot) == 0)
    precondition(dot.draft == "A draft that survives minimizing")
    try await typeDraft("Still the same draft", in: panel)
    print("PASS inactive visibility, first click, unread clearing and preserved draft")

    let expected = panel.frame
    model.showingDot = false
    precondition(!panel.isVisible && panel.contentView == nil)
    model.showingDot = true
    let reopened = mini.panel!
    try await Task.sleep(for: .milliseconds(200))
    precondition(reopened.frame == expected, "Panel position was not restored")
    precondition(dot.draft == "Still the same draft")
    precondition(model.sessions.filter(\.isDot).count == 1)
    let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
    precondition(screen.contains(GolemMiniWindow.clamped(NSRect(x: 4000, y: -4000, width: 400, height: 560), to: [screen])))
    precondition(screen.contains(GolemMiniWindow.clamped(NSRect(x: -30, y: -30, width: 2400, height: 1600), to: [screen])))
    mini.openFullChat()
    try await Task.sleep(for: .milliseconds(300))
    precondition(!model.showingDot && model.selectedID == dot.id && main.isKeyWindow && !reopened.isVisible,
                 "Return to main: shown=\(model.showingDot), selected=\(model.selectedID == dot.id), key=\(main.isKeyWindow), visibleMini=\(reopened.isVisible)")
    precondition(!revealedMain, "Created a second main window instead of revealing the existing one")
    model.mainChatWindow = nil
    mini.revealMainWindow()
    precondition(revealedMain, "Did not reopen the main scene after closing it")
    model.mainChatWindow = main
    print("PASS saved position, disconnected-screen clamping and return to full chat")

    // Progress narration stays readable during a turn, including across a mid-turn message.
    // Neither past commentary nor thought/tool detail should spill out of collapsed groups.
    let olderNote = DisplayItem(kind: .assistant, text: "Earlier narration", phase: .commentary)
    let firstNote = DisplayItem(kind: .assistant, text: "I'll give Golem a small draggable window.", phase: .commentary)
    let secondNote = DisplayItem(kind: .assistant, text: "I'm using the development workflow to verify it.", phase: .commentary)
    let fixture = [
        DisplayItem(kind: .user, text: "Make Golem draggable"), firstNote,
        DisplayItem(kind: .thought, text: "Thought content stays folded"),
        DisplayItem(kind: .tool, text: "Reading window code", toolState: .done),
        DisplayItem(kind: .user, text: "Show me progress too", steered: true), secondNote,
        DisplayItem(kind: .tool, text: "Checking panel behavior", toolState: .done),
        DisplayItem(kind: .tool, text: "Capturing the window", toolState: .running)
    ]
    let regular = model.newChat(backend: .claude)
    regular.record.items = [olderNote, DisplayItem(kind: .assistant, text: "Earlier answer")] + fixture
    regular.isRunning = true
    precondition(regular.liveCommentaryIDs == Set([firstNote.id, secondNote.id]))
    for session in [regular, dot] {
        session.record.items = fixture
        session.isRunning = true
        let target: NSWindow
        if session.isDot {
            model.showingDot = true
            target = mini.panel!
        } else {
            main.contentView = NSHostingView(rootView: ChatView(session: session).environment(model))
            main.makeKeyAndOrderFront(nil)
            target = main
        }
        try await Task.sleep(for: .seconds(2))
        let name = session.isDot ? "golem" : "regular"
        let live = try await capture(name + "-progress", panel: target)
        precondition(live.contains("small draggable window") && live.contains("development workflow"), "Live notes missing in \(name): \(live)")
        precondition(!live.contains("thought content stays folded"), "Thought leaked from its group")
        session.appendItem(DisplayItem(kind: .assistant, text: "The mini window is ready for review.", phase: .final))
        session.isRunning = false
        precondition(session.liveCommentaryIDs.isEmpty)
        try await Task.sleep(for: .seconds(1))
        let finished = try await capture(name + "-finished", panel: target)
        precondition(finished.contains("ready for review") && !finished.contains("development workflow") && !finished.contains("small draggable window"), "Finished notes did not fold in \(name): \(finished)")
        print("PASS \(name) live progress notes, mid-turn steering and finished grouping")
    }
    mini.panel?.makeKeyAndOrderFront(nil)
    ChatCommands.shared.toggleModelPopover()
    try await Task.sleep(for: .milliseconds(400))
    let popovers = app.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    for (index, window) in app.windows.filter(\.isVisible).enumerated() {
        print("Shortcut window: \(type(of: window)), \(window.title), key=\(window.isKeyWindow)")
        try await capture("shortcut-\(index)", panel: window)
    }
    precondition(popovers.count == 1, "Model shortcut opened \(popovers.count) popovers with two chats visible")
    ChatCommands.shared.toggleModelPopover()
    try await Task.sleep(for: .milliseconds(400))
    precondition(popovers.allSatisfy { !$0.isVisible }, "Model shortcut did not close the active popover")
    print("PASS model shortcut targets only the focused chat window and toggles closed")
    model.showingDot = false
    Diagnostics.shared.stop()
}

Task { @MainActor in
    do { try await run(); exit(0) }
    catch { fputs("Mini regression failed: \(error)\n", stderr); exit(1) }
}
app.run()

@testable import Chatterbox
import AppKit
import SwiftUI
// The thread sidebar (ThreadSidebar.swift), Mac: About this thread down the right of a chat, in
// place of the old column of icon buttons. A busy front thread (work threads, outputs, a brief,
// notes, tools, a sidechat, an automation) shows every section; a plain chat shows only the ones
// with something in them; the header has Files, Terminal and Images; the toolbar has its toggle,
// which hides and shows it; a narrow window slides it over instead. Stand-in sessions only;
// nothing runs. Evidence: mac-sidebar*.png in the fixture.
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Thread.detachNewThread { Thread.sleep(forTimeInterval: 180); print("FAIL timed out"); exit(2) }
var failures = 0
func check(_ ok: Bool, _ what: String) { print((ok ? "ok   " : "FAIL ") + what); if !ok { failures += 1 } }

@MainActor func composited(_ window: NSWindow, _ name: String, _ root: URL) throws {
    window.displayIfNeeded()
    typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
    let rep: NSBitmapImageRep
    if let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        rep = NSBitmapImageRep(cgImage: image)
    } else {
        guard let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: bitmap); rep = bitmap
    }
    try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
    print("wrote \(name).png")
}

/// The probes on screen (ColumnProbe), by role, with their frames in the window.
@MainActor func probes(_ window: NSWindow) -> [String: NSRect] {
    var found: [String: NSRect] = [:]
    func walk(_ view: NSView) {
        if let probe = view as? ColumnProbe.Probe, !probe.isHiddenOrHasHiddenAncestor, probe.bounds.width > 0 {
            found[probe.role] = probe.convert(probe.bounds, to: nil)
        }
        view.subviews.forEach(walk)
    }
    if let root = window.contentView { walk(root) }
    return found
}

@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-thread-sidebar-mac."))
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    UserDefaults.standard.setVolatileDomain(["companionEnabled": false, "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false,
                                             "sidebarProjectsCollapsed": false, "sidebarChatsCollapsed": false,
                                             "mainSidebarWidth": 250.0], forName: UserDefaults.argumentDomain)
    // Every section open, so the screenshot shows them all; the sidebar shown.
    UserDefaults.standard.set("status,place,work,outputs,notes,tools,runs", forKey: "threadSidebarSections")
    UserDefaults.standard.set(true, forKey: "threadSidebarOpen")
    let model = AppModel()

    // A busy front thread in a project folder.
    let folder = root.appendingPathComponent("Galley")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    func picture(_ name: String, hue: CGFloat) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: NSColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1), ending: NSColor(hue: hue + 0.1, saturation: 0.8, brightness: 0.35, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: 800, height: 600), angle: -35)
        NSColor(white: 1, alpha: 0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: 260, y: 160, width: 280, height: 280)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }
    let specimen = try picture("specimen-page.png", hue: 0.58)
    let proof = try picture("cover-proof.png", hue: 0.02)
    let kerning = try picture("kerning-pairs.png", hue: 0.33)
    let pdf = folder.appendingPathComponent("Specimen.pdf")
    try Data("%PDF-1.4\n%%EOF\n".utf8).write(to: pdf)
    var record = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
    record.title = "Galley"; record.projectNickname = "Galley"; record.projectFolder = folder.path
    record.activeBackend = .claude
    record.brief = "Phase 3 of the typography engine: hyphenation, kerning pairs and Knuth-Plass line breaking. Tests in TypographyTests; specimen PDF for review."
    record.items = [
        DisplayItem(kind: .user, text: "Phase 3: finish the typography engine, then show me the specimen."),
        DisplayItem(kind: .image, text: "", attachments: [Attachment(name: "kerning-pairs.png", path: kerning.path, mediaType: "image/png", kind: .image)]),
        DisplayItem(kind: .assistant, text: "The specimen is at `\(pdf.path)`, and the cover proof at `\(proof.path)`.\n\n![Specimen](\(specimen.path))\n\nPublished for review: https://snippets.shelbyklein.com/galley/specimen.html (public).", phase: .final),
        DisplayItem(kind: .assistant, text: "Here's the note for the printer:\n\n```draft\nSubject: Galley proofs for Thursday\n\nHi Dana, the specimen pages are ready for a press check.\n```", phase: .final),
    ]
    let galley = model.insertSession(record)
    galley.contextUsage[.claude] = ContextUsage(used: 86_000, window: 200_000)
    func work(_ title: String, running: Bool = false, step: String? = nil) -> ChatSession {
        var thread = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
        thread.title = title; thread.workOf = galley.id; thread.sidechatOf = galley.id; thread.sidechatFolder = folder.path
        if let step { var tool = DisplayItem(kind: .tool, text: step); tool.toolState = .running; thread.items = [tool] }
        let session = model.insertSession(thread)
        session.isRunning = running
        return session
    }
    _ = work("Widow and orphan control", running: true, step: "swift test --filter WidowTests")
    _ = work("Hyphenation dictionary for German")
    var side = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
    side.title = "Font licensing questions"; side.sidechatOf = galley.id; side.sidechatFolder = folder.path
    _ = model.insertSession(side)
    try ProjectAutomations.save([ProjectAutomation(projectFolder: folder.path, title: "Weekly test run", template: .custom, instructions: "Run the tests.")])
    let scope = PinnedNotesStore.scope(for: galley.record)
    PinnedNotesStore.shared.setDraft("Ask Dana about the paper stock before the press check.", for: scope)
    PinnedNotesStore.shared.add(for: scope)
    ThreadTools.shared.seed([.init(name: "cinema4d", kind: "server", isOn: true), .init(name: "github", kind: "server", isOn: true),
                             .init(name: "inspo", kind: "server", isOn: true), .init(name: "wordpress", kind: "server", isOn: false),
                             .init(name: "Gmail", kind: "connector", isOn: false)], for: galley)

    // A plain chat: nothing made, no folder, no tools.
    let plain = model.newChat(backend: .claude)
    plain.setTitle("Banner ideas")
    plain.record.items = [DisplayItem(kind: .user, text: "Three taglines for the spring banner?"),
                          DisplayItem(kind: .assistant, text: "1. Aim higher this spring.\n2. Every arrow counts.\n3. Find your range.", phase: .final)]
    ThreadTools.shared.seed([], for: plain)

    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1440, height: 900), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    func show(_ session: ChatSession, dark: Bool, width: CGFloat = 1440) async throws {
        model.selectedID = session.id
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: width, height: 900))
        window.contentView = NSHostingView(rootView: ContentView().environment(model).environment(\.colorScheme, dark ? .dark : .light))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(2.5))
    }

    // Busy thread: every section, the header's places, the old column gone.
    try await show(galley, dark: false)
    var seen = probes(window)
    let all = ThreadSidebarSection.allCases.map { "threadSidebar:\($0.rawValue)" }
    check(seen["threadSidebar"] != nil, "the sidebar is docked in a wide window")
    if let frame = seen["threadSidebar"] {
        check(abs(frame.width - ThreadSidebar.width) < 1 && abs(frame.maxX - window.contentLayoutRect.width) < 2,
              "it's \(ThreadSidebar.width) wide, along the right edge (\(frame))")
    }
    check(all.allSatisfy { seen[$0] != nil }, "a busy thread shows every section (\(all.filter { seen[$0] == nil }))")
    let order = all.compactMap { role in seen[role].map { (role, $0.minY) } }
    check(order.map(\.1) == order.map(\.1).sorted(by: >) || order.map(\.1) == order.map(\.1).sorted(),
          "sections run in order: Status, Where, Task & work, Outputs, Notes, Tools, Runs here")
    for button in ["files", "terminal", "images"] { check(seen["threadSidebar:header:\(button)"] != nil, "header has \(button.capitalized)") }
    check(seen["threadSidebar:workThreads"] != nil, "Task & work lists the work threads")
    check(seen["threadSidebar:start"] != nil, "Task & work has the start actions (work thread, sidequest, sidechat, PC, presets)")
    check(seen["threadSidebar:model"] != nil, "Status has the model row")
    check(seen["threadSidebar:context"] != nil, "Status shows context: the session knows it")
    let outputs = ThreadOutputs.collect(galley)
    check(outputs.filter { $0.kind == .image }.count == 3 && outputs.contains { $0.kind == .file && $0.title == "Specimen.pdf" }
            && outputs.contains { $0.kind == .link } && outputs.contains { $0.kind == .draft },
          "Outputs has its images, the PDF, the published link and the draft (\(outputs.map { "\($0.kind):\($0.title)" }))")
    check(outputs.first?.kind == .draft, "Outputs are newest first")
    let ids = (window.toolbar?.items ?? []).map(\.itemIdentifier.rawValue)
    check(ids.last == "chatterbox.threadSidebar", "the toolbar ends with About this Thread (\(ids))")
    try composited(window, "mac-sidebar", root)
    try await show(galley, dark: true); try composited(window, "mac-sidebar-dark", root)

    // A plain chat: only what it has.
    try await show(plain, dark: false)
    seen = probes(window)
    check(["status", "place", "work", "notes"].allSatisfy { seen["threadSidebar:\($0)"] != nil }, "a plain chat shows Status, Where, Task & work and Notes")
    check(["outputs", "tools", "runs"].allSatisfy { seen["threadSidebar:\($0)"] == nil }, "and hides Outputs, Tools and Runs here, which are empty")
    check(seen["threadSidebar:context"] == nil, "no context bar where the session doesn't know it")
    // Collapsed by default except Status, Task & work and Outputs.
    UserDefaults.standard.set(ThreadSidebarSection.openByDefault, forKey: "threadSidebarSections")
    try await Task.sleep(for: .seconds(0.8))
    try composited(window, "mac-sidebar-simple", root)

    // The toolbar's toggle hides it, and it stays hidden; again shows it.
    model.threadSidebarToggleRequest += 1
    try await Task.sleep(for: .seconds(1))
    check(probes(window)["threadSidebar"] == nil && UserDefaults.standard.bool(forKey: "threadSidebarOpen") == false, "About this Thread hides it, remembered")
    model.threadSidebarToggleRequest += 1
    try await Task.sleep(for: .seconds(1))
    check(probes(window)["threadSidebar"] != nil, "and shows it again")

    // Narrow: no room beside the chat, so it slides over when asked.
    try await show(galley, dark: false, width: 900)
    check(probes(window)["threadSidebar"] == nil, "a narrow window doesn't dock it")
    model.threadSidebarToggleRequest += 1
    try await Task.sleep(for: .seconds(1))
    seen = probes(window)
    check(seen["threadSidebar"] != nil, "the toggle slides it over instead")
    check(UserDefaults.standard.bool(forKey: "threadSidebarOpen"), "sliding over doesn't change the remembered choice")
    try composited(window, "mac-sidebar-narrow", root)

    app.appearance = nil
    UserDefaults.standard.removeObject(forKey: "threadSidebarSections")
    UserDefaults.standard.removeObject(forKey: "threadSidebarOpen")
    print(failures == 0 ? "PASS thread sidebar, Mac. Evidence: \(root.path)" : "FAIL \(failures) thread sidebar checks")
    exit(failures == 0 ? 0 : 1)
}
Task { @MainActor in do { try await run() } catch { print(error); exit(1) } }
app.run()

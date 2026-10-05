import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

// Run through scripts/test-chat-rendering.sh. No saved chats or agent sessions are used.
// Captures only this test process's own window, without screen-recording permission.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

@MainActor
func run() async throws {
    guard #available(macOS 14.4, *) else { fatalError("Requires macOS 14.4 or later") }
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"],
          root.hasPrefix("/tmp/chatterbox-render.") else { fatalError("Use the isolated runner") }
    UserDefaults.standard.setVolatileDomain([
        "themeBackground": "black", "dotCheckIns": false, "dotWatchWaiting": false,
        "dotSummarizeFinished": false, "dotEmailWatch": false, "companionEnabled": false,
        "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false
    ], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let first = model.newChat(backend: .claude)
    first.setTitle("Plain fixture")
    for n in 0..<160 { first.appendItem(DisplayItem(kind: .assistant, text: "Earlier reply \(n).")) }
    first.appendItem(DisplayItem(kind: .assistant, text: "Plain transcript ready"))
    let preview = model.newChat(backend: .claude)
    preview.setTitle("Preview fixture")
    for n in 0..<2 {
        let file = URL(fileURLWithPath: root).appendingPathComponent("preview-\(n).svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">
          <rect width="1440" height="900" fill="#244465"/>
          <text x="80" y="180" fill="white" font-size="64">Live SVG preview \(n)</text>
        </svg>
        """.write(to: file, atomically: true, encoding: .utf8)
        preview.appendItem(DisplayItem(kind: .image, text: file.lastPathComponent,
            attachments: [Attachment(name: file.lastPathComponent, path: file.path, mediaType: "image/svg+xml", kind: .text)]))
    }
    // Offscreen WebKit views followed by ordinary messages exercise bottom-anchored layout.
    for n in 0..<18 {
        preview.appendItem(DisplayItem(kind: .assistant, text: "Reply \(n).\n\nThe preview is above this paragraph.\n\nThe chat should remain readable and interactive."))
    }
    preview.appendItem(DisplayItem(kind: .assistant, text: "Preview transcript ready"))
    model.selectedID = first.id
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: ContentView().environment(model))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for n in 0..<6 {
        let chat = n.isMultiple(of: 2) ? first : preview
        model.selectedID = chat.id
        try await Task.sleep(for: .seconds(2))
        let image = windowImage(window)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: root).appendingPathComponent("switch-\(n).png"))
        let recognize = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: image).perform([recognize])
        let text = (recognize.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        let expected = n.isMultiple(of: 2) ? "plain transcript ready" : "preview transcript ready"
        guard text.contains(expected), text.contains("studios") else {
            fatalError("Switch \(n): transcript or sidebar disappeared. Recognized: \(text)")
        }
        // Exercise actual text input after a switch; do not send it to an agent.
        if let editor = descendants(window.contentView!).compactMap({$0 as? NSTextView}).first(where:{$0.isEditable}) {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor)
                editor.selectAll(nil)
                editor.insertText("Draft survives switch \(n)", replacementRange: editor.selectedRange())
                try await Task.sleep(for: .milliseconds(100))
                precondition(chat.draft == "Draft survives switch \(n)", "Composer did not accept input: switch=\(n), editor=\(type(of:editor)), text=\(editor.string), expectedChat=\(chat.title), first=\(first.draft), preview=\(preview.draft)")
        } else { fatalError("Missing composer") }
        print("PASS switch \(n): transcript, sidebar and composer")
    }
    // The reporter must return promptly, then capture real composited pixels asynchronously.
    let start = Date()
    Diagnostics.shared.reportFreeze()
    precondition(Date().timeIntervalSince(start) < 0.5, "Reporter blocked the main actor")
    try await Task.sleep(for: .seconds(5))
    let reports = try FileManager.default.contentsOfDirectory(at: Diagnostics.folder, includingPropertiesForKeys: nil)
    precondition(reports.contains { $0.lastPathComponent.hasSuffix("freeze.txt") }, "No manual report")
    precondition(reports.contains { $0.lastPathComponent.hasSuffix("window.png") }, "No composited capture")
    Diagnostics.shared.stop()
    print("PASS asynchronous freeze reporter")
}

Task { @MainActor in
    do { try await run(); exit(0) }
    catch { fputs("Rendering regression failed: \(error)\n", stderr); exit(1) }
}
app.run()

/// The window server's image of one of this process's own windows. Needs no screen-recording
/// permission, which ScreenCaptureKit now asks for even for your own windows.
func windowImage(_ window: NSWindow) -> CGImage {
    window.displayIfNeeded()
    typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
    guard let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { fatalError("Couldn't capture the test window") }
    return image
}

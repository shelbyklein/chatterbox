import AppKit
import SwiftUI

// Run through scripts/test-home-thumbnails.sh: copies of your chats, nothing resumed.
// Renders Home's Studios page and checks that threads with images show them on their tiles.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)

@MainActor
func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], root.hasPrefix("/tmp/chatterbox-perf.") else { fatalError("Use the isolated runner") }
    let out = ProcessInfo.processInfo.environment["THUMB_OUT"] ?? "/tmp"
    UserDefaults.standard.setVolatileDomain(["dotCheckIns": false, "dotWatchWaiting": false, "dotSummarizeFinished": false,
        "dotEmailWatch": false, "companionEnabled": false, "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false,
        "macHomePage": ProcessInfo.processInfo.environment["THUMB_PAGE"] ?? "Studios",
        "homeCardScale": Double(ProcessInfo.processInfo.environment["THUMB_SCALE"] ?? "1") ?? 1,
        "themeBackground": ProcessInfo.processInfo.environment["THUMB_THEME"] ?? "standard",
        "sidebarTagFilter": ProcessInfo.processInfo.environment["THUMB_TAGS"] ?? "",
        "sidebarLineSpacing": Double(ProcessInfo.processInfo.environment["THUMB_LINES"] ?? "2") ?? 2,
        "sidebarRowSpacing": Double(ProcessInfo.processInfo.environment["THUMB_ROWS"] ?? "0") ?? 0,
        "sidebarProjectSort": ProcessInfo.processInfo.environment["THUMB_SORT"] ?? "recent"], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1500, height: 900),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: ContentView().environment(model))
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    if ProcessInfo.processInfo.environment["THUMB_SIDEBAR"] != nil {
        try await Task.sleep(for: .seconds(2))   // after the window opens on Home
        model.showingHome = false
    } else { model.showingHome = true }
    try await Task.sleep(for: .seconds(4))
    let studioChats = model.activeSessions.filter { model.studio(for: $0) != nil }
    let shown = studioChats.filter { ThreadThumbnails.shared.images[$0.id] != nil }
    print("Studio threads \(studioChats.count), with a thumbnail \(shown.count): \(shown.map(\.title).prefix(6))")
    if let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\((ProcessInfo.processInfo.environment["THUMB_PAGE"] ?? "Studios").lowercased())\(ProcessInfo.processInfo.environment["THUMB_TAG"] ?? "").png"))
    }
    for s in model.activeSessions where s.record.projectFolder != nil && s.record.worktreeOf == nil {
        let folder = s.record.projectFolder!
        print("ICON \(s.projectName): \(ProjectIcons.shared.icons[folder] != nil ? (ProjectIcons.detect(in: folder)?.path.replacingOccurrences(of: folder, with: "…") ?? "custom") : "none")")
    }
    print(shown.isEmpty ? "RESULT no thumbnails" : "RESULT ok")
    exit(0)
}
Task { @MainActor in do { try await run() } catch { print("error", error); exit(1) } }
app.run()

import AppKit
import SwiftUI

// Renders a project's Automations window against an isolated data folder.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)

@MainActor func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], root.hasPrefix("/tmp/chatterbox-perf.") else { fatalError("Use the isolated runner") }
    UserDefaults.standard.setVolatileDomain(["dotCheckIns": false, "dotWatchWaiting": false, "dotEmailWatch": false, "companionEnabled": false], forName: UserDefaults.argumentDomain)
    let folder = "/Users/shelbyklein/Studio/sdhq"
    try ProjectAutomations.save([
        ProjectAutomation(projectFolder: folder, title: "WordPress updates", template: .wordpress, instructions: ProjectAutomations.wordpressInstructions, weekday: 2, hour: 9),
        ProjectAutomation(projectFolder: folder, title: "Broken link check", template: .custom, instructions: "Crawl the site for broken links.", weekday: 6, hour: 16, minute: 30, enabled: false),
    ])
    let model = AppModel()
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: AutomationsSheet(projectFolder: folder, projectName: "SDHQ").environment(model))
    window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    try await Task.sleep(for: .seconds(2))
    window.displayIfNeeded()
    if let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUT"]!))
    }
    exit(0)
}
Task { @MainActor in do { try await run() } catch { print("error", error); exit(1) } }
app.run()

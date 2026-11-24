import AppKit
import SwiftUI

// Account Usage (ProxyQuotaView): Gemini's limits show beside the proxy's Claude and Codex
// accounts, from the same numbers as the usage meter. Renders it and saves a picture.
@MainActor func run() throws {
    let now = Date()
    UsageLimits.shared.show(claude: [], codex: [], gemini: [
        UsageWindow(id: "5h", label: "5-hour", utilization: 0.25, resetsAt: now.addingTimeInterval(3 * 3600)),
        UsageWindow(id: "weekly", label: "Weekly", utilization: 0.6, resetsAt: now.addingTimeInterval(4 * 86_400)),
    ])
    let view = ProxyQuotaView(route: "Codex · Global provider: cpa-gui").padding(20).frame(width: 580).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage, image.height > 200 else { throw NSError(domain: "render", code: 1) }
    let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "proxy-quota.png")
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: out)
    print("PASS Account Usage renders with a Gemini section (\(image.width)x\(image.height)): \(out.path)")
}
do { try MainActor.assumeIsolated { try run() } } catch { print("FAIL \(error)"); exit(1) }

@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// The Do on Shelby-PC form: task, files to send, agent. Evidence: form.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
struct Harness: View {
 @State var task="Open logo.psd in Photoshop and export a 512 px PNG"
 @State var files=[URL(fileURLWithPath:"/Users/shelby/Desktop/logo.psd")]
 @State var agent=Backend.claude
 var body: some View { PCErrandForm(task:$task,files:$files,agent:$agent){} }
}
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-pc-errand-form."))
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:360,height:320),styleMask:[.titled],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 panel.contentView=NSHostingView(rootView:Harness().background(Color(white:0.14)).environment(\.colorScheme,.dark).fixedSize())
 panel.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(900))
 let host=panel.contentView!;host.layoutSubtreeIfNeeded()
 let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/form.png"))
 print("PASS PC errand form. Evidence: \(root)/form.png")
}
Task { @MainActor in do { try await run(); exit(0) } catch { print("FAIL \(error)"); exit(1) } }
app.run()

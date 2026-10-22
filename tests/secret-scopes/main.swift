@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Renders the secret editor scoped to a project and a Studio. Evidence: editor.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-secret-scopes."))
 let archery=UUID(), playcase=UUID()
 var entry=SecretEntry(name:"ClickUp API",variable:"CLICKUP_API")
 entry.note="ClickUp access"
 entry.projects=["/fixture/website"]
 entry.studios=[archery]
 precondition(!entry.isEverywhere)
 let editor=SecretEditor(entry:entry,isNew:false,
   projects:[(name:"website",folder:"/fixture/website"),(name:"playcase",folder:"/fixture/playcase")],
   studios:[(name:"USA Archery",id:archery),(name:"PlayCase",id:playcase)]){_,_ in}
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:480,height:560),styleMask:[.titled],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 panel.contentView=NSHostingView(rootView:editor.background(Color(white:0.14)).environment(\.colorScheme,.dark))
 panel.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(800))
 let host=panel.contentView!;host.layoutSubtreeIfNeeded()
 let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/editor.png"))
 print("PASS secret editor offers projects and Studios. Evidence: \(root)/editor.png")
}
Task { @MainActor in
 do { try await run(); exit(0) } catch { print("FAIL \(error)"); exit(1) }
}
app.run()

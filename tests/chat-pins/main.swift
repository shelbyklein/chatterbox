@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Pins and unpins messages, then renders the pinned panel open and folded. Evidence: open.png, folded.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-chat-pins."))
 let defaults=UserDefaults(suiteName:"chatterbox.test.chatpins")!
 defaults.removePersistentDomain(forName:"chatterbox.test.chatpins")
 let store=PinnedMessagesStore(defaults:defaults)
 let chat=UUID()
 let reply=DisplayItem(kind:.assistant,text:"Both changes are **live**: the header is tighter and the pills open *Position parts*.")
 let ask=DisplayItem(kind:.user,text:"Remember: never push without asking.")
 store.toggle(reply,in:chat); store.toggle(ask,in:chat)
 precondition(store.pins(for:chat).map(\.id)==[ask.id,reply.id],"newest pin first")
 store.toggle(ask,in:chat); precondition(!store.isPinned(ask.id,in:chat),"toggle unpins")
 store.toggle(ask,in:chat)
 precondition(PinnedMessagesStore(defaults:defaults).pins(for:chat).count==2,"pins persist")
 for expanded in [true,false] {
  store.expanded=expanded
  let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:320,height:360),styleMask:[.titled],backing:.buffered,defer:false)
  panel.appearance=NSAppearance(named:.darkAqua)
  let view=ChatPins(chat:chat,agentName:"Claude",store:store){_ in}.padding(16).background(Color(white:0.12)).environment(\.colorScheme,.dark)
  panel.contentView=NSHostingView(rootView:view.fixedSize())
  panel.orderFrontRegardless()
  try await Task.sleep(for:.milliseconds(600))
  let host=panel.contentView!;host.layoutSubtreeIfNeeded()
  let rendered=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
  host.cacheDisplay(in:host.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(expanded ? "open.png" : "folded.png"))
  panel.close()
 }
 defaults.removePersistentDomain(forName:"chatterbox.test.chatpins")
 print("PASS: pins toggle, persist and render. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

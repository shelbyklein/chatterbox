@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Renders the sidebar's Pins at each size and folded. Evidence: small.png, medium.png, large.png, collapsed.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-sidebar-pins."))
 precondition(ProcessInfo.processInfo.environment["CHATTERBOX_PREFERENCES_SUITE"]=="chatterbox.test.sidebarpins")
 let store=PinStore.shared
 for pin in store.pins { store.remove(pin) }
 for path in ["/System/Applications/Calendar.app","/System/Applications/Notes.app","/System/Applications/Music.app","/Applications","/System/Applications/Maps.app","/System/Applications/Photos.app","/System/Applications/Reminders.app"] {
  let isApp=path.hasSuffix(".app")
  store.add(Pin(title:URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent,kind:isApp ? .app : .file,target:path,place:nil))
 }
 let defaults=UserDefaults.standard
 let saved=(defaults.object(forKey:"sidebarPinSize"),defaults.object(forKey:"sidebarPinsCollapsed"))
 defer { defaults.set(saved.0,forKey:"sidebarPinSize"); defaults.set(saved.1,forKey:"sidebarPinsCollapsed") }
 for (name,size,collapsed) in [("small",24.0,false),("medium",32.0,false),("large",44.0,false),("collapsed",24.0,true)] {
  defaults.set(size,forKey:"sidebarPinSize"); defaults.set(collapsed,forKey:"sidebarPinsCollapsed")
  let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:280,height:200),styleMask:[.titled],backing:.buffered,defer:false)
  panel.appearance=NSAppearance(named:.darkAqua)
  let view=PinsSection(place:nil){_ in}.frame(width:260).padding(10).background(Color(white:0.08)).environment(\.colorScheme,.dark)
  panel.contentView=NSHostingView(rootView:view.fixedSize())
  panel.orderFrontRegardless()
  try await Task.sleep(for:.milliseconds(700))
  let host=panel.contentView!;host.layoutSubtreeIfNeeded()
  let rendered=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
  host.cacheDisplay(in:host.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("\(name).png"))
  panel.close()
 }
 for pin in store.pins { store.remove(pin) }
 print("PASS: pins render at each size and folded. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

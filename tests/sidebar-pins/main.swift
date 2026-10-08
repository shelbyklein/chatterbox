@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Render global toolbar pins and their dedicated Settings page in isolated preferences.
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
 let model = AppModel()
 let place = PinPlace(key: "project:/tmp/example", name: "Example")
 let projectPin = Pin(title: "Project folder", kind: .file, target: "/tmp/example", place: place.key)
 store.add(projectPin)
 precondition(store.globalPins.count == 7 && store.pins(in: place) == [projectPin])
 let first = store.globalPins[0], second = store.globalPins[1]
 store.move(second.id, to: first.id)
 precondition(store.globalPins[0].id == second.id)
 precondition(store.pins(in: place) == [projectPin])
 store.rename(second, to: "My Notes")
 precondition(store.globalPins[0].title == "My Notes")
 let defaults=UserDefaults.standard
 let saved=defaults.object(forKey:"sidebarPinSize")
 defer { defaults.set(saved,forKey:"sidebarPinSize") }
 for (name,size) in [("small",24.0),("medium",32.0),("large",44.0)] {
  defaults.set(size,forKey:"sidebarPinSize")
  try await render(GlobalPinsToolbar().environment(model), name: name, width: 420, height: 60, root: root)
 }
 try await render(PinsSettingsView().environment(model), name: "settings", width: 880, height: 680, root: root)
 try await render(AddPinSheet(request: PinSheetRequest(place: place, current: place)), name: "project-add", width: 500, height: 430, root: root)
 for pin in store.pins { store.remove(pin) }
 print("PASS: global and project pins remain separate; reorder and rename preserve project pins; toolbar, settings and scoped add rendered. Evidence: \(root)")
}
@MainActor func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, root: String) async throws {
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 panel.contentView=NSHostingView(rootView:view.frame(width:width,height:height).background(Color(white:0.08)).environment(\.colorScheme,.dark))
 panel.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(700))
 let host=panel.contentView!;host.layoutSubtreeIfNeeded()
 let rendered=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
 host.cacheDisplay(in:host.bounds,to:rendered)
 try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("\(name).png"))
 panel.close()
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

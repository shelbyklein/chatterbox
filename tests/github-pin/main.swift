@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-github-pin."))
 let pin=Pin(title:"GitHub",kind:.website,target:"https://github.com/shelbyklein/chatterbox")
 _ = PinStore.shared.icon(for:pin)
 for _ in 0..<100 {
  if PinStore.shared.icon(for:pin) != nil {break}
  try await Task.sleep(for:.milliseconds(100))
 }
 guard let image=PinStore.shared.icon(for:pin), let data=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:data) else {fatalError("GitHub favicon failed to load")}
 precondition(bitmap.hasAlpha)
 // Transparent outside corners distinguish the favicon from an opaque touch-icon tile.
 precondition((bitmap.colorAt(x:0,y:0)?.alphaComponent ?? 1) < 0.1)
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:320,height:170),styleMask:[.titled],backing:.buffered,defer:false)
 panel.orderFrontRegardless()
 for dark in [true,false] {
  panel.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
  panel.contentView=NSHostingView(rootView:VStack(spacing:12) {
   PinIcon(pin:pin).frame(width:64,height:64).padding(16).background(Color.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:14))
   Text(dark ? "GitHub · dark" : "GitHub · light")
  }.frame(width:320,height:170).background(dark ? Color.black : Color.white).environment(\.colorScheme,dark ? .dark : .light))
  try await Task.sleep(for:.milliseconds(600))
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(dark ? "dark.png" : "light.png"))
 }
 print("PASS: actual GitHub favicon loaded with transparent corners; native pin rendered light/dark. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

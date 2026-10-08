@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Renders the prompt-preset list (normal and editing). Evidence: list.png, editing.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-quick-prompts."))
 QuickPrompts.shared.prompts=[QuickPrompt(title:"Sync branches to main",prompt:"/dev-sync"),QuickPrompt(title:"Ship it",prompt:"Commit, push and install the current work")]
 var sent:[String]=[]
 for editing in [false,true] {
  let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:320,height:360),styleMask:[.titled],backing:.buffered,defer:false)
  panel.appearance=NSAppearance(named:.darkAqua)
  panel.contentView=NSHostingView(rootView:QuickPromptList(send:{sent.append($0.prompt)},editing:editing).fixedSize().background(Color(white:0.12)).environment(\.colorScheme,.dark))
  panel.orderFrontRegardless()
  try await Task.sleep(for:.milliseconds(600))
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(editing ? "editing.png" : "list.png"))
  panel.close()
 }
 print("PASS: prompt presets rendered. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

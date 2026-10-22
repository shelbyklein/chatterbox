@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// A session on Shelby-PC is grey: the model chip, the message box and your bubbles.
// Evidence: mac.png (Claude on the Mac), pc.png (an open model on the PC).
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-pc-color."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 let style=ReaderStyle()
 for (name,open) in [("mac",nil),("pc","qwen3.5:9b")] as [(String,String?)] {
  var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
  record.openModel=open
  record.items=[DisplayItem(kind:.user,text:"What's on the PC's D: drive?"),DisplayItem(kind:.assistant,text:"Three folders: Chatterbox, Games and Backups.",phase:.final)]
  let session=model.insertSession(record)
  precondition(session.usesPC == (open != nil))
  precondition((style.color(for:session) == ReaderStyle.pcColor) == (open != nil),"\(name): color follows the PC")
  precondition((style.agentColor(for:session) == ReaderStyle.pcColor) == (open != nil),"\(name): agent color follows the PC")
  let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:760,height:420),styleMask:[.titled],backing:.buffered,defer:false)
  panel.appearance=NSAppearance(named:.darkAqua)
  panel.contentView=NSHostingView(rootView:ChatView(session:session).environment(model).environment(\.colorScheme,.dark))
  panel.orderFrontRegardless()
  try await Task.sleep(for:.seconds(1.2))
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/\(name).png"))
  panel.close()
 }
 print("PASS sessions on Shelby-PC are grey. Evidence: \(root)")
}
Task { @MainActor in do { try await run(); exit(0) } catch { print("FAIL \(error)"); exit(1) } }
app.run()

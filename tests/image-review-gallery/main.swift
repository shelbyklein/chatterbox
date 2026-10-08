@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Renders the image review sheet opened on the middle of three chat images: both Previous and
// Next show, with "2 of 3". Evidence: review.png in the temp folder.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-image-review."))
 var urls:[URL]=[]
 for (i,color) in [NSColor.systemBlue,.systemOrange,.systemGreen].enumerated() {
  let image=NSImage(size:NSSize(width:800,height:500),flipped:false) { rect in
   color.setFill(); rect.fill()
   ("Image \(i+1)" as NSString).draw(at:NSPoint(x:320,y:230),withAttributes:[.font:NSFont.boldSystemFont(ofSize:48),.foregroundColor:NSColor.white])
   return true
  }
  let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
  let url=URL(fileURLWithPath:root).appendingPathComponent("image-\(i+1).png")
  try rep.representation(using:.png,properties:[:])!.write(to:url)
  urls.append(url)
 }
 let middle=Attachment(name:urls[1].lastPathComponent,path:urls[1].path,mediaType:"image/png",kind:.image)
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:1100,height:680),styleMask:[.titled],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 panel.contentView=NSHostingView(rootView:ImageReviewView(attachment:middle,gallery:urls) { _,_ in }.frame(width:1100,height:680))
 panel.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(1200))
 let view=panel.contentView!;view.layoutSubtreeIfNeeded()
 let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:rendered)
 try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("review.png"))
 // Preserve the user's clipboard while verifying an image (not its path) copies.
 let pasteboard=NSPasteboard.general
 let saved=(pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } }
 defer {
  pasteboard.clearContents()
  let restored=saved.map { values in let item=NSPasteboardItem();for (type,data) in values {item.setData(data,forType:type)};return item }
  _=pasteboard.writeObjects(restored)
 }
 precondition(ImageClipboard.copy(urls[0]))
 precondition(pasteboard.data(forType:.png) != nil && pasteboard.data(forType:.tiff) != nil)
 for count in [1,3] {
  panel.contentView=NSHostingView(rootView:ReplyImages(urls:Array(urls.prefix(count))).padding(20).frame(width:1100,height:680,alignment:.topLeading).background(Color.black).environment(\.colorScheme,.dark))
  try await Task.sleep(for:.milliseconds(900))
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("reply-\(count).png"))
 }
 print("PASS: gallery and single/multiple image copy controls rendered; clipboard has PNG/TIFF. Evidence: \(root)/review.png")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

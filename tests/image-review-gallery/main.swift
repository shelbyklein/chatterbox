@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Renders the image review sheet opened on the middle of three chat images: both Previous and
// Next show, with "2 of 3". Evidence: review.png in the temp folder.
let app=NSApplication.shared
// Regular, so the panel takes the test's clicks.
app.setActivationPolicy(.regular)
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
 // A click near the picture's right edge makes a mark (the clickable area once stopped short
 // of it). The blue picture, so an orange mark shows against it.
 let blue=Attachment(name:urls[0].lastPathComponent,path:urls[0].path,mediaType:"image/png",kind:.image)
 // Wide, so the picture sits centered with room either side, as in a wide window.
 panel.setContentSize(NSSize(width:1700,height:680))
 panel.contentView=NSHostingView(rootView:ImageReviewView(attachment:blue,gallery:urls) { _,_ in }.frame(width:1700,height:680))
 try await Task.sleep(for:.milliseconds(1200))
 func render()->NSBitmapImageRep { let v=panel.contentView!;v.layoutSubtreeIfNeeded();let r=v.bitmapImageRepForCachingDisplay(in:v.bounds)!;v.cacheDisplay(in:v.bounds,to:r);return r }
 let before=render()
 let scale=CGFloat(before.pixelsWide)/before.size.width
 func color(_ r:NSBitmapImageRep,_ p:CGPoint)->NSColor { r.colorAt(x:Int(p.x*scale),y:Int(p.y*scale))!.usingColorSpace(.sRGB)! }
 func isBlue(_ c:NSColor)->Bool { c.blueComponent>0.7 && c.redComponent<0.3 }
 // The picture's right edge, along its middle row (view points, top-left origin).
 let midY=before.size.height/2
 guard let right=stride(from:before.size.width-1,through:0,by:-1).first(where:{ isBlue(color(before,CGPoint(x:$0,y:midY))) }) else { print("FAIL: the picture shows");exit(1) }
 // Above the Next arrow, which sits at the middle of the right edge.
 let target=CGPoint(x:right-14,y:midY-120)
 panel.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
 try await Task.sleep(for:.milliseconds(300))
 let hosting=panel.contentView!
 let inWindow=hosting.convert(NSPoint(x:target.x,y:hosting.isFlipped ? target.y : hosting.bounds.height-target.y),to:nil)
 for kind in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
  try await Task.sleep(for:.milliseconds(60))
  panel.sendEvent(NSEvent.mouseEvent(with:kind,location:inWindow,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!)
 }
 try await Task.sleep(for:.milliseconds(500))
 let after=render()
 let mark=color(after,CGPoint(x:target.x-7,y:target.y))
 precondition(mark.redComponent>0.8 && mark.blueComponent<0.4,"a click at the picture's right edge (\(Int(target.x)) of \(Int(before.size.width))) makes a mark: \(mark)")
 try after.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("mark-right-edge.png"))
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
  panel.setContentSize(NSSize(width:1100,height:680));panel.contentView=NSHostingView(rootView:ReplyImages(urls:Array(urls.prefix(count))).padding(20).frame(width:1100,height:680,alignment:.topLeading).background(Color.black).environment(\.colorScheme,.dark))
  try await Task.sleep(for:.milliseconds(900))
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("reply-\(count).png"))
 }
 print("PASS: a mark at the picture's right edge; gallery and single/multiple image copy controls rendered; clipboard has PNG/TIFF. Evidence: \(root)/review.png")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

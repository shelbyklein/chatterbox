@testable import ChatterboxTestEngine
import AppKit
import PDFKit
import SwiftUI
// Comments on a PDF. Pages render about 2000 px long, following rotation. The review opens on
// page 2 of 3; a click makes a spot and a drag a box, numbered on their page; marks stay with
// their page across Next and Previous; Send gives one message ("Page 2:", "Page 3:") with a
// marked-up PNG per marked page, then the PDF. The viewer offers Comment when it can send.
// Evidence: review.png, viewer.png and the sent page copies in the temp folder.
let app=NSApplication.shared
// Regular, so the panel takes the test's clicks and the note fields take focus.
app.setActivationPolicy(.regular)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-pdf-review."))
 // Three letter pages: a blue block at the top left, "Page N" in the middle.
 let url=URL(fileURLWithPath:root).appendingPathComponent("Proof.pdf")
 var media=CGRect(x:0,y:0,width:612,height:792)
 let writer=CGContext(url as CFURL,mediaBox:&media,nil)!
 for n in 1...3 {
  writer.beginPDFPage(nil)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current=NSGraphicsContext(cgContext:writer,flipped:false)
  NSColor.white.setFill();media.fill()
  NSColor.systemBlue.setFill();NSRect(x:40,y:672,width:160,height:80).fill()
  ("Page \(n)" as NSString).draw(at:NSPoint(x:220,y:380),withAttributes:[.font:NSFont.boldSystemFont(ofSize:48),.foregroundColor:NSColor.black])
  NSGraphicsContext.restoreGraphicsState()
  writer.endPDFPage()
 }
 writer.closePDF()
 let document=PDFDocument(url:url)!
 precondition(document.pageCount==3)

 func bitmap(_ image:NSImage)->NSBitmapImageRep { NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!) }
 func sample(_ rep:NSBitmapImageRep,_ x:CGFloat,_ y:CGFloat)->NSColor { rep.colorAt(x:Int(x*CGFloat(rep.pixelsWide)),y:Int(y*CGFloat(rep.pixelsHigh)))!.usingColorSpace(.sRGB)! }
 func isBlue(_ c:NSColor)->Bool { c.blueComponent>0.7 && c.redComponent<0.3 }
 func isOrange(_ c:NSColor)->Bool { c.redComponent>0.8 && c.greenComponent>0.25 && c.blueComponent<0.3 }
 func isWhite(_ c:NSColor)->Bool { c.redComponent>0.95 && c.greenComponent>0.95 && c.blueComponent>0.95 }

 // The page picture: 2000 px on the long side, top left where the page's is.
 let page2=bitmap(ImageReviewView.render(document.page(at:1)!))
 precondition(page2.pixelsHigh==2000 && page2.pixelsWide==1545,"Page renders 2000 px long: \(page2.pixelsWide)x\(page2.pixelsHigh)")
 precondition(isBlue(sample(page2,0.15,0.1)) && isWhite(sample(page2,0.85,0.1)),"Page renders upright")
 // A page turned a quarter clockwise: wide, its top left now at the top right.
 let turnedDocument=PDFDocument(url:url)!
 turnedDocument.page(at:0)!.rotation=90
 let turned=bitmap(ImageReviewView.render(turnedDocument.page(at:0)!))
 precondition(turned.pixelsWide==2000 && turned.pixelsHigh==1545 && isBlue(sample(turned,0.9,0.15)) && isWhite(sample(turned,0.1,0.15)),"A rotated page renders turned")

 // The review, open on page 2.
 var sentText=""
 var sentFiles:[Attachment]=[]
 let original=try Data(contentsOf:url)
 // Non-activating: it takes key (and so the clicks) without activating the app, which a test
 // started from an agent's shell can't do; a window that isn't key spends a click becoming key.
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:1200,height:760),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 // A captured view leaves out the window's own background: the dark one, so text shows.
 let backdrop=Color(white:0.16)
 panel.contentView=NSHostingView(rootView:ImageReviewView(pdf:.pdf(url),document:document,page:1) { text,files in sentText=text;sentFiles=files }.frame(width:1200,height:760).background(backdrop))
 panel.makeKeyAndOrderFront(nil)
 try await Task.sleep(for:.milliseconds(1200))
 precondition(panel.isKeyWindow,"The review panel takes key")
 func render()->NSBitmapImageRep { let v=panel.contentView!;v.layoutSubtreeIfNeeded();let r=v.bitmapImageRepForCachingDisplay(in:v.bounds)!;v.cacheDisplay(in:v.bounds,to:r);return r }
 var shot=render()
 let scale=CGFloat(shot.pixelsWide)/shot.size.width
 func color(_ r:NSBitmapImageRep,_ p:CGPoint)->NSColor { r.colorAt(x:Int(p.x*scale),y:Int(p.y*scale))!.usingColorSpace(.sRGB)! }
 // The white page on the dark canvas (view points, top-left origin), along a row above the
 // arrows, whose chevrons are white too.
 let canvasWidth=shot.size.width-281
 let row=stride(from:CGFloat(0),to:canvasWidth,by:1).filter { isWhite(color(shot,CGPoint(x:$0,y:shot.size.height/4))) }
 guard let left=row.first,let right=row.last else { print("FAIL: the page shows");exit(1) }
 let column=stride(from:CGFloat(0),to:shot.size.height,by:1).filter { isWhite(color(shot,CGPoint(x:left+4,y:$0))) }
 let pageRect=CGRect(x:left,y:column.first!,width:right-left+1,height:column.last!-column.first!+1)
 precondition(abs(pageRect.width/pageRect.height-612.0/792)<0.02,"The page keeps its shape: \(pageRect)")
 precondition(isBlue(color(shot,CGPoint(x:pageRect.minX+0.15*pageRect.width,y:pageRect.minY+0.1*pageRect.height))),"The review shows the page upright")
 func at(_ x:CGFloat,_ y:CGFloat)->CGPoint { CGPoint(x:pageRect.minX+x*pageRect.width,y:pageRect.minY+y*pageRect.height) }

 func pointer(_ type:NSEvent.EventType,_ p:CGPoint) {
  let view=panel.contentView!
  let location=view.convert(NSPoint(x:p.x,y:view.isFlipped ? p.y : view.bounds.height-p.y),to:nil)
  panel.sendEvent(NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
 }
 func click(_ p:CGPoint) async throws {
  pointer(.leftMouseDown,p);try await Task.sleep(for:.milliseconds(60));pointer(.leftMouseUp,p)
  try await Task.sleep(for:.milliseconds(400))
 }
 func drag(_ from:CGPoint,_ to:CGPoint) async throws {
  pointer(.leftMouseDown,from)
  for step in 1...6 {
   try await Task.sleep(for:.milliseconds(40))
   let t=CGFloat(step)/6
   pointer(.leftMouseDragged,CGPoint(x:from.x+(to.x-from.x)*t,y:from.y+(to.y-from.y)*t))
  }
  pointer(.leftMouseUp,to)
  try await Task.sleep(for:.milliseconds(400))
 }
 // A new mark's note field takes focus: type into it as the keyboard would.
 func type(_ text:String) async throws {
  guard let field=panel.firstResponder as? NSTextView else { print("FAIL: the new mark's note field has focus (\(String(describing:panel.firstResponder)))");exit(1) }
  field.insertText(text,replacementRange:NSRange(location:NSNotFound,length:0))
  try await Task.sleep(for:.milliseconds(250))
 }
 // Coordinates as in the image review test: the arrows sit mid-canvas, Send at the bottom right.
 let size=panel.contentView!.bounds.size
 let next=CGPoint(x:size.width-315,y:size.height/2),previous=CGPoint(x:34,y:size.height/2)
 let send=CGPoint(x:size.width-60,y:size.height-28)

 // Page 2: a spot at the top right and a box at the bottom left. A badge's number sits at its
 // center, so its orange is checked just left of there.
 try await click(at(0.7,0.3))
 try await type("Make the heading bigger")
 try await drag(at(0.1,0.6),at(0.5,0.8))
 try await type("Tighten this paragraph")
 shot=render()
 let spotBadge=CGPoint(x:at(0.7,0.3).x-7,y:at(0.7,0.3).y)
 precondition(isOrange(color(shot,spotBadge)),"A click makes a numbered spot")
 precondition(isOrange(color(shot,CGPoint(x:at(0.1,0.6).x-7,y:at(0.1,0.6).y))),"A drag makes a numbered box")

 // Page 3 starts clean; its own spot, in the middle.
 try await click(next)
 try await Task.sleep(for:.milliseconds(500))
 shot=render()
 precondition(!isOrange(color(shot,spotBadge)),"Page 3 doesn't show page 2's marks")
 try await click(at(0.5,0.5))
 try await type("Swap this photo")
 // Back on page 2, its marks are there again.
 try await click(previous)
 try await Task.sleep(for:.milliseconds(500))
 shot=render()
 precondition(isOrange(color(shot,spotBadge)),"Page 2 keeps its marks across Next and Previous")
 precondition(!isOrange(color(shot,CGPoint(x:at(0.5,0.5).x-7,y:at(0.5,0.5).y))),"Page 2 doesn't show page 3's mark")
 // Evidence: page 2's marks and notes, "Page 2 of 3", and the sidebar's "Also marked: page 3".
 try shot.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("review.png"))

 try await click(send)
 print(sentText)
 precondition(sentFiles.count==3,"Send attaches pages 2 and 3, then the PDF: \(sentFiles.map(\.name))")
 precondition(sentFiles[2].path==url.path && sentFiles[2].kind == .pdf,"The PDF itself comes last")
 precondition(sentFiles[0].name=="Marked up Proof page 2.png" && sentFiles[1].name=="Marked up Proof page 3.png","Page copies are named by page: \(sentFiles.map(\.name))")
 precondition(sentText.hasPrefix("Feedback on Proof.pdf. Marked-up copies of pages 2, 3 are attached, numbered as below."),"The heading names the PDF and the pages")
 precondition(sentText.contains("\nPage 2:\n1. spot at top right (x ") && sentText.contains("): Make the heading bigger\n2. area at bottom left (x "),"Page 2's marks, numbered and placed in words")
 precondition(sentText.contains("): Tighten this paragraph\n\nPage 3:\n1. spot at center (x ") && sentText.hasSuffix("): Swap this photo"),"Page 3's mark, numbered from 1")
 for (index,file) in sentFiles.prefix(2).enumerated() {
  let copy=NSBitmapImageRep(data:try Data(contentsOf:file.url))!
  precondition(copy.pixelsWide==1545 && copy.pixelsHigh==2000,"A page copy is 2000 px long")
  precondition(isBlue(sample(copy,0.15,0.1)),"A page copy shows the page upright")
  // Badges are 48 px across the middle at this size: 30 px left of center is orange.
  let marked=index==0 ? [CGPoint(x:0.7,y:0.3),CGPoint(x:0.1,y:0.6)] : [CGPoint(x:0.5,y:0.5)]
  for point in marked {
   let c=copy.colorAt(x:Int(point.x*1545)-30,y:Int(point.y*2000))!.usingColorSpace(.sRGB)!
   precondition(isOrange(c),"Page \(index+2)'s copy has its numbered mark at \(point)")
  }
  try FileManager.default.copyItem(at:file.url,to:URL(fileURLWithPath:root).appendingPathComponent("sent-page-\(index+2).png"))
 }
 let after=try Data(contentsOf:url)
 precondition(after==original,"The PDF itself never changes")

 // The viewer: Comment shows beside the page controls when it can send to a session. (Its
 // page is drawn in layers, which a captured view leaves blank.)
 panel.contentView=NSHostingView(rootView:DocumentViewer(document:LocalDocument(url:url)) { _,_ in }.frame(width:1200,height:760).background(backdrop))
 try await Task.sleep(for:.milliseconds(1500))
 try render().representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("viewer.png"))
 print("PASS: page rendering (size, upright, rotated), spot and box marks per page across Next and Previous, one message with Page 2 and Page 3, a marked-up copy per page and the PDF last; PDF unchanged. Evidence: \(root)/review.png, \(root)/sent-page-2.png, \(root)/viewer.png")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

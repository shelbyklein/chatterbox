@testable import Chatterbox
import AppKit
import PDFKit
import SwiftUI
// A multi-page PDF in the document viewer: one page at a time with flip buttons, two-page
// spreads (the cover alone), and the long scroll. Evidence: pages.png, spreads.png, scroll.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
var failures=0
func check(_ ok:Bool,_ what:String) { print((ok ? "PASS " : "FAIL ")+what); if !ok { failures+=1 } }
@MainActor func shot(_ window:NSWindow,_ name:String,_ root:URL) throws {
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    // Five landscape pages, each a color with its number.
    let doc=PDFDocument()
    for (i,color) in [NSColor.systemRed,.systemBlue,.systemGreen,.systemOrange,.systemPurple].enumerated() {
        let image=NSImage(size:NSSize(width:800,height:500),flipped:false){r in
            color.setFill();r.fill()
            ("Page \(i+1)" as NSString).draw(at:NSPoint(x:40,y:40),withAttributes:[.font:NSFont.boldSystemFont(ofSize:80),.foregroundColor:NSColor.white])
            return true
        }
        doc.insert(PDFPage(image:image)!,at:i)
    }
    let url=root.appendingPathComponent("Brochure.pdf");precondition(doc.write(to:url))
    UserDefaults.standard.set("pages",forKey:"pdfLayout")
    let window=NSWindow(contentRect:NSRect(x:40,y:40,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:DocumentViewer(document:LocalDocument(url:url)).background(Color(white:0.14)).environment(\.colorScheme,.dark))
    window.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1.5))
    func all(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap(all)}
    guard let pdfView=all(window.contentView!).compactMap({$0 as? PDFView}).first else { check(false,"the PDF shows");exit(1) }
    check(pdfView.displayMode == .singlePage,"Pages shows one page at a time")
    // The window capture leaves PDF pages blank (PDFView draws them itself); check a page's own render.
    let thumb=pdfView.document!.page(at:0)!.thumbnail(of:NSSize(width:80,height:50),for:.mediaBox)
    let bits=NSBitmapImageRep(data:thumb.tiffRepresentation!)!
    let c=bits.colorAt(x:40,y:5)!.usingColorSpace(.sRGB)!
    check(c.redComponent > 0.7 && c.greenComponent < 0.5,"the first page renders its content (red: \(String(format:"%.2f %.2f %.2f",c.redComponent,c.greenComponent,c.blueComponent)))")
    pdfView.goToNextPage(nil);pdfView.goToNextPage(nil)
    try await Task.sleep(for:.milliseconds(400))
    let at=pdfView.currentPage.map { pdfView.document!.index(for:$0) } ?? -1;check(at == 2,"flipping forward twice reaches page 3 (at \(at+1))")
    try shot(window,"pages.png",root)
    UserDefaults.standard.set("spreads",forKey:"pdfLayout")
    try await Task.sleep(for:.seconds(1))
    check(pdfView.displayMode == .twoUp && pdfView.displaysAsBook,"Spreads shows two pages, the cover alone")
    try shot(window,"spreads.png",root)
    UserDefaults.standard.set("scroll",forKey:"pdfLayout")
    try await Task.sleep(for:.seconds(1))
    check(pdfView.displayMode == .singlePageContinuous,"Scroll shows the long column")
    try shot(window,"scroll.png",root)
    let pager=PDFPager()
    check(pager.label(total:5,spreads:false)=="1 of 5","page counter")
    UserDefaults.standard.removeObject(forKey:"pdfLayout")
    window.orderOut(nil)
    print(failures==0 ? "PASS pdf flip views. Evidence: \(root.path)" : "FAIL \(failures) checks")
    exit(failures==0 ? 0 : 1)
}
Task { @MainActor in do {try await run()} catch {print(error);exit(1)} }
app.run()

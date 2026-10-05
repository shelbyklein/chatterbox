import AppKit
import PDFKit
import ScreenCaptureKit
import SwiftUI
import Vision

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOC_TEST_DIR"]!)
    let md = root.appendingPathComponent("Approved plan.md")
    try "# Approved plan\n\nReview the flyer before publishing.\n\n- Confirm the deadline\n- Check the exported PDF\n\n**Nothing has been published.**".write(to: md, atomically: true, encoding: .utf8)
    let pdf = root.appendingPathComponent("Review flyer.pdf")
    var box = CGRect(x: 0,y: 0,width: 612,height: 792)
    let ctx = CGContext(pdf as CFURL, mediaBox: &box, nil)!
    for i in 1...3 {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(box)
        ctx.setFillColor(NSColor.systemOrange.cgColor); ctx.fill(CGRect(x: 40,y: 400,width: 532,height: 300))
        ctx.endPDFPage()
        print("Created page \(i)")
    }
    ctx.closePDF()
    precondition(LocalDocument.supports(md) && LocalDocument.supports(pdf))
    precondition(!LocalDocument.supports(root.appendingPathComponent("page.html")))
    precondition(FileLink.resolve(URL(string: "Approved%20plan.md")!, in: root.path) == md)
    let loaded = try DocumentLoader.text(md)
    precondition(loaded.contains("Nothing has been published"))
    let big = root.appendingPathComponent("large.md")
    try Data(repeating: 65, count: 2_000_001).write(to: big)
    do { _ = try DocumentLoader.text(big); fatalError("Large file accepted") } catch { print("PASS size limit") }
    do { _ = try DocumentLoader.text(root.appendingPathComponent("missing.md")); fatalError("Missing accepted") } catch { print("PASS missing file") }
    let doc = PDFDocument(url: pdf)!
    precondition(doc.pageCount == 3)
    let native = PDFView(); native.document = doc
    native.go(to: doc.page(at: 2)!)
    precondition(native.currentPage === doc.page(at: 2))
    print("PASS native PDF page navigation")
    let panel = NSPanel(contentRect: NSRect(x: 20,y:20,width:900,height:650),styleMask: [.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.appearance = NSAppearance(named:.darkAqua)
    for (name, url, expected) in [("markdown",md,"approved plan"),("pdf",pdf,"review flyer.pdf")] {
        panel.contentView = NSHostingView(rootView: DocumentViewer(document: LocalDocument(url:url)))
        panel.orderFrontRegardless()
        try await Task.sleep(for:.seconds(2))
        let image = windowImage(panel)
        try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("\(name).png"))
        let request = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage:image).perform([request])
        let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:" ").lowercased()
        precondition(recognized.contains(expected), "Missing rendered document: \(recognized)")
        print("PASS rendered \(name)")
    }
    panel.orderOut(nil)
}
Task { do { try await run(); exit(0) } catch { print(error); exit(1) } }
app.run()

/// The window server's image of one of this process's own windows. Needs no screen-recording
/// permission, which ScreenCaptureKit now asks for even for your own windows.
func windowImage(_ window: NSWindow) -> CGImage {
    window.displayIfNeeded()
    typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
    guard let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { fatalError("Couldn't capture the test window") }
    return image
}

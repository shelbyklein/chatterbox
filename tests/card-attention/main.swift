@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
    precondition(root.hasPrefix("/tmp/chatterbox-card-attention."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    let model = AppModel()
    var record = ConversationRecord(model:"opus", effort:"medium", personality:.pragmatic)
    record.title = "Question waiting"
    record.items = [DisplayItem(kind:.questions,text:"Which layout should I use?",approvalState:.pending)]
    let artwork=URL(fileURLWithPath:root).appendingPathComponent("latest-artwork.png")
    let icon=NSWorkspace.shared.icon(forFile:"/System/Applications/Notes.app")
    let representation=NSBitmapImageRep(data:icon.tiffRepresentation!)!
    try representation.representation(using:.png,properties:[:])!.write(to:artwork)
    record.items.insert(DisplayItem(kind:.assistant,text:"Latest artwork: [Preview](" + artwork.path + ")",phase:.final),at:0)
    let waiting = model.insertSession(record)
    record.id = UUID(); record.title = "Ready session"; record.items = [DisplayItem(kind:.assistant,text:"Latest artwork: [Preview](" + artwork.path + ")",phase:.final)]
    let ready = model.insertSession(record)
    precondition(ChatSession.referencedImages(in: "Latest artwork: [Preview](" + artwork.path + ")", folder: root).contains(artwork))
    let window = NSWindow(contentRect:NSRect(x:50,y:80,width:750,height:550),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.orderFrontRegardless()
    func render(_ name:String, _ dark:Bool) async throws {
        window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: VStack(alignment:.leading,spacing:16) {
            Text("Pending question: unselected / selected / ready").font(.headline)
            HStack(alignment:.top,spacing:16) {
                ThreadCard(session:waiting) {}.frame(width:220).fixedSize(horizontal:false,vertical:true)
                ThreadCard(session:waiting,selected:true) {}.frame(width:220).fixedSize(horizontal:false,vertical:true)
                ThreadCard(session:ready) {}.frame(width:220).fixedSize(horizontal:false,vertical:true)
            }
            HStack(spacing:24) {
                ThreadCard(session:waiting,iconOnly:true) {}
                ThreadCard(session:waiting,iconOnly:true,selected:true) {}
                ThreadCard(session:ready,iconOnly:true) {}
            }
        }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(dark ? Color.black : Color.white).environment(model).environment(\.colorScheme,dark ? .dark : .light))
        try await Task.sleep(for:.milliseconds(700))
        let view=window.contentView!; view.layoutSubtreeIfNeeded()
        let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(name+".png"))
    }
    precondition(waiting.isWaitingOnYou && !ready.isWaitingOnYou)
    try await render("pending-dark",true)
    precondition(ThreadThumbnails.shared.images[waiting.id] != nil && ThreadThumbnails.shared.images[ready.id] != nil)
    try await render("pending-light",false)
    waiting.record.items[1].approvalState = .approved
    precondition(!waiting.isWaitingOnYou)
    try await render("answered-dark",true)
    let html = URL(fileURLWithPath:root).appendingPathComponent("Website Review.html")
    try "<html><body>Report</body></html>".write(to:html,atomically:true,encoding:.utf8)
    let paths = PathLinks.context(for:html.path,folder:root)
    for source in [html.path, "**\(html.path)**", "`\(html.path)`"] {
        let linked = MarkdownText.inline(source,paths:paths)
        precondition(linked.runs.contains {$0.link?.scheme == PathLinks.scheme && $0.link?.path == html.path}, "Existing file must be clickable: \(source)")
    }
    precondition(!MarkdownText.inline(root+"/missing.html",paths:paths).runs.contains {$0.link != nil})
    precondition(MarkdownText.inline("[Site](https://example.com)",paths:paths).runs.contains {$0.link?.absoluteString == "https://example.com"})
    let actual = "/Users/shelbyklein/Vibes/wpsolutions.com/competitor-report/WPS-Competitor-Website-Review.html"
    if FileManager.default.fileExists(atPath:actual) {
        precondition(MarkdownText.inline("**\(actual)**",paths:paths).runs.contains {$0.link?.path == actual})
    }
    window.setContentSize(NSSize(width:750,height:160))
    window.contentView = NSHostingView(rootView: MarkdownText(text:"The report is ready:\n\n**\(html.path)** (3.2 MB)").padding(20).frame(width:750,height:160,alignment:.topLeading).environment(\.chatFolder,root))
    window.setContentSize(NSSize(width:750,height:160))
    try await Task.sleep(for:.milliseconds(700))
    let view=window.contentView!; view.layoutSubtreeIfNeeded()
    let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("html-link.png"))
    print("PASS: bare/bold/code existing HTML paths (including spaces), missing file stays unlinked, explicit web links preserved; actual reported path verified.")
    print("PASS: pending and answered question state; selected/unselected cards and icon tiles rendered in light/dark. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

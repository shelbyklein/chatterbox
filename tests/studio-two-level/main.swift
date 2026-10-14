@testable import Chatterbox
import AppKit
import SwiftUI
// A Studio session open in the chat view: the Studios down the left, the Studio's sessions,
// then the chat, and the same with Images showing. Evidence: chat.png, library-images.png, library-files.png, cards.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func png(_ url:URL,_ color:NSColor) throws {
    let image=NSImage(size:NSSize(width:600,height:400),flipped:false){r in color.setFill();r.fill();return true}
    try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:url)
}
@MainActor func shot(_ window:NSWindow,_ name:String,_ root:URL) throws {
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-studio-two-level."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"mainSidebarWidth":260.0],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    let archery=model.newStudio(named:"USA Archery")!, geekify=model.newStudio(named:"Geekify")!
    _ = geekify
    let logos=model.chats(in:archery).first!
    logos.setTitle("National Event Logos")
    var items:[DisplayItem]=[DisplayItem(kind:.user,text:"Make the field nationals logo")]
    for (i,color) in [NSColor.systemRed,.systemBlue,.systemOrange].enumerated() {
        let url=root.appendingPathComponent("logo-\(i).png");try png(url,color)
        var item=DisplayItem(kind:.image,text:"");item.attachments=[Attachment(name:url.lastPathComponent,path:url.path,mediaType:"image/png",kind:.image)];items.append(item)
    }
    // A file the chat shared, for the Library's Files.
    let brief=root.appendingPathComponent("Logo brief.txt");try "Field nationals logo brief".write(to:brief,atomically:true,encoding:.utf8)
    var shared=DisplayItem(kind:.user,text:"Here's the brief");shared.attachments=[Attachment(name:brief.lastPathComponent,path:brief.path,mediaType:"text/plain",kind:.text)];items.insert(shared,at:1)
    items.append(DisplayItem(kind:.assistant,text:"Here are three takes on the logo.",phase:.final))
    logos.record.items=items
    let other=model.newChat(in:archery);other.setTitle("Collegiate One Pager")
    model.selectedID=logos.id
    precondition(model.studioSidebarID==archery.id,"opening a Studio session shows its Studio")
    let window=NSWindow(contentRect:NSRect(x:40,y:40,width:1400,height:820),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
    window.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1.5))
    try shot(window,"chat.png",root)
    // The chat's Library: its images (with the circles that pick them), then its files.
    let library=NSWindow(contentRect:NSRect(x:60,y:60,width:960,height:640),styleMask:[.titled],backing:.buffered,defer:false)
    library.appearance=NSAppearance(named:.darkAqua)
    UserDefaults.standard.set("images",forKey:"chatLibraryShows")
    library.contentView=NSHostingView(rootView:ChatImageGallery(session:logos,onOpen:{_ in}).background(Color(white:0.14)).environment(model).environment(\.colorScheme,.dark))
    library.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1.2))
    try shot(library,"library-images.png",root)
    UserDefaults.standard.set("files",forKey:"chatLibraryShows")
    try await Task.sleep(for:.seconds(1.2))
    try shot(library,"library-files.png",root)
    UserDefaults.standard.removeObject(forKey:"chatLibraryShows")
    library.orderOut(nil)
    // The sessions as cards: each one's newest image across the top, filling its frame.
    UserDefaults.standard.set(true,forKey:"macStudioSidebarCards")
    try await Task.sleep(for:.seconds(1.5))
    try shot(window,"cards.png",root)
    UserDefaults.standard.removeObject(forKey:"macStudioSidebarCards")
    print("PASS two-level Studio sidebar, the chat's Library (images, files) and cards render. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

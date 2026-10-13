@testable import Chatterbox
import AppKit
import SwiftUI
// A Studio session open in the chat view: the Studios down the left, the Studio's sessions,
// then the chat, and the same with Images showing. Evidence: chat.png, images.png.
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
    UserDefaults.standard.set(true,forKey:"studioChatShowsImages")
    try await Task.sleep(for:.seconds(1.2))
    try shot(window,"images.png",root)
    UserDefaults.standard.removeObject(forKey:"studioChatShowsImages")
    print("PASS two-level Studio sidebar and Chat/Images render. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

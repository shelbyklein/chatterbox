@testable import Chatterbox
import AppKit
import SwiftUI
// The Studio page as cards, at 6 to a row and at 2. Evidence: cards-6.png, cards-2.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func png(_ url:URL,_ color:NSColor) throws {
    let image=NSImage(size:NSSize(width:600,height:450),flipped:false){r in color.setFill();r.fill();return true}
    try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:url)
}
@MainActor func shot(_ window:NSWindow,_ name:String,_ root:URL) throws {
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-studio-cards."))
    UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    let studio=model.newStudio(named:"USA Archery")!
    let colors:[NSColor]=[.systemRed,.systemBlue,.systemOrange,.systemTeal,.systemPink,.systemIndigo,.systemGreen,.systemYellow]
    for (i,color) in colors.enumerated() {
        let chat=i==0 ? model.chats(in:studio).first! : model.newChat(in:studio)
        chat.setTitle("Session \(i+1)")
        let url=root.appendingPathComponent("s\(i).png");try png(url,color)
        var image=DisplayItem(kind:.image,text:"");image.attachments=[Attachment(name:url.lastPathComponent,path:url.path,mediaType:"image/png",kind:.image)]
        chat.record.items=[DisplayItem(kind:.user,text:"Make it"),image,DisplayItem(kind:.assistant,text:"Here's version \(i+1).",phase:.final)]
    }
    UserDefaults.standard.set(studio.id.uuidString,forKey:"macStudioSelection")
    UserDefaults.standard.set("cards",forKey:"macStudioLayout")
    defer { for key in ["macStudioSelection","macStudioLayout","macStudioCardColumns"] { UserDefaults.standard.removeObject(forKey:key) } }
    let window=NSWindow(contentRect:NSRect(x:40,y:40,width:1400,height:860),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:ChatHomeView(menu:{_ in AnyView(EmptyView())}).environment(model).environment(\.colorScheme,.dark))
    window.orderFrontRegardless()
    for columns in [6.0,2.0] {
        UserDefaults.standard.set(columns,forKey:"macStudioCardColumns")
        try await Task.sleep(for:.seconds(1.5))
        try shot(window,"cards-\(Int(columns)).png",root)
    }
    print("PASS Studio cards at 6 and 2 to a row. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

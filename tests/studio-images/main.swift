@testable import Chatterbox
import AppKit
import SwiftUI
// A Studio's Images view: images from several sessions in one grid, newest first, each
// labelled with its session. No agents run. Evidence: grid.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func png(_ url:URL,_ color:NSColor,_ label:String) throws {
    let image=NSImage(size:NSSize(width:640,height:420),flipped:false){rect in
        color.setFill();rect.fill()
        (label as NSString).draw(at:NSPoint(x:40,y:180),withAttributes:[.font:NSFont.boldSystemFont(ofSize:64),.foregroundColor:NSColor.white])
        return true}
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try rep.representation(using:.png,properties:[:])!.write(to:url)
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-studio-images."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    var sessions:[ChatSession]=[]
    for (n,(title,colors)) in [("National Event Logos",[NSColor.systemRed,.systemBlue]),("Indoor Nationals Program",[NSColor.systemIndigo]),("Archie",[NSColor.systemOrange,.systemTeal,.systemPink])].enumerated() {
        var items:[DisplayItem]=[]
        for (i,color) in colors.enumerated() {
            let url=root.appendingPathComponent("\(n)-\(i).png");try png(url,color,"\(title.prefix(8)) \(i+1)")
            // Older first: the grid sorts by when each file was made.
            try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(Double(-3600*(n*3+i)))],ofItemAtPath:url.path)
            var item=DisplayItem(kind:.image,text:"")
            item.attachments=[Attachment(name:url.lastPathComponent,path:url.path,mediaType:"image/png",kind:.image)]
            items.append(item)
        }
        var r=ConversationRecord(model:"opus",effort:"",personality:.friendly);r.title=title;r.items=items
        sessions.append(model.insertSession(r))
    }
    let found=SessionImageGrid.collect(sessions)
    precondition(found.count==6,"every session's images: \(found.count)")
    precondition(zip(found,found.dropFirst()).allSatisfy{$0.date >= $1.date},"newest first")
    precondition(found.first?.title=="National Event Logos","each image knows its session")
    let window=NSWindow(contentRect:NSRect(x:40,y:60,width:640,height:520),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:SessionImageGrid(session:sessions[2]).environment(model).environment(\.colorScheme,.dark).frame(width:640,height:520).background(Color(white:0.1)))
    window.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1.5))
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("grid.png"))
    window.close()
    print("PASS session images: every image, newest first. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

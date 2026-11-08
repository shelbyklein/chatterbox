@testable import Chatterbox
import AppKit
import SwiftUI
setbuf(stdout,nil)
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-archive-view."))
    UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"sidebarTagFilter":"hidden-tag","sidebarChatTagFilter":"hidden-tag"],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    let active=model.newChat();active.setTitle("Active thread stays open");active.draft="Unsent active draft"
    let studio=model.newStudio(named:"Archery")!
    var archived:[ChatSession]=[]
    for i in 0..<40 {
        var r=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
        r.title=i==0 ? "Prepare downloadable Club Handbook" : i==1 ? "Playcase Logo Updates" : "Archived thread \(i)"
        r.archivedAt=Date().addingTimeInterval(-Double(i)*86400)
        r.activeBackend=i%2==0 ? .codex : .claude
        r.items=[DisplayItem(kind:.assistant,text:i==0 ? "The handbook is ready for your review." : "Completed work remains available in this archived conversation.",phase:.final)]
        if i==0 {r.studioID=studio.id}
        if i==1 {r.projectFolder=root.appendingPathComponent("Playcase").path}
        let s=model.insertSession(r);archived.append(s)
    }
    archived[0].draft="Archived draft preserved"
    precondition(model.archivedSessions.map(\.id)==archived.map(\.id),"complete archive, newest first")
    precondition(model.archivedSessions(matching:"  ").count==40)
    precondition(model.archivedSessions(matching:"ARCHERY handbook").map(\.id)==[archived[0].id])
    precondition(model.archivedSessions(matching:"ready review").map(\.id)==[archived[0].id])
    precondition(model.archivedSessions(matching:"does-not-exist").isEmpty)
    model.selectedID=active.id
    let panel=NSPanel(contentRect:NSRect(x:20,y:20,width:1240,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    panel.appearance=NSAppearance(named:.darkAqua)
    panel.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
    panel.makeKeyAndOrderFront(nil)
    func pause() async throws {try await Task.sleep(for:.milliseconds(650))}
    func capture(_ name:String) throws {
        let host=panel.contentView!;host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
    }
    func click(_ rect:CGRect) async throws {
        precondition(rect.width>0 && rect.height>0,"missing native target")
        let point=NSPoint(x:rect.midX,y:panel.frame.height-rect.midY)
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            app.postEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!,atStart:false)
        }
        try await pause()
    }
    func field(_ v:NSView)->NSTextField? {
        if let f=v as? NSTextField,f.placeholderString=="Search archived threads" {return f}
        return v.subviews.lazy.compactMap{field($0)}.first
    }
    func type(_ value:String) async throws {
        let f=field(panel.contentView!)!
        panel.makeFirstResponder(f)
        let editor=f.currentEditor() as! NSTextView
        editor.selectAll(nil);editor.insertText(value,replacementRange:editor.selectedRange())
        try await pause()
    }
    try await pause()
    try await click(SidebarDebug.archive)
    precondition(model.showingArchive,"actual Archived dock button opens center page")
    precondition(panel.title=="Archived","native toolbar title reflects page")
    precondition(field(panel.contentView!) != nil && panel.contentView!.bounds.width>1000)
    try capture("archived-wide")
    try await type("Archived thread 39")
    precondition(MacHomeDebug.cards[archived[39].id] != nil,"search reaches a thread beyond the first screen")
    try await type("ARCHERY handbook")
    precondition(MacHomeDebug.cards[archived[0].id] != nil)
    try capture("archived-search")
    try await click(MacHomeDebug.cards[archived[0].id]!)
    precondition(model.selectedID==archived[0].id && !model.showingArchive)
    precondition(archived[0].record.archivedAt != nil && archived[0].draft=="Archived draft preserved")
    try await click(SidebarDebug.archive)
    precondition(field(panel.contentView!)!.stringValue=="ARCHERY handbook","query survives opening a result and returning")
    try await type("no-match-903")
    try capture("archived-no-match")
    try await type("")
    panel.setContentSize(NSSize(width:760,height:650));try await pause()
    try capture("archived-narrow")
    model.showView(.chats);precondition(!model.showingArchive)
    precondition(active.draft=="Unsent active draft")
    for s in archived {s.setArchived(false)}
    model.showingArchive=true;try await pause()
    precondition(model.archivedSessions.isEmpty)
    try capture("archived-empty")
    panel.close()
    print("PASS global 40-thread archive/order, cross-Studio search, real dock/search/card actions, query retention, archive/drafts unchanged, native wide/narrow/empty/no-match renders")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

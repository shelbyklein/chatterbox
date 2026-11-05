@testable import Chatterbox
import AppKit
import SwiftUI
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-mac-home."))
    UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"sidebarProjectsCollapsed":false,"sidebarStudiosCollapsed":false,"sidebarChatsCollapsed":false,"sidebarSectionWeights":"1.6,0.6,0.8"],forName:UserDefaults.argumentDomain)
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    UserDefaults.standard.set(false, forKey: "macProjectsSidebarCards")
    UserDefaults.standard.set(HomeThreadPage.projects.rawValue,forKey:"macHomePage")
    defer { UserDefaults.standard.removeObject(forKey: "macProjectsSidebarCards"); UserDefaults.standard.removeObject(forKey:"macHomePage") }
    let model = AppModel()
    func project(_ title: String, _ backend: Backend) -> ChatSession {
        var record = ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
        record.title=title; record.projectNickname=title; record.projectFolder=root.appendingPathComponent(title).path
        record.activeBackend=backend
        record.items=[DisplayItem(kind:.assistant,text:"The latest build is ready to review. Your changes are preserved in this thread.",phase:.final)]
        return model.insertSession(record)
    }
    let parent=project("Chatterbox",.codex); parent.draft="Draft stays here"
    let other=project("SDHQ",.claude)
    var branchRecord=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    branchRecord.title="Layout experiment";branchRecord.projectFolder=root.appendingPathComponent("layout").path
    branchRecord.worktreeOf=parent.record.projectFolder;branchRecord.worktreeBranch="layout"
    branchRecord.items=[DisplayItem(kind:.assistant,text:"The narrow layout is ready for a visual check.",phase:.final)]
    let branch=model.insertSession(branchRecord)
    let side = model.newSidechat(of:parent)
    let studio=model.newStudio(named:"Geekify")!
    let studioChat=model.chats(in:studio).first!
    studioChat.setTitle("Dark Crystal painting"); model.setStudio(studio.id,collapsed:true)
    let regular=model.newChat(backend:.codex); regular.setTitle("PlayCase magnets")
    var archivedRecord=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    archivedRecord.title="Archived layout review";archivedRecord.archivedAt=Date()
    archivedRecord.items=[DisplayItem(kind:.assistant,text:"This archived conversation remains available with its history intact.",phase:.final)]
    let archived=model.insertSession(archivedRecord);archived.draft="Archived draft stays"
    let question=DisplayItem(kind:.questions,text:"Choose a layout",approvalState:.pending)
    other.record.items.append(question)
    parent.isRunning=true
    let all=HomeThreads.groups(model).flatMap(\.threads)
    precondition(Set(all.map(\.id)).count==all.count)
    precondition(Set(all.map(\.id))==Set(model.activeSessions.map(\.id)),"Missing active thread, including collapsed Studio")
    precondition(HomeThreads.groups(model,search:"Geekify").flatMap(\.threads).contains {$0.id==studioChat.id})
    precondition(HomeThreads.groups(model,search:"layout").flatMap(\.threads).contains {$0.id==branch.id})
    precondition(HomeThreads.groups(model,filter:.working).flatMap(\.threads).map(\.id)==[parent.id])
    precondition(HomeThreads.groups(model,filter:.needsYou).flatMap(\.threads).contains {$0.id==other.id})
    precondition(HomeThreads.groups(model,search:"no-match-903").isEmpty)
    let pageThreads=[HomeThreadPage.projects,.studios,.chats].flatMap { HomeThreads.groups(model,page:$0).flatMap(\.threads) }
    precondition(Set(pageThreads.map(\.id))==Set(model.activeSessions.map(\.id)) && Set(pageThreads.map(\.id)).count==pageThreads.count)
    precondition(HomeThreads.groups(model,page:.projects).flatMap(\.threads).contains {$0.id==branch.id})
    // Sidechats sit inside their parent's card, not as cards of their own.
    precondition(!HomeThreads.groups(model,page:.projects).flatMap(\.threads).contains {$0.id==side.id} && model.childChats(of:parent).contains {$0.id==side.id})
    precondition(HomeThreads.groups(model,page:.studios).flatMap(\.threads).map(\.id)==[studioChat.id])
    precondition(HomeThreads.groups(model,page:.chats).flatMap(\.threads).contains {$0.id==regular.id})
    precondition(HomeThreads.groups(model,page:.archive).flatMap(\.threads).map(\.id)==[archived.id])
    precondition(HomeThreads.groups(model,page:.archive,search:"layout").flatMap(\.threads).map(\.id)==[archived.id])
    precondition(HomeThreads.groups(model,page:.projects,search:"Geekify").isEmpty)
    let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
    model.selectedID=parent.id
    let panel=NSPanel(contentRect:NSRect(x:40,y:90,width:280,height:60),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    panel.orderFrontRegardless()
    var globalOrigin = CGPoint.zero
    func render(_ view: AnyView, _ width: CGFloat, _ height: CGFloat, _ name: String, _ dark: Bool = true) async throws {
        MacHomeDebug.cards=[:]; MacHomeDebug.entries=[:]; MacHomeDebug.pinnedGroups=[:]; MacHomeDebug.inspected=nil
        panel.setContentSize(NSSize(width:width,height:height)); panel.setFrameOrigin(NSPoint(x:20,y:20))
        panel.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
        panel.contentView=NSHostingView(rootView:view.environment(model).environment(\.colorScheme,dark ? .dark : .light).onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { globalOrigin = $0 })
        try await Task.sleep(for:.milliseconds(700))
        try snapshot(name)
    }
    func snapshot(_ name: String) throws {
        let content=panel.contentView!;content.layoutSubtreeIfNeeded()
        let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds)!
        content.cacheDisplay(in:content.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
    }
    func point(_ frame: CGRect, _ x: CGFloat = 0.5) -> NSPoint {
        // Global frames are window-relative already: only flip to AppKit coordinates.
        NSPoint(x:frame.minX+frame.width*x,y:panel.frame.height-frame.midY)
    }
    func click(_ point: NSPoint, count: Int = 1) async throws {
        for n in 1...count {
            for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:n,clickCount:n,pressure:1)!
                app.postEvent(event, atStart: false)
            }
        }
        try await Task.sleep(for:.milliseconds(400))
    }
    // Sidebar view controls (per-section Cards keys), unchanged by the Studios page.
    try await render(AnyView(DesktopOverviewControls().padding(12)),280,60,"controls")
    try await click(NSPoint(x:77,y:30))
    precondition(UserDefaults.standard.bool(forKey:"macProjectsSidebarCards"),"Native Cards segment failed")
    setenv("CHATTERBOX_TEST_SIDEBAR_ONLY","230",1)
    try await render(AnyView(ContentView()),230,900,"sidebar-cards")
    for thread in [parent,other,branch] {   // standalone chats live on the Chats page; sidechats inside their parent card
        guard let frame=MacHomeDebug.cards[thread.id] else {fatalError("Missing visible sidebar card \(thread.title) of \(MacHomeDebug.cards.count)")}
        precondition(frame.minX>=globalOrigin.x && frame.maxX<=globalOrigin.x+230,"Clipped sidebar card")
    }
    try await render(AnyView(DesktopOverviewControls().padding(12)),280,60,"controls-persisted")
    try await click(NSPoint(x:33,y:30))
    precondition(!UserDefaults.standard.bool(forKey:"macProjectsSidebarCards"),"Native List segment failed")
    unsetenv("CHATTERBOX_TEST_SIDEBAR_ONLY")
    parent.isRunning=false

    // MARK: Thread families: work threads sit inside their front thread's card (list and cards),
    // at most three children until Show more; a working one always shows; Activity leaves them out.
    let works=try (1...5).map { n in try model.newWorkThread(of:parent,title:"Work thread \(n)") }
    // lastActivity is the later of created and updated: set both.
    side.record.createdAt=Date().addingTimeInterval(-30); side.record.updatedAt=side.record.createdAt
    for (n,work) in works.enumerated() { work.record.createdAt=Date().addingTimeInterval(TimeInterval(-60*(n+1))); work.record.updatedAt=work.record.createdAt }
    works[4].isRunning=true   // the oldest, but working
    precondition(!model.sidebarProjects.contains { thread in works.contains { $0 === thread } }, "a work thread isn't a project")
    precondition(model.sidechats(of:parent).filter { $0.record.workOf==parent.id }.count==5, "work threads are the front thread's children")
    precondition(!Attention.shared.activityWorking(in:model).contains { $0 === works[4] } && Attention.shared.workingChats(in:model).contains { $0 === works[4] },
                 "Activity leaves a working work thread out; the Desk still sees it")
    let collapsed=ThreadFamilyLimit.visible(model.sidechats(of:parent),expanded:false,updatedAt:\.lastActivity) { $0.isRunning || $0.isWaitingOnYou }
    precondition(collapsed.shown.map(\.id)==[side.id,works[0].id,works[4].id] && collapsed.hidden==3, "newest first, three shown, the working one among them")
    setenv("CHATTERBOX_TEST_SIDEBAR_ONLY","300",1)
    SidebarDebug.families=[:]; SidebarDebug.rows=[:]; SidebarDebug.familyToggles=[:]; FamilyExpansion.shared.ids=[]
    try await render(AnyView(ContentView()),300,900,"mac-list-cards")
    guard let family=SidebarDebug.families[parent.id] else { fatalError("No family card for Chatterbox") }
    for thread in [parent,side,works[0],works[4],branch] {
        guard let frame=SidebarDebug.rows[thread.id] else { fatalError("Missing row \(thread.title)") }
        precondition(family.insetBy(dx:-1,dy:-1).contains(frame), "\(thread.title) sits inside Chatterbox's card")
    }
    for hidden in works[1...3] { precondition(SidebarDebug.rows[hidden.id]==nil, "\(hidden.title) waits behind Show more") }
    if let sdhq=SidebarDebug.families[other.id] { precondition(sdhq.minY >= family.maxY || sdhq.maxY <= family.minY, "each family its own card") }
    else { fatalError("SDHQ has no card of its own") }
    guard let toggle=SidebarDebug.familyToggles[parent.id] else { fatalError("No Show more") }
    try await click(point(toggle))
    try await Task.sleep(for:.milliseconds(400)); try snapshot("mac-list-cards-expanded")
    precondition(FamilyExpansion.shared.ids.contains(parent.id), "Show more expands the family")
    for work in works { precondition(SidebarDebug.rows[work.id].map { SidebarDebug.families[parent.id]!.insetBy(dx:-1,dy:-1).contains($0) } == true, "\(work.title) shows once expanded") }
    // Cards: the same three inside the front thread's card, then Show more.
    UserDefaults.standard.set(true, forKey: "macProjectsSidebarCards")
    FamilyExpansion.shared.ids=[]; MacHomeDebug.childRows=[:]; MacHomeDebug.familyToggles=[:]
    try await render(AnyView(ContentView()),300,900,"mac-cards-family")
    precondition(MacHomeDebug.cards[parent.id] != nil && works.allSatisfy { MacHomeDebug.cards[$0.id]==nil }, "no card of their own")
    precondition(Set(MacHomeDebug.childRows.keys)==Set([side.id,works[0].id,works[4].id]) && MacHomeDebug.familyToggles[parent.id] != nil,
                 "three children in the card, then Show more: \(MacHomeDebug.childRows.count)")
    try await click(point(MacHomeDebug.familyToggles[parent.id]!))
    try await Task.sleep(for:.milliseconds(400)); try snapshot("mac-cards-family-expanded")
    precondition(Set(works.map(\.id)).isSubset(of: Set(MacHomeDebug.childRows.keys)), "all of them once expanded")
    UserDefaults.standard.set(false, forKey: "macProjectsSidebarCards")
    // One waiting on you surfaces in Activity as its front thread's row, not its own.
    works[1].record.items.append(DisplayItem(kind:.questions,text:"Which layout?",approvalState:.pending))
    precondition(works[1].isWaitingOnYou && Attention.shared.workNeedingYou(in:model).map(\.id)==[works[1].id], "a work thread needing you is listed for its front thread's row")
    try await render(AnyView(SidebarActivityStrip().frame(width:280).padding(8).background(Color(nsColor:.windowBackgroundColor))),300,220,"mac-activity-work-needs-you")
    works[1].record.items.removeLast()
    unsetenv("CHATTERBOX_TEST_SIDEBAR_ONLY")
    works[4].isRunning=false
    for work in works { model.archive(work) }
    FamilyExpansion.shared.ids=[]

    // MARK: Studios page fixtures: images, statuses, pins.
    func picture(_ name: String, _ hue: CGFloat, width: Int = 2000, height: Int = 1500) -> URL {
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        NSGradient(starting:NSColor(hue:hue,saturation:0.7,brightness:0.9,alpha:1),ending:NSColor(hue:hue+0.15,saturation:0.8,brightness:0.35,alpha:1))!.draw(in:NSRect(x:0,y:0,width:width,height:height),angle:-35)
        for ring in 0..<5 {
            let inset=CGFloat(ring)*CGFloat(height)/12
            NSColor(white:ring.isMultiple(of:2) ? 1 : 0.1,alpha:0.85).setFill()
            NSBezierPath(ovalIn:NSRect(x:CGFloat(width)/2-CGFloat(height)/2.6+inset,y:CGFloat(height)/2-CGFloat(height)/2.6+inset,width:CGFloat(height)/1.3-inset*2,height:CGFloat(height)/1.3-inset*2)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let url=root.appendingPathComponent(name+".png")
        try! rep.representation(using:.png,properties:[:])!.write(to:url)
        return url
    }
    func studioThread(_ studio: Studio, _ title: String, reply: String, image: URL?, backend: Backend = .claude) -> ChatSession {
        var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
        record.title=title;record.studioID=studio.id;record.studioFolder=studio.folder;record.activeBackend=backend
        if let image {
            record.items.append(DisplayItem(kind:.image,timestamp:Date().addingTimeInterval(-120),attachments:[Attachment(name:image.lastPathComponent,path:image.path,mediaType:"image/png",kind:.image)]))
        }
        record.items.append(DisplayItem(kind:.assistant,text:reply,phase:.final))
        return model.insertSession(record)
    }
    let usa=model.newStudio(named:"USA Archery")!
    let magazine=studioThread(usa,"2027 Indoor Magazine",reply:"Cover updated with the new target art. Review the latest proof before continuing.",image:picture("magazine",0.6))
    let ribbons=studioThread(usa,"National Event Ribbons",reply:"Refining the landscape fill on the ribbon set.",image:picture("ribbons",0.02),backend:.codex)
    let logos=studioThread(usa,"Event Logos",reply:"New proof of the field logo is ready.",image:nil)
    let crystal=studioThread(studio,"Dark Crystal",reply:"Rendering the next angle of the crystal.",image:picture("crystal",0.12))
    ribbons.isRunning=true
    logos.record.items.append(DisplayItem(kind:.questions,text:"Choose the final direction",approvalState:.pending))

    // SI1: status priority, notes and image dates from the chat itself.
    precondition(StudioSessionSummary(logos).status == .needsYou)
    logos.isRunning=true
    precondition(StudioSessionSummary(logos).status == .needsYou,"Needs you must win over Working")
    logos.isRunning=false
    precondition(StudioSessionSummary(ribbons,unread:true).status == .working,"Working must win over Ready to review")
    precondition(StudioSessionSummary(magazine,unread:true).status == .review)
    precondition(StudioSessionSummary(magazine,unread:false).status == .idle)
    precondition(StudioSessionSummary(magazine).note=="Cover updated with the new target art.","Note: \(StudioSessionSummary(magazine).note)")
    precondition(StudioSessionSummary(studioChat).note=="No replies yet")
    precondition(StudioSessionSummary(logos).imageDate==nil)
    precondition(StudioSessionSummary(magazine).imageDate==magazine.items.first!.timestamp,"Image date is the image row's")

    // SI2: large previews are decoded large; tiles stay small.
    ThreadThumbnails.shared.refreshLarge(magazine)
    for _ in 0..<40 where ThreadThumbnails.shared.largeImages[magazine.id]==nil { try await Task.sleep(for:.milliseconds(100)) }
    let large=ThreadThumbnails.shared.largeImages[magazine.id]!.size, small=ThreadThumbnails.shared.images[magazine.id]!.size
    precondition(max(large.width,large.height)>=1000,"Large preview too small: \(large)")
    // Tiles decode at 480 px, sharp across a full-width card, still far from the large previews.
    precondition(max(small.width,small.height)<=480,"Tile thumbnail grew: \(small)")

    // SI3/SI4: the page opens on Pinned, showing only pinned Studio sessions, grouped.
    for thread in [magazine,ribbons,crystal,studioChat] { model.togglePinnedThread(thread) }
    model.togglePinnedThread(parent)   // a pinned project never appears on the Studios page
    UserDefaults.standard.removeObject(forKey:"macStudioSelection"); UserDefaults.standard.removeObject(forKey:"macStudioInspected")
    defer { UserDefaults.standard.removeObject(forKey:"macStudioSelection"); UserDefaults.standard.removeObject(forKey:"macStudioInspected") }
    model.showingHome=true
    try await render(AnyView(ContentView()),1500,950,"studios-pinned-wide")
    precondition(Set(MacHomeDebug.cards.keys)==Set([magazine.id,ribbons.id,crystal.id,studioChat.id]),"Pinned cards: \(MacHomeDebug.cards.count)")
    precondition(Set(MacHomeDebug.pinnedGroups.keys)==Set([usa.id.uuidString,studio.id.uuidString]),"Pinned groups")
    precondition(MacHomeDebug.cards[logos.id]==nil,"Unpinned session appeared on Pinned")
    precondition(MacHomeDebug.entries["pinned"] != nil && MacHomeDebug.entries[usa.id.uuidString] != nil,"Left column entries missing")
    let column=MacHomeDebug.column, activity=MacHomeDebug.activity
    precondition(activity.minX>=column.minX-1 && activity.maxX<=column.maxX+1 && activity.minY<column.minY+40,"Activity is not at the top of the Studios column")
    for frame in MacHomeDebug.cards.values { precondition(frame.minX>=column.maxX && frame.maxX<=globalOrigin.x+1500,"Card overlaps the column or clips") }

    // SI6: a card click opens its Studio's inspector on that session; the choice persists.
    try await click(point(MacHomeDebug.cards[ribbons.id]!))
    precondition(UserDefaults.standard.string(forKey:"macStudioSelection")==usa.id.uuidString,"Card did not select its Studio")
    precondition(model.showingHome,"Single click must not open the chat")
    try await render(AnyView(ContentView()),1500,950,"studios-inspector-wide")
    precondition(MacHomeDebug.inspected==ribbons.id,"Inspector shows \(String(describing: MacHomeDebug.inspected))")
    // SI5: every session in the Studio is listed; selecting another updates the detail.
    precondition(Set([magazine.id,ribbons.id,logos.id]).isSubset(of:Set(MacHomeDebug.cards.keys)),"Inspector list incomplete")
    precondition(MacHomeDebug.cards[crystal.id]==nil,"Another Studio's session in the list")
    try await click(point(MacHomeDebug.cards[magazine.id]!))
    try await Task.sleep(for:.milliseconds(600))
    precondition(MacHomeDebug.inspected==magazine.id,"Row selection did not update the inspector")
    precondition(max(MacHomeDebug.previewPixels.width,MacHomeDebug.previewPixels.height)>=1000,"Inspector preview is not full size: \(MacHomeDebug.previewPixels)")
    try snapshot("studios-inspector-magazine")
    // SI6: the filter applies to the inspector list.
    try await click(point(MacHomeDebug.filter,0.5))
    try await Task.sleep(for:.milliseconds(400))
    try snapshot("studios-inspector-needs-you")
    precondition(MacHomeDebug.listed==[logos.id],"Needs you filter rows: \(MacHomeDebug.listed.count)")
    precondition(MacHomeDebug.inspected==logos.id,"Inspector did not follow the filtered list")
    try await click(point(MacHomeDebug.filter,0.17))
    // Remounting keeps the Studio and its inspected session.
    try await render(AnyView(ContentView()),1500,950,"studios-inspector-remount")
    precondition(MacHomeDebug.inspected==magazine.id,"Inspected session not restored")
    // Open Chat selects the session and leaves the page; nothing in the chat changes.
    let before=try encoder.encode(magazine.record)
    try await click(point(MacHomeDebug.openChat))
    precondition(model.selectedID==magazine.id && !model.showingHome,"Open Chat failed")
    let after=try encoder.encode(magazine.record); precondition(after==before)

    // Double-clicking a Pinned card opens the chat.
    UserDefaults.standard.set("pinned",forKey:"macStudioSelection")
    model.showingHome=true
    try await render(AnyView(ContentView()),1500,950,"studios-pinned-again")
    try await click(point(MacHomeDebug.cards[crystal.id]!),count:2)
    precondition(model.selectedID==crystal.id && !model.showingHome,"Double-click did not open the chat")

    // A left-column click switches Studios; a deleted Studio falls back to Pinned.
    model.showingHome=true
    try await render(AnyView(ContentView()),1500,950,"studios-entry")
    try await click(point(MacHomeDebug.entries[studio.id.uuidString]!))
    precondition(UserDefaults.standard.string(forKey:"macStudioSelection")==studio.id.uuidString,"Left column click failed")
    UserDefaults.standard.set(UUID().uuidString,forKey:"macStudioSelection")
    try await render(AnyView(ContentView()),1500,950,"studios-missing-studio")
    precondition(!MacHomeDebug.pinnedGroups.isEmpty && MacHomeDebug.inspected==nil,"Missing Studio did not fall back to Pinned")

    // Narrow window: nothing clips or overlaps.
    try await render(AnyView(ContentView()),900,900,"studios-pinned-narrow",false)
    for frame in MacHomeDebug.cards.values { precondition(frame.minX>=MacHomeDebug.column.maxX && frame.maxX<=globalOrigin.x+900+1,"Narrow card clipped") }
    UserDefaults.standard.set(usa.id.uuidString,forKey:"macStudioSelection")
    try await render(AnyView(ContentView()),900,900,"studios-inspector-narrow",false)
    for frame in MacHomeDebug.cards.values { precondition(frame.minX>=MacHomeDebug.column.maxX && frame.maxX<=globalOrigin.x+900+1,"Narrow row clipped") }

    // Empty Pinned: the empty state, and no cards.
    for thread in model.pinnedThreads { model.togglePinnedThread(thread) }
    UserDefaults.standard.set("pinned",forKey:"macStudioSelection")
    try await render(AnyView(ContentView()),1500,950,"studios-pinned-empty")
    precondition(MacHomeDebug.cards.isEmpty && MacHomeDebug.pinnedGroups.isEmpty)
    precondition(parent.draft=="Draft stays here")
    print("PASS: Studios page — status priority/notes/image dates, large previews, Pinned grouping and empty state, Activity at the column's top, native card/row/entry/filter/Open Chat/double-click navigation, saved selection and missing-Studio fallback, wide and narrow layouts. Proof: \(root.path)")
    panel.orderOut(nil)
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()

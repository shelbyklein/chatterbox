@testable import Chatterbox
import AppKit
import SwiftUI
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-mac-home."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"sidebarProjectsCollapsed":false,"sidebarStudiosCollapsed":false,"sidebarChatsCollapsed":false,"sidebarSectionWeights":"1.6,0.6,0.8"],forName:UserDefaults.argumentDomain)
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    UserDefaults.standard.set(false, forKey: "macSidebarCards")
    defer { UserDefaults.standard.removeObject(forKey: "macSidebarCards") }
    let model = AppModel()
    var golemRecord=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    golemRecord.title="Golem"; golemRecord.isDot=true; golemRecord.activeBackend = .codex
    golemRecord.items=[DisplayItem(kind:.assistant,text:"Your projects are up to date. Two threads have new work ready to review.",phase:.final)]
    _ = model.insertSession(golemRecord)
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
    let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
    let before=try encoder.encode(parent.record)
    model.selectedID=parent.id
    let panel=NSPanel(contentRect:NSRect(x:40,y:90,width:280,height:60),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    panel.orderFrontRegardless()
    var globalOrigin = CGPoint.zero
    func render(_ view: AnyView, _ width: CGFloat, _ height: CGFloat, _ name: String, _ dark: Bool = true) async throws {
        MacHomeDebug.cards=[:]
        panel.setContentSize(NSSize(width:width,height:height))
        panel.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
        panel.contentView=NSHostingView(rootView:view.environment(model).environment(\.colorScheme,dark ? .dark : .light).onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { globalOrigin = $0 })
        try await Task.sleep(for:.milliseconds(500))
        let content=panel.contentView!;content.layoutSubtreeIfNeeded()
        let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds)!
        content.cacheDisplay(in:content.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
    }
    func click(_ point: NSPoint) async throws {
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            app.postEvent(event, atStart: false)
        }
        try await Task.sleep(for:.milliseconds(250))
    }
    try await render(AnyView(DesktopOverviewControls().padding(12)),280,60,"controls")
    try await click(NSPoint(x:77,y:30))
    precondition(UserDefaults.standard.bool(forKey:"macSidebarCards"),"Native Cards segment failed")
    // Home's real sidebar button, located from its production rendered bounds.
    let home=MacHomeDebug.home
    try await click(NSPoint(x:home.midX-globalOrigin.x,y:panel.contentView!.bounds.height-(home.midY-globalOrigin.y)))
    precondition(model.showingHome,"Native Home entry failed")
    try await render(AnyView(ContentView()),1200,1000,"home-wide")
    guard let frame=MacHomeDebug.cards[parent.id] else { fatalError("Project not rendered") }
    precondition(frame.minX>=globalOrigin.x && frame.maxX<=globalOrigin.x+1200)
    try await click(NSPoint(x:frame.midX-globalOrigin.x,y:panel.contentView!.bounds.height-(frame.midY-globalOrigin.y)))
    precondition(!model.showingHome && model.selectedID==parent.id,"Native existing-card navigation failed")
    precondition(parent.draft=="Draft stays here" && (try! encoder.encode(parent.record))==before)
    model.showingHome=true
    try await render(AnyView(ContentView()),640,850,"home-narrow",false)
    for frame in MacHomeDebug.cards.values {precondition(frame.minX>=globalOrigin.x && frame.maxX<=globalOrigin.x+640,"Clipped Home card")}
    setenv("CHATTERBOX_TEST_SIDEBAR_ONLY","230",1)
    try await render(AnyView(ContentView()),230,900,"sidebar-cards")
    for thread in [parent,other,branch,side,regular] {
        guard let frame=MacHomeDebug.cards[thread.id] else {fatalError("Missing visible sidebar card")}
        precondition(frame.minX>=globalOrigin.x && frame.maxX<=globalOrigin.x+230,"Clipped sidebar card")
    }
    // Newly mounted controls read the persisted Cards selection.
    try await render(AnyView(DesktopOverviewControls().padding(12)),280,60,"controls-persisted")
    precondition(UserDefaults.standard.bool(forKey:"macSidebarCards"))
    try await click(NSPoint(x:33,y:30))
    precondition(!UserDefaults.standard.bool(forKey:"macSidebarCards"),"Native List segment failed")
    try await render(AnyView(ContentView()),230,900,"sidebar-list")
    unsetenv("CHATTERBOX_TEST_SIDEBAR_ONLY")
    model.showingHome=true; model.selectedID=regular.id
    precondition(!model.showingHome)
    model.showingHome=true; model.showingSettings=true
    precondition(!model.showingHome)
    parent.isRunning=false
    print("PASS: unique complete groups, collapsed Studio/search/filters, native List/Cards/Home/card clicks, same-session history and draft preserved. Proof: \(root.path)")
    panel.orderOut(nil)
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()

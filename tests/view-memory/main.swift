@testable import Chatterbox
import AppKit
import SwiftUI
// Each main view returns to the session it was last in.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-view-memory."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    UserDefaults.standard.removeObject(forKey:"lastSessionInView")
    defer { UserDefaults.standard.removeObject(forKey:"lastSessionInView") }
    let model=AppModel()
    func project(_ name:String)->ChatSession{var r=ConversationRecord(model:"opus",effort:"",personality:.friendly);r.title=name;r.projectFolder=root.path+"/"+name;r.items=[DisplayItem(kind:.user,text:"hi")];return model.insertSession(r)}
    let alpha=project("alpha"), beta=project("beta")
    let studio=model.newStudio(named:"Archery")!
    let logos=model.chats(in:studio).first!;logos.setTitle("Logos")
    let flyers=model.newChat(in:studio);flyers.setTitle("Flyers")
    let chatA=model.newChat();chatA.setTitle("Plain A");chatA.record.items=[DisplayItem(kind:.user,text:"a")]
    let chatB=model.newChat();chatB.setTitle("Plain B");chatB.record.items=[DisplayItem(kind:.user,text:"b")]
    func at(_ s:ChatSession)->Bool{model.selectedID==s.id && !model.showingHome}
    model.selectedID=beta.id
    model.showView(.studios)
    precondition(at(logos),"Studios returns to the session a new Studio opened")
    model.selectedID=flyers.id
    precondition(model.studioSidebarID==studio.id,"a Studio session shows its Studio")
    model.showView(.projects); precondition(at(beta),"Projects returns to the project it was left in, not the newest")
    model.showView(.chats); precondition(at(chatB) || at(chatA),"Chats opens a chat")
    model.selectedID=chatA.id
    model.showView(.studios); precondition(at(flyers),"Studios returns to its session")
    model.showView(.chats); precondition(at(chatA),"Chats returns to the chat it was left in")
    model.selectedID=alpha.id
    model.showView(.studios); precondition(at(flyers),"still Flyers")
    model.showingHome=true; model.rememberStudiosOverview()
    model.showView(.projects); precondition(at(alpha),"Projects returns to alpha")
    model.showView(.studios); precondition(!model.showingHome && model.studioSidebarID == studio.id,"Studios opens a session with its sidebar even after visiting the overview")
    model.archive(chatA)
    model.showView(.chats); precondition(at(chatB),"a view whose session is gone falls back to its newest")
    // A project Sidechat has no projectFolder of its own. Restoring it must not
    // switch the section highlight and sidebar back to standalone Chats.
    var r=ConversationRecord(model:"opus",effort:"",personality:.friendly)
    r.title="Project Sidechat";r.sidechatProjectFolder=alpha.record.projectFolder
    r.items=[DisplayItem(kind:.user,text:"sidechat")]
    let sidechat=model.insertSession(r)
    model.selectedID=sidechat.id
    precondition(!model.showingChatsSidebar,"selecting a project Sidechat keeps Projects")
    model.showView(.chats)
    model.showView(.projects)
    precondition(at(sidechat) && !model.showingChatsSidebar,"Projects restores its Sidechat without jumping to Chats")
    let reveal=model.sidebarRevealRequest
    model.showView(.projects)
    precondition(at(sidechat) && model.sidebarRevealRequest == reveal+1,"repeated section clicks reveal the sidebar")
    // Exercise the native segmented toolbar action, rather than just showView.
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:700),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    let toolbar=WindowToolbar(model:model,bridge:ChatToolbarBridge())
    toolbar.install(in:window)
    let group=window.toolbar!.items.compactMap { $0 as? NSToolbarItemGroup }.first!
    func click(_ index:Int) {
        group.setSelected(!group.isSelected(at:index),at:index)
        _=toolbar.perform(NSSelectorFromString("pickView:"),with:group)
    }
    click(2)
    precondition(model.showingChatsSidebar,"native Chats button opens Chats")
    click(0)
    precondition(at(sidechat) && !model.showingChatsSidebar,"native Projects button restores the project Sidechat")
    let before=model.sidebarRevealRequest
    click(0)
    precondition(at(sidechat) && model.sidebarRevealRequest == before+1,"native Projects repeat click reveals instead of toggling")
    for session in model.activeSessions where !session.isDot { session.setArchived(true) }
    model.showView(.projects)
    precondition(model.selectedID == nil && !model.showingHome && !model.showingChatsSidebar && !model.showingStudiosSidebar,"empty Projects clears the old session")
    model.showView(.chats)
    precondition(model.selectedID == nil && model.showingChatsSidebar,"empty Chats retains its sidebar")
    model.showView(.studios)
    precondition(model.selectedID == nil && !model.showingHome && model.showingStudiosSidebar,"empty Studios retains its sidebar")
    // Render the actual narrow column container: section clicks reveal, never hide,
    // its sidebar overlay. No live chat or provider is opened by this fixture.
    window.setContentSize(NSSize(width:600,height:650))
    window.contentView=NSHostingView(rootView:ChatColumns(sidebar:AnyView(Text("Sidebar")),chat:AnyView(Text("Blank session"))).environment(model))
    func hasSidebar(_ view:NSView)->Bool {
        if let probe=view as? ColumnProbe.Probe, probe.role == "sidebar-overlay" { return true }
        return view.subviews.contains(where:hasSidebar)
    }
    model.showView(.projects)
    try await Task.sleep(for:.milliseconds(300))
    precondition(hasSidebar(window.contentView!),"narrow section entry exposes the sidebar")
    model.showView(.projects)
    try await Task.sleep(for:.milliseconds(300))
    precondition(hasSidebar(window.contentView!),"repeated section click keeps the narrow sidebar open")
    print("PASS view memory, native section buttons, project Sidechats, empty sections, and narrow sidebar rendering")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

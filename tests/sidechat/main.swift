@testable import Chatterbox
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-sidechat."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"sidebarProjectsCollapsed":false,"sidebarStudiosCollapsed":false,"sidebarChatsCollapsed":false,"sidebarSectionWeights":"1,1,1"],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    record.title="Chatterbox";record.projectFolder=root.path;record.projectNickname="Chatterbox"
    record.activeBackend = .codex
    record.codex=CodexSettings(threadId:"original-thread",model:"gpt-6.1-sol",effort:"high",fastMode:true,folder:root.path,canEdit:true,mode:"ask",route:"direct")
    record.claudeSessionID="original-claude"
    record.items=[DisplayItem(kind:.assistant,text:"Parent history stays here",phase:.final)]
    let parent=model.insertSession(record)
    parent.draft="Original draft";parent.isRunning=true
    let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
    let original=try encoder.encode(parent.record)
    let window=NSPanel(contentRect:NSRect(x:40,y:90,width:280,height:80),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.contentView=NSHostingView(rootView:NewSidechatControl(parent:parent).environment(model).padding().frame(width:280,height:80))
    window.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(250))
    for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
        let event=NSEvent.mouseEvent(with:type,location:NSPoint(x:140,y:40),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        window.sendEvent(event)
    }
    try await Task.sleep(for:.milliseconds(300))
    guard let side=model.selected, side.id != parent.id, side.record.sidechatOf==parent.id else {throw NSError(domain:"Native Sidechat button failed",code:1)}
    precondition(try! encoder.encode(parent.record)==original && parent.draft=="Original draft" && parent.isRunning)
    precondition(side.items.isEmpty && side.draft.isEmpty && side.record.codex?.threadId==nil && side.record.claudeSessionID==nil && side.record.codex?.forkFrom==nil)
    precondition(side.workingFolder==parent.workingFolder && side.record.codex?.route=="direct" && side.record.codex?.effort=="high" && side.mode==parent.mode && side.record.codex?.fastMode==true)
    precondition(side.record.worktreeOf==nil && side.record.projectFolder==nil && side.record.sidechatProjectFolder==root.path)
    precondition(!model.sidebarChats.contains {$0.id==side.id} && model.sidechats(of:parent).contains {$0.id==side.id})
    let regular=model.newChat(backend:.claude);regular.setTitle("Design question")
    let other=model.newSidechat(of:regular)
    precondition(other.workingFolder==regular.workingFolder && other.record.claudeSessionID==nil)
    let studio=model.newStudio(named:"Creative")!
    let studioParent=model.chats(in:studio).first!
    let studioSide=model.newSidechat(of:studioParent)
    precondition(!model.chats(in:studio).contains {$0.id==studioSide.id})
    let again=model.newSidechat(of:side)
    precondition(again.record.sidechatOf==parent.id)
    let ids=CompanionMapper.chatList(model).groups.flatMap(\.chats).map(\.id)
    precondition(Set(ids).count==ids.count)
    for chat in [side,other,studioSide,again] {precondition(ids.contains(chat.id),"Empty sidechat missing on mobile")}
    var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as! [String:Any]
    for key in ["sidechatOf","sidechatFolder","sidechatProjectFolder"] {legacy.removeValue(forKey:key)}
    let old=try JSONDecoder().decode(ConversationRecord.self,from:JSONSerialization.data(withJSONObject:legacy))
    precondition(old.sidechatOf==nil && old.boundFolder==root.path)
    parent.isRunning=false
    model.selectedID=side.id
    window.setContentSize(NSSize(width:280,height:760))
    window.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
    window.appearance=NSAppearance(named:.darkAqua)
    try await Task.sleep(for:.milliseconds(600))
    let view=window.contentView!
    view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("sidebar.png"))
    model.archive(again)
    precondition(again.record.archivedAt != nil && model.sessions.contains {$0.id==again.id},"Empty ended Sidechat was deleted")
    try await Task.sleep(for:.seconds(1))
    let loaded=AppModel()
    precondition(loaded.sessions.contains {$0.id==side.id && $0.record.sidechatOf==parent.id})
    precondition(loaded.sessions.contains {$0.id==again.id && $0.record.archivedAt != nil})
    model.archive(parent)
    precondition(model.sidebarChats.contains {$0.id==side.id},"Archived parent hid Sidechat")
    print("PASS native create; fresh sessions/same folder/settings; no parent changes; nesting; unique mobile list; old JSON; empty persistence/archive; orphan visibility")
    print("Proof: \(root.appendingPathComponent("sidebar.png").path)")
    window.orderOut(nil)
}
Task {do {try await run();exit(0)} catch {print(error);exit(1)}}
app.run()

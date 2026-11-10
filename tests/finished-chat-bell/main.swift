@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.regular)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-bell."))
 UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyReplies":false,"mobilePushEnabled":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel(), attention=Attention.shared
 func chat(_ title:String,project:Bool=false)->ChatSession {
  var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
  record.title=title
  if project {record.projectFolder=root+"/playcase.gg"}
  record.items=[DisplayItem(kind:.assistant,text:"Finished the review. The report is ready to open.")]
  return model.insertSession(record)
 }
 let a=chat("Website review",project:true),b=chat("Design discussion"),unseen=chat("Never ran"),working=chat("Building a new feature")
 working.record.turnStartedAt=Date().addingTimeInterval(-75);working.isRunning=true;attention.update(working,model:model)
 precondition(attention.workingChats(in:model).map(\.id)==[working.id])
 working.record.archivedAt=Date();precondition(attention.workingChats(in:model).isEmpty);working.record.archivedAt=nil
 model.selectedID=a.id;model.showingSettings=true
 func finish(_ session:ChatSession) {
  session.isRunning=true;attention.update(session,model:model)
  session.isRunning=false;attention.update(session,model:model)
 }
 finish(a);finish(b)
 attention.update(unseen,model:model)
 precondition(Set(attention.finishedChats(in:model).map(\.id))==[a.id,b.id])
 attention.update(b,model:model);precondition(attention.finishedChats(in:model).count==2)
 precondition(Set((AppPreferences.defaults.stringArray(forKey:"macUnreadFinishedChats") ?? []).compactMap(UUID.init(uuidString:)))==[a.id,b.id])
 let restored=Attention();precondition(restored.unread==[a.id,b.id],"Unread did not survive store reload")
 b.record.archivedAt=Date();precondition(attention.finishedChats(in:model).count==1);b.record.archivedAt=nil
 b.isRunning=true;precondition(attention.finishedChats(in:model).count==1);b.isRunning=false
 precondition(!attention.openFinishedChat(UUID(),in:model))
 let workingPanel=NSPanel(contentRect:NSRect(x:80,y:80,width:280,height:200),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 workingPanel.appearance=NSAppearance(named:.darkAqua)
 workingPanel.contentView=NSHostingView(rootView:SidebarActivityStrip().padding(12).environment(model).environment(\.colorScheme,.dark))
 workingPanel.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(400))
 let workingView=workingPanel.contentView!;workingView.layoutSubtreeIfNeeded()
 let workingBitmap=workingView.bitmapImageRepForCachingDisplay(in:workingView.bounds)!
 workingView.cacheDisplay(in:workingView.bounds,to:workingBitmap)
 try workingBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/combined-sidebar.png"))
 workingPanel.close()
 // The toolbar's Session activity popover is gone (Shelby, 2026-11-10): opening a finished chat
 // the way the sidebar strip and menu bar do still reads it.
 precondition(attention.openFinishedChat(a.id,in:model) && model.selectedID==a.id)
 let remaining=attention.finishedChats(in:model)
 precondition(remaining.count==1,"Click did not open/mark the native list row")
 precondition(!model.showingSettings && !attention.unread.contains(model.selectedID!))
 let next=remaining[0]
 precondition(attention.openFinishedChat(next.id,in:model) && model.selectedID==next.id)
 precondition(model.showingChatsSidebar == (next.record.projectFolder==nil))
 precondition(attention.finishedChats(in:model).isEmpty)
 precondition((AppPreferences.defaults.stringArray(forKey:"macUnreadFinishedChats") ?? []).isEmpty)
 precondition(attention.openWorkingChat(working.id,in:model) && model.selectedID==working.id && working.isRunning)
 precondition(!attention.openWorkingChat(a.id,in:model))
 model.showingSettings=true;working.isRunning=false;attention.update(working,model:model)
 precondition(attention.workingChats(in:model).isEmpty && attention.finishedChats(in:model).map(\.id)==[working.id])
 precondition(attention.openFinishedChat(working.id,in:model))
 app.activate(ignoringOtherApps:true)
 try await Task.sleep(for:.milliseconds(200))
 model.selectedID=a.id;model.showingHome=true
 precondition(!attention.isWatching(a),"Hidden chat counted as watched")
 model.showingHome=false;model.showingSettings=false
 if app.isActive { precondition(attention.isWatching(a));finish(a);precondition(!attention.unread.contains(a.id)) }
 print("PASS: completion dedupe, hidden-page attention, persistence, filtering, native list navigation and targeted clearing. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)}}
app.run()

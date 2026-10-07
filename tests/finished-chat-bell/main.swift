@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.regular)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-bell."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyReplies":false,"mobilePushEnabled":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
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
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:430,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua);panel.orderFrontRegardless()
 panel.contentView=NSHostingView(rootView:VStack(alignment:.leading){FinishedChatsBell();FinishedChatsList()}.padding(12).environment(model).environment(\.colorScheme,.dark))
 try await Task.sleep(for:.milliseconds(500))
 let view=panel.contentView!;view.layoutSubtreeIfNeeded()
 let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/finished-list.png"))
 // Actual list row click, local native event coordinates, verified by selected UUID/unread.
 let point=view.convert(NSPoint(x:150,y:view.isFlipped ? 130 : view.bounds.height-130),to:nil)
 for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
  panel.sendEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
 }
 try await Task.sleep(for:.milliseconds(150))
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

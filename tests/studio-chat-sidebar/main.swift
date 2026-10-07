@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-studio-sidebar."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyReplies":false,"mobilePushEnabled":false,"keepMacAwake":false,"macStudioSidebarCards":false,"readerBackground":"black","sidebarTagFilter":"wordpress"],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 let a=Studio(name:"Playcase Studio",folder:root+"/studio-a"),b=Studio(name:"Other Studio",folder:root+"/studio-b")
 model.studios=[a,b]
 func chat(_ title:String,studio:Studio?=nil,project:Bool=false)->ChatSession {
  var r=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic);r.title=title
  r.items=[DisplayItem(kind:.assistant,text:"Fixture reply for \(title)")]
  r.studioID=studio?.id;r.studioFolder=studio?.folder
  if project {r.projectFolder=root+"/project"}
  return model.insertSession(r)
 }
 let first=chat("Package artwork",studio:a),second=chat("Product photos",studio:a),other=chat("Other Studio session",studio:b),project=chat("Unrelated project",project:true),standalone=chat("Standalone chat")
 model.selectedID=first.id
 precondition(model.studioSidebarID==a.id && !model.showingChatsSidebar)
 precondition(Set(model.chats(in:model.sidebarStudio!).map(\.id))==[first.id,second.id])
 model.selectedID=other.id;precondition(model.studioSidebarID==b.id)
 model.selectedID=project.id;precondition(model.studioSidebarID==nil && !model.showingChatsSidebar)
 model.selectedID=standalone.id;precondition(model.studioSidebarID==nil && model.showingChatsSidebar)
 ProjectStudioLinks.shared.set(a.id,for:project.record.projectFolder!)
 precondition(model.openLinkedStudioChat(second.id,for:project.record.projectFolder!) && model.studioSidebarID==a.id)
 first.isRunning=true;Attention.shared.update(first,model:model);first.isRunning=false;Attention.shared.update(first,model:model)
 precondition(Attention.shared.openFinishedChat(first.id,in:model) && model.studioSidebarID==a.id)
 let created=model.newChat(in:a)
 precondition(created.record.studioID==a.id && model.studioSidebarID==a.id)
 model.selectedID=first.id
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:1240,height:780),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua);panel.orderFrontRegardless()
 panel.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
 try await Task.sleep(for:.milliseconds(1000))
 let view=panel.contentView!;view.layoutSubtreeIfNeeded()
 let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/studio-sidebar.png"))
 print("PASS: studio A/B, project/standalone routing, linked shortcut, bell navigation and new-chat membership; native ContentView render: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)}};app.run()

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
 let artwork=URL(fileURLWithPath:root+"/studio-artwork.png")
 let icon=NSWorkspace.shared.icon(forFile:"/System/Applications/Notes.app")
 let representation=NSBitmapImageRep(data:icon.tiffRepresentation!)!
 try representation.representation(using:.png,properties:[:])!.write(to:artwork)
 first.record.items.append(DisplayItem(kind:.assistant,text:"[Latest artwork]("+artwork.path+")",phase:.final))
 model.togglePinnedThread(first)
 model.togglePinnedThread(second)
 model.togglePinnedThread(project)
 model.togglePinnedThread(standalone)
 precondition(SessionOriginLabel.text(for: first, in: model) == "Studio · Playcase Studio")
 precondition(SessionOriginLabel.text(for: project, in: model) == "Project")
 precondition(SessionOriginLabel.text(for: standalone, in: model) == "Chat")
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:1240,height:780),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua);panel.orderFrontRegardless()
 panel.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
 try await Task.sleep(for:.milliseconds(1000))
 let view=panel.contentView!;view.layoutSubtreeIfNeeded()
 let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/studio-sidebar.png"))
 precondition(ThreadThumbnails.shared.images[first.id] != nil)
 var cardPreferences=UserDefaults.standard.volatileDomain(forName:UserDefaults.argumentDomain)
 cardPreferences["macStudioSidebarCards"]=true
 UserDefaults.standard.setVolatileDomain(cardPreferences,forName:UserDefaults.argumentDomain)
 try await Task.sleep(for:.milliseconds(700))
 view.layoutSubtreeIfNeeded()
 let cardBitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:cardBitmap)
 try cardBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/studio-pinned-cards.png"))
 // A previously saved collapsed Projects preference must not hide the list.
 var preferences=UserDefaults.standard.volatileDomain(forName:UserDefaults.argumentDomain)
 preferences["sidebarProjectsCollapsed"]=true
 preferences["macProjectsSidebarCards"]=false
 preferences["sidebarTagFilter"]=""
 UserDefaults.standard.setVolatileDomain(preferences,forName:UserDefaults.argumentDomain)
 model.selectedID=project.id
 try await Task.sleep(for:.milliseconds(700))
 view.layoutSubtreeIfNeeded()
 let projectsBitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:projectsBitmap)
 try projectsBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/projects-expanded.png"))
 preferences["macProjectsSidebarCards"]=true
 UserDefaults.standard.setVolatileDomain(preferences,forName:UserDefaults.argumentDomain)
 try await Task.sleep(for:.milliseconds(700))
 view.layoutSubtreeIfNeeded()
 let originCards=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:originCards)
 try originCards.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/pinned-origin-cards.png"))
 // Chats use the same persisted tags as projects, with their own sidebar filter.
 standalone.toggleTag("Research")
 project.toggleTag("Project only")
 standalone.toggleTag("research")
 precondition(standalone.tags.isEmpty)
 standalone.toggleTag("Research")
 let decoded=try JSONDecoder().decode(ConversationRecord.self,from:JSONEncoder().encode(standalone.record))
 precondition(decoded.tags == ["Research"])
 let untagged=chat("Untagged reference")
 model.selectedID=standalone.id
 var chatPreferences=UserDefaults.standard.volatileDomain(forName:UserDefaults.argumentDomain)
 chatPreferences["macChatsSidebarCards"]=true
 chatPreferences["sidebarChatTagFilter"]="Research"
 chatPreferences["sidebarTagFilter"]="Project only"
 UserDefaults.standard.setVolatileDomain(chatPreferences,forName:UserDefaults.argumentDomain)
 try await Task.sleep(for:.milliseconds(700))
 let savedDecoder=JSONDecoder();savedDecoder.dateDecodingStrategy = .iso8601
 let saved=try savedDecoder.decode(ConversationRecord.self,from:Data(contentsOf:URL(fileURLWithPath:root+"/Conversations/"+standalone.id.uuidString+".json")))
 precondition(saved.tags == ["Research"])
 view.layoutSubtreeIfNeeded()
 let chatsBitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:chatsBitmap)
 try chatsBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/tagged-chat-cards.png"))
 precondition(model.showingChatsSidebar && untagged.tags.isEmpty)
 chatPreferences["macChatsSidebarCards"]=false
 UserDefaults.standard.setVolatileDomain(chatPreferences,forName:UserDefaults.argumentDomain)
 try await Task.sleep(for:.milliseconds(700))
 view.layoutSubtreeIfNeeded()
 let chatsListBitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:chatsListBitmap)
 try chatsListBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/tagged-chat-list.png"))
 print("PASS: studio A/B, project/standalone routing, linked shortcut, bell navigation and new-chat membership; native ContentView render: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)}};app.run()

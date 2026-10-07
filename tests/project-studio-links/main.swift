@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-project-studio."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 let a=Studio(name:"Playcase Studio",folder:root+"/studio-a")
 let b=Studio(name:"Other Studio",folder:root+"/studio-b")
 model.studios=[a,b]
 var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 record.projectFolder=root+"/playcase.gg";record.projectNickname="playcase.gg";record.tags=["wordpress"]
 let project=model.insertSession(record)
 var thread=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 thread.title="Playcase design chat";thread.studioID=a.id;thread.studioFolder=a.folder
 let design=model.insertSession(thread)
 thread.id=UUID();thread.title="Other Studio chat";thread.studioID=b.id;thread.studioFolder=b.folder
 let other=model.insertSession(thread)
 let links=ProjectStudioLinks.shared;let folder=record.projectFolder!
 links.set(a.id,for:folder)
 precondition(ProjectStudioLinks(defaults:AppPreferences.defaults).studioID(for:folder+"/.")==a.id,"Link did not persist/normalize")
 links.set(b.id,for:folder);precondition(model.linkedStudio(for:folder)?.id==b.id,"Replacement failed")
 links.set(a.id,for:folder)
 let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
 let records=try encoder.encode(model.sessions.map(\.record))
 precondition(!model.openLinkedStudioChat(other.id,for:folder),"Opened a chat in an unrelated Studio")
 precondition(model.openLinkedStudioChat(design.id,for:folder) && model.selectedID==design.id,"Linked chat did not open")
 let afterRecords=try encoder.encode(model.sessions.map(\.record))
 precondition(afterRecords==records,"Linking/opening changed chat records")
 model.studios[0].archivedAt=Date();precondition(model.linkedStudio(for:folder)==nil,"Archived Studio still reachable")
 model.studios[0].archivedAt=nil
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:580,height:470),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua);panel.orderFrontRegardless()
 func save(_ name:String) throws {
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(name+".png"))
 }
 panel.contentView=NSHostingView(rootView:VStack(alignment:.leading,spacing:20){
  Text("Linked project: Cards and List").font(.headline)
  HStack(spacing:16){ThreadCard(session:project) {}.frame(width:250);ThreadCard(session:project,selected:true){}.frame(width:250)}
  SidebarRow(session:project,shortcut:nil).padding(12).background(Color.primary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
 }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color.black).environment(model).environment(\.colorScheme,.dark))
 try await Task.sleep(for:.milliseconds(700));try save("linked-card-list")
 links.set(nil,for:folder)
 precondition(model.linkedStudio(for:folder)==nil && ProjectStudioLinks(defaults:AppPreferences.defaults).studioID(for:folder)==nil,"Unlink failed")
 try await Task.sleep(for:.milliseconds(350));try save("unlinked-card-list")
 print("PASS: link persists, normalizes, replaces and unlinks; archive guard and Studio-only routing; records preserved. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)}}
app.run()

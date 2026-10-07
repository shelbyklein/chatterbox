@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-notes."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model = AppModel()
 var project = ConversationRecord(model:"gpt-6.1-sol", effort:"medium", personality:.pragmatic)
 project.activeBackend = .codex; project.projectFolder = root+"/project"; project.title="Project"
 let session = model.insertSession(project)
 var chat = ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic);chat.title="Other chat"
 let other = model.insertSession(chat)
 let store = PinnedNotesStore.shared, scope = PinnedNotesStore.scope(for:project), otherScope = PinnedNotesStore.scope(for:chat)
 var worktree = project;worktree.projectFolder=root+"/worktree";worktree.worktreeOf=project.projectFolder
 precondition(PinnedNotesStore.scope(for:worktree)==scope)
 precondition(scope != otherScope)
 let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
 let before=try encoder.encode(model.sessions.map(\.record))
 store.setDraft("  ",for:scope);precondition(!store.add(for:scope))
 store.setDraft("Check deployment checklist before publishing.",for:scope);precondition(store.add(for:scope))
 let first=store.notes[scope]!.first!.id
 store.setDraft("Keep the current logo.",for:scope);precondition(store.add(for:scope))
 store.setDraft("Unfinished project note",for:scope)
 store.setDraft("Separate chat note",for:otherScope);precondition(store.add(for:otherScope))
 let reloaded=PinnedNotesStore(defaults:AppPreferences.defaults)
 precondition(reloaded.notes[scope]?.first?.text=="Keep the current logo.")
 precondition(reloaded.notes[scope]?.count==2 && reloaded.notes[otherScope]?.count==1)
 precondition(reloaded.drafts[scope]=="Unfinished project note" && reloaded.drafts[otherScope]==nil)
 store.remove(first,for:scope);precondition(store.notes[scope]?.count==1 && store.notes[otherScope]?.count==1)
 let after = try encoder.encode(model.sessions.map(\.record)); precondition(after==before)
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:1360,height:800),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua);panel.orderFrontRegardless()
 func save(_ name:String) throws {
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(name+".png"))
 }
 panel.contentView=NSHostingView(rootView:ChatView(session:session).environment(model).environment(\.colorScheme,.dark))
 try await Task.sleep(for:.milliseconds(650));try save("collapsed-gutter")
 // Click the actual gutter icon in the full ChatView, using local window events.
 let hosting=panel.contentView!
 let point=hosting.convert(NSPoint(x:32,y:hosting.isFlipped ? 32 : hosting.bounds.height-32),to:nil)
 for kind in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
  let event=NSEvent.mouseEvent(with:kind,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  panel.sendEvent(event)
 }
 try await Task.sleep(for:.milliseconds(450));try save("expanded-gutter")
 session.isRunning=true;other.isRunning=true
 panel.contentView=NSHostingView(rootView:HStack(spacing:20){
  ChatNotes(scope:scope,project:true,expanded:true).frame(width:280)
  ThreadCard(session:session){}.frame(width:250)
  ThreadCard(session:other){}.frame(width:250)
 }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color.black).environment(model).environment(\.colorScheme,.dark))
 try await Task.sleep(for:.milliseconds(650));try save("notes-and-spinners")
 session.isRunning=false;other.isRunning=false
 print("PASS: scoped persistence, draft restore, order, blank rejection, deletion and unchanged transcripts. Native gutter click/render and provider spinners: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)}}
app.run()

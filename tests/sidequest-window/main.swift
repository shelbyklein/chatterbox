@testable import Chatterbox
import AppKit
import SwiftUI
// A chat with a sidequest open: the sidequest floats in its bottom right, then shrinks to a
// bubble, then closes. No agents run. Evidence: open.png, bubble.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func shot(_ window:NSWindow,_ name:String,_ root:URL) throws {
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-sidequest-window."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    var record=ConversationRecord(model:"opus",effort:"medium",personality:.friendly)
    record.title="Event Logos";record.activeBackend = .claude
    record.items=[DisplayItem(kind:.user,text:"Let's do a ribbon logo for the spring event."),
                  DisplayItem(kind:.assistant,text:"Here's the direction: a looping ribbon in the brand red, with the date set in the condensed face. I'll have Codex render a few options.",phase:.final)]
    let parent=model.insertSession(record)
    var quest=ChatSession.sidequestRecord(of:parent,anchor:parent,number:1,backend:.codex,task:"Render four ribbon logo options")
    quest.pendingHandoff=nil
    quest.items=[DisplayItem(kind:.user,text:"Render four ribbon logo options"),
                 DisplayItem(kind:.tool,text:"Generating image 2 of 4")]
    let side=model.insertSession(quest)
    side.isRunning=true
    model.selectedID=parent.id
    precondition(model.sidechats(of:parent).contains {$0.id==side.id},"the sidequest sits under its chat")
    let window=NSWindow(contentRect:NSRect(x:40,y:60,width:1100,height:760),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:ChatView(session:parent).environment(model).environment(\.colorScheme,.dark).frame(width:1100,height:760))
    window.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(900))
    try shot(window,"open.png",root)
    precondition(model.selectedID==parent.id,"showing the sidequest doesn't leave the chat")
    UserDefaults.standard.set(true,forKey:"sidequestWindowCollapsed-"+side.id.uuidString)
    try await Task.sleep(for:.milliseconds(500))
    try shot(window,"bubble.png",root)
    UserDefaults.standard.removeObject(forKey:"sidequestWindowCollapsed-"+side.id.uuidString)
    // In card view the sidequest sits inside its chat's card.
    precondition(model.showsInsideParentCard(side) && model.sidequests(of:parent).map(\.id)==[side.id],"the sidequest belongs inside its chat's card")
    let card=NSWindow(contentRect:NSRect(x:40,y:60,width:260,height:240),styleMask:[.titled],backing:.buffered,defer:false)
    card.appearance=NSAppearance(named:.darkAqua)
    card.contentView=NSHostingView(rootView:ThreadCard(session:parent){}.environment(model).environment(\.colorScheme,.dark).frame(width:220).padding(20).background(Color(white:0.1)))
    card.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(700))
    try shot(card,"card.png",root)
    card.close()
    side.isRunning=false
    window.close()
    print("PASS sidequest window renders open and as a bubble. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

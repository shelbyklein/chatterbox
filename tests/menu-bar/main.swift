@testable import Chatterbox
import AppKit
import SwiftUI
// The menu bar panel with a chat waiting on you, a new reply, one working and a recent one.
// No agents run. Evidence: panel.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-menu-bar."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    let replyID=UUID()
    UserDefaults.standard.set([replyID.uuidString],forKey:"macUnreadFinishedChats")
    defer { UserDefaults.standard.removeObject(forKey:"macUnreadFinishedChats") }
    let model=AppModel()
    func chat(_ title:String,_ backend:Backend,_ items:[DisplayItem],id:UUID=UUID()) -> ChatSession {
        var r=ConversationRecord(model:"opus",effort:"",personality:.friendly);r.id=id;r.title=title;r.activeBackend=backend;r.items=items
        if backend == .codex {r.codex=CodexSettings(folder:root.path,canEdit:false,mode:"readOnly")}
        return model.insertSession(r)
    }
    var question=DisplayItem(kind:.questions,text:"Which plugin first?");question.approvalState = .pending
    _ = chat("SDHQ",.claude,[DisplayItem(kind:.user,text:"Update the plugins"),question])
    let reply=chat("Spoolside",.claude,[DisplayItem(kind:.user,text:"Ship it"),DisplayItem(kind:.assistant,text:"Both changes are live.",phase:.final)],id:replyID)
    let working=chat("Event Logos",.codex,[DisplayItem(kind:.user,text:"Render four options")])
    working.isRunning=true
    _ = chat("Vispix",.claude,[DisplayItem(kind:.user,text:"Hi"),DisplayItem(kind:.assistant,text:"Hello",phase:.final)])
    precondition(Attention.shared.finishedChats(in:model).contains {$0.id==reply.id},"the reply counts as new")
    let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:300,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    panel.appearance=NSAppearance(named:.darkAqua)
    panel.contentView=NSHostingView(rootView:MenuBarPanel(model:model).environment(\.colorScheme,.dark).background(Color(white:0.14)).fixedSize())
    panel.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(800))
    let view=panel.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("panel.png"))
    working.isRunning=false
    print("PASS menu bar panel renders. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

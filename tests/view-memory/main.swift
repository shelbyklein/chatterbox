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
    model.showView(.studios); precondition(model.showingHome,"Studios returns to its overview when that's where it was left")
    model.archive(chatA)
    model.showView(.chats); precondition(at(chatB),"a view whose session is gone falls back to its newest")
    print("PASS each view returns to the session it was last in")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

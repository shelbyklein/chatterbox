@testable import Chatterbox
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-project-studio."))
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let guide=root.appendingPathComponent("design.md")
    try "Existing design guide\n".write(to:guide,atomically:true,encoding:.utf8)
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"sidebarProjectsCollapsed":false,"sidebarStudiosCollapsed":false,"sidebarChatsCollapsed":false,"sidebarSectionWeights":"0.3,2.4,0.3"],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    var record=ConversationRecord(model:"opus",effort:"medium",personality:.friendly)
    record.projectFolder=root.path;record.title="Galley";record.projectNickname="Galley"
    record.claudeSessionID="keep-claude";record.claudeTasks=[ClaudeTask(id:"1",subject:"Keep tasks",status:"pending")]
    record.activeBackend = .codex
    record.codex=CodexSettings(threadId:"keep-codex",model:"gpt-6.1-sol",effort:"high",fastMode:true,folder:root.path,canEdit:true,mode:"ask",route:"direct")
    record.items=[DisplayItem(kind:.assistant,text:"Existing project history",phase:.final)]
    let parent=model.insertSession(record);parent.draft="Keep draft"
    let pin=Pin(title:"Docs",kind:.file,target:root.path,place:"project:"+root.path)
    PinStore.shared.add(pin)
    var worktreeRecord=record;worktreeRecord.id=UUID();worktreeRecord.title="Isolated work";worktreeRecord.projectNickname="isolated";worktreeRecord.projectFolder=root.appendingPathComponent("worktree").path;worktreeRecord.worktreeOf=root.path;worktreeRecord.worktreeBranch="isolated"
    let worktree=model.insertSession(worktreeRecord);worktree.isRunning=true
    let side=model.newSidechat(of:parent), branchSide=model.newSidechat(of:worktree)
    parent.isRunning=true
    precondition(model.convertProjectToStudio(parent,named:"Galley") == nil)
    parent.isRunning=false
    var missingRecord=record;missingRecord.id=UUID();missingRecord.projectFolder=root.appendingPathComponent("missing").path
    let missing=model.insertSession(missingRecord)
    precondition(model.convertProjectToStudio(missing,named:"Missing") == nil)
    precondition(!FileManager.default.fileExists(atPath:missingRecord.projectFolder!))
    model.delete(missing)
    let ids=[parent.id,worktree.id,side.id,branchSide.id]
    let items=parent.items.map(\.id)
    let studio=model.convertProjectToStudio(parent,named:"Galley")!
    precondition(studio.folder==root.path && parent.workingFolder==root.path && parent.record.projectFolder==nil && parent.record.studioID==studio.id)
    precondition(parent.id==ids[0] && parent.items.map(\.id)==items && parent.draft=="Keep draft" && parent.record.claudeSessionID=="keep-claude" && parent.record.codex?.threadId=="keep-codex" && parent.record.claudeTasks?.count==1)
    precondition(parent.record.codex?.effort=="high" && parent.record.codex?.fastMode==true && parent.record.codex?.route=="direct")
    precondition(worktree.workingFolder==worktreeRecord.projectFolder && worktree.record.worktreeOf==root.path && worktree.record.studioID==studio.id && worktree.isRunning)
    precondition(side.record.studioID==studio.id && branchSide.record.studioID==studio.id && side.workingFolder==root.path && branchSide.workingFolder==worktree.workingFolder)
    precondition(parent.record.convertedProjectFolder==root.path && model.newSidechat(of:parent).record.sidechatProjectFolder==root.path)
    precondition(try! String(contentsOf:guide,encoding:.utf8)=="Existing design guide\n")
    precondition(PinStore.shared.pins(in:PinPlace(key:"studio:"+studio.id.uuidString,name:studio.name)).contains {$0.id==pin.id})
    precondition(model.session(boundTo:root.path)?.id==parent.id)
    precondition(!model.sidebarProjects.contains {$0.id==parent.id})
    let fork=model.fork(parent)!
    precondition(fork.record.convertedProjectFolder==nil && fork.record.sidechatProjectFolder==root.path)
    let listed=CompanionMapper.chatList(model).groups.flatMap(\.chats).map(\.id)
    precondition(Set(listed).count==listed.count)
    precondition(listed.firstIndex(of:parent.id)! < listed.firstIndex(of:worktree.id)!)
    for id in ids {precondition(listed.contains(id),"Converted descendant hidden")}
    precondition(model.convertProjectToStudio(worktree,named:"Don't convert worktrees") == nil)
    model.selectedID=parent.id
    let window=NSPanel(contentRect:NSRect(x:30,y:80,width:300,height:760),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark));window.appearance=NSAppearance(named:.darkAqua);window.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(600))
    let view=window.contentView!;view.layoutSubtreeIfNeeded();let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("converted.png"))
    try await Task.sleep(for:.seconds(1))
    let reloaded=AppModel()
    precondition(reloaded.studios.contains {$0.id==studio.id && $0.folder==root.path})
    for id in ids {precondition(reloaded.sessions.contains {$0.id==id && $0.record.studioID==studio.id})}
    // Existing Studio membership: both cwd choices, no new Studio, no file moves.
    let existing=model.newStudio(named:"Existing Studio")!
    let existingPin=Pin(title:"Existing pin",kind:.file,target:existing.folder,place:"studio:"+existing.id.uuidString)
    PinStore.shared.add(existingPin)
    for keep in [true,false] {
        let project=root.appendingPathComponent(keep ? "keep-project" : "shared-project")
        try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
        let marker=project.appendingPathComponent("original.txt")
        try "untouched".write(to:marker,atomically:true,encoding:.utf8)
        var r=record;r.id=UUID();r.projectFolder=project.path;r.codex?.folder=project.path
        let thread=model.insertSession(r);thread.draft="Saved draft"
        var childRecord=r;childRecord.id=UUID();childRecord.projectFolder=project.appendingPathComponent("branch").path;childRecord.worktreeOf=project.path
        let child=model.insertSession(childRecord);child.isRunning=true
        let temporary=model.newSidechat(of:thread)
        let projectPin=Pin(title:"Project pin",kind:.file,target:marker.path,place:"project:"+project.path)
        PinStore.shared.add(projectPin)
        let count=model.studios.count
        thread.isRunning=true
        precondition(model.convertProjectToStudio(thread,into:existing,keepFolder:keep)==nil)
        thread.isRunning=false
        thread.isRestartingThread=true
        precondition(model.convertProjectToStudio(thread,into:existing,keepFolder:keep)==nil)
        thread.isRestartingThread=false
        precondition(model.convertProjectToStudio(thread,into:existing,keepFolder:keep)?.id==existing.id)
        precondition(model.studios.count==count)
        precondition(thread.workingFolder==(keep ? project.path : existing.folder))
        precondition(thread.record.studioWorkingFolder==(keep ? project.path : nil))
        precondition(thread.record.convertedProjectFolder==project.path)
        precondition(thread.convertedProjectScope==(keep ? project.path : nil))
        precondition(thread.record.claudeSessionID==(keep ? "keep-claude" : nil))
        precondition(thread.record.codex?.threadId=="keep-codex" && thread.record.codex?.folder==thread.workingFolder)
        precondition(thread.items.map(\.id)==r.items.map(\.id) && thread.draft=="Saved draft")
        precondition(child.isRunning && child.workingFolder==childRecord.projectFolder && temporary.workingFolder==project.path)
        precondition(child.record.studioID==existing.id && temporary.record.studioID==existing.id)
        precondition(model.worktrees(of:thread).contains {$0.id==child.id})
        precondition(model.newSidechat(of:thread).record.sidechatProjectFolder==(keep ? project.path : nil))
        precondition(try! String(contentsOf:marker,encoding:.utf8)=="untouched")
        let pins=PinStore.shared.pins(in:PinPlace(key:"studio:"+existing.id.uuidString,name:existing.name))
        precondition(pins.contains {$0.id==existingPin.id} && pins.contains {$0.id==projectPin.id})
        try await Task.sleep(for:.seconds(1))
        let restored=AppModel().sessions.first {$0.id==thread.id}!
        precondition(restored.workingFolder==thread.workingFolder && restored.record.studioID==existing.id)
    }
    var plainRecord=record;plainRecord.id=UUID();plainRecord.projectFolder=nil
    let plain=model.insertSession(plainRecord)
    precondition(model.joinStudio(plain,studio:existing,keepFolder:true))
    precondition(plain.workingFolder==root.path && plain.record.claudeSessionID=="keep-claude")
    precondition(model.joinStudio(plain,studio:existing,keepFolder:false))
    precondition(plain.workingFolder==existing.folder && plain.record.claudeSessionID==nil)
    var archived=existing;archived.archivedAt=Date()
    let unused=model.insertSession(record)
    precondition(model.convertProjectToStudio(unused,into:archived)==nil)
    model.delete(unused)
    var uiRecord=record;uiRecord.id=UUID();uiRecord.projectFolder=root.path
    let uiThread=model.insertSession(uiRecord)
    window.contentView=NSHostingView(rootView:StudioDestinationSheet(source:uiThread,initialName:"",destination:existing.id).environment(model).environment(\.colorScheme,.dark))
    window.setContentSize(NSSize(width:528,height:500))
    try await Task.sleep(for:.milliseconds(600))
    let chooser=window.contentView!;chooser.layoutSubtreeIfNeeded();let chooserRep=chooser.bitmapImageRepForCachingDisplay(in:chooser.bounds)!
    chooser.cacheDisplay(in:chooser.bounds,to:chooserRep)
    try chooserRep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("existing-studio-chooser.png"))
    // Click the production SwiftUI Move control with native mouse events.
    let point=NSPoint(x:StudioDestinationDebug.moveFrame.midX-StudioDestinationDebug.rootOrigin.x,y:chooser.bounds.height-(StudioDestinationDebug.moveFrame.midY-StudioDestinationDebug.rootOrigin.y))
    for kind in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
        let event=NSEvent.mouseEvent(with:kind,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        app.postEvent(event,atStart:false)
    }
    try await Task.sleep(for:.milliseconds(300))
    precondition(uiThread.record.studioID==existing.id && uiThread.workingFolder==root.path,"Native Move didn't join the selected Studio")
    precondition(model.convertProjectToStudio(parent,into:existing)?.id==existing.id)
    precondition(parent.workingFolder==root.path && model.worktrees(of:parent).contains {$0.id==worktree.id})
    print("PASS native Move control joins existing Studio")
    print("PASS existing Studio: keep/shared folder, reload, history/draft/IDs, active descendants, pins merged, no files moved; ordinary thread cwd choices")
    let other=model.newStudio(named:"Elsewhere")!
    model.move(parent,to:other)
    precondition(parent.record.convertedProjectFolder==nil,"Old project scope remained after moving away")
    print("PASS same-folder conversion; provider IDs/tasks/history/draft/settings preserved; running worktree untouched; all descendants listed once; design preserved; reload; stale scope cleared")
    print("Proof: \(root.appendingPathComponent("converted.png").path)")
    window.orderOut(nil)
}
Task {do {try await run();exit(0)} catch {print(error);exit(1)}}
app.run()

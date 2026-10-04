import Foundation

#if CHATTERBOX_HEADLESS
// Compatibility surface for the existing companion API; this is not a UI model.
typealias AppModel=DaemonContext
typealias Attention=DaemonAttention
@MainActor final class DaemonAttention {
    static let shared=DaemonAttention()
    func dotUnreadCount(_ session:ChatSession)->Int {
        let seen=AppPreferences.defaults.string(forKey:"dotSeenItem").flatMap(UUID.init(uuidString:))
        guard let seen,let i=session.items.firstIndex(where:{$0.id==seen}) else{return 0}
        return session.items.dropFirst(i+1).filter{$0.kind == .assistant && $0.phase == .final}.count
    }
}
@MainActor final class DaemonContext {
    let runtime:ConversationRuntime
    var selectedID:UUID?
    init(_ runtime:ConversationRuntime){self.runtime=runtime}
    var sessions:[ChatSession]{runtime.sessions}
    var activeSessions:[ChatSession]{sessions.filter{$0.record.archivedAt==nil}}
    var dot:ChatSession?{runtime.assistant}
    var dotName:String{dot?.title ?? "Golem"}
    var companionListRevision:Int{runtime.state.sequence}
    func companionRevision(of id:UUID)->Int{runtime.state.revisions[id.uuidString] ?? 0}
    var sidebarProjects:[ChatSession]{activeSessions.filter{$0.record.projectFolder != nil && $0.record.worktreeOf==nil && !$0.isDot}.sorted{$0.record.updatedAt>$1.record.updatedAt}}
    var sidebarChats:[ChatSession]{activeSessions.filter{$0.record.projectFolder==nil && $0.record.studioID==nil && !$0.isDot}}
    var activeStudios:[Studio]{runtime.studios.filter{$0.archivedAt==nil}}
    func studio(_ id:UUID)->Studio?{runtime.studios.first{$0.id==id}}
    func chats(in studio:Studio)->[ChatSession]{activeSessions.filter{$0.record.studioID==studio.id && !$0.isDot}}
    func worktrees(of project:ChatSession)->[ChatSession]{activeSessions.filter{$0.record.worktreeOf==project.record.projectFolder}}
    func newChat(backend:Backend?=nil) throws ->ChatSession {
        var r=ConversationRecord(model:AppPreferences.defaults.string(forKey:"defaultModel") ?? "default",effort:AppPreferences.defaults.string(forKey:"defaultEffort") ?? "",personality:.friendly)
        r.activeBackend=backend ?? Backend(rawValue:AppPreferences.defaults.string(forKey:"defaultBackend") ?? "") ?? .claude
        if r.backend == .codex {r.codex=CodexSettings(folder:RuntimePaths.data.path,canEdit:false,mode:PermissionModes.defaultCodex)}
        return try runtime.insert(r)
    }
    func newChat(in studio:Studio,backend:Backend?=nil) throws ->ChatSession {let s=try newChat(backend:backend);s.record.studioID=studio.id;s.record.studioFolder=studio.folder;s.onChange?(s);try runtime.flush();return s}
    func ensureDot() throws ->ChatSession{try runtime.ensureAssistant()}
    func archive(_ s:ChatSession){s.shutdown();s.setArchived(true)}
    func renameDot(_ title:String){dot?.setTitle(title);dot?.restartClaudeForNewTools()}
    func setInstructions(_ text:String,forStudio id:UUID){var all=runtime.studios;guard let i=all.firstIndex(where:{$0.id==id}) else{return};all[i].instructions=text;try? runtime.updateStudios(all)}
    func canFork(_ s:ChatSession)->Bool{!s.isRunning && !s.isDot && s.record.projectFolder==nil && !s.items.isEmpty}
    func fork(_ s:ChatSession)->ChatSession?{
        guard canFork(s) else{return nil}
        var r=s.record;r.id=UUID();r.title += " (fork)";r.createdAt=Date();r.updatedAt=Date();r.archivedAt=nil;r.forkedFrom=s.id
        r.isDot=nil;r.sentDotName=nil;r.dotFollowing=nil;r.currentIssue=nil;r.turnStartedAt=nil;r.backgroundTasks=nil;r.claudeHost=nil;r.codexHost=nil
        r.claudeForkPending=r.claudeSessionID != nil ? true:nil
        if let thread=r.codex?.threadId{r.codex?.forkFrom=thread;r.codex?.threadId=nil}
        for i in r.items.indices{r.items[i].queued=nil;if r.items[i].approvalState == .pending{r.items[i].approvalState = .expired}}
        r.items.append(DisplayItem(kind:.notice,text:"Forked from \(s.title)."))
        return try? runtime.insert(r)
    }
    func startDotComputer() async{await DotComputer.shared.start();dot?.restartClaudeForNewTools()}
    func setUpDotComputer() async{await DotComputer.shared.setUp();dot?.restartClaudeForNewTools()}
    func stopDotComputer() async{await DotComputer.shared.stop();dot?.restartClaudeForNewTools()}
    func recordAssistantDecision(_ title:String,detail:String?,chat:ChatSession?){try? runtime.recordAssistantNote(title:title,detail:detail,chat:chat?.id)}
}
#endif

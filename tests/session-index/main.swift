@testable import Chatterbox
import AppKit
// AppModel's session index: Sidechats, sidequests and worktrees are looked up, not scanned per
// thread (the sidebar asks for every thread's family on each draw); the index is rebuilt only
// when the sessions or a session's place change.
setbuf(stdout, nil)
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL \(message)"); exit(1) }
    print("PASS \(message)")
}
@MainActor func run() throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-session-index."))
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    let model = AppModel()
    let baseline = model.activeSessions.count   // a fresh model opens one chat of its own
    func record(_ title: String) -> ConversationRecord {
        var record = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
        record.title = title
        return record
    }
    var projects: [ChatSession] = []
    for i in 0..<300 {
        var r = record("Project \(i)"); r.projectFolder = root.appendingPathComponent("p\(i)").path
        projects.append(model.insertSession(r))
    }
    var sidechats: [UUID: [ChatSession]] = [:]
    for i in 0..<100 {
        let parent = projects[i % 50]
        sidechats[parent.id, default: []].append(model.newSidechat(of: parent))
    }
    for i in 0..<60 {
        var r = record("Branch \(i)"); r.projectFolder = root.appendingPathComponent("wt\(i)").path
        r.worktreeOf = projects[i].record.projectFolder; r.worktreeBranch = "b\(i)"
        _ = model.insertSession(r)
    }
    let allChats = 300 + 100 + 60
    check(model.activeSessions.count == baseline + allChats, "\(allChats) open sessions besides the \(baseline) the model started with")
    check(projects.prefix(50).allSatisfy { Set(model.sidechats(of: $0).map(\.id)) == Set(sidechats[$0.id]!.map(\.id)) }, "every project's Sidechats are found")
    check(projects[50...].allSatisfy { model.sidechats(of: $0).isEmpty }, "projects without Sidechats have none")
    check(model.worktrees(of: projects[0]).count == 1 && model.worktrees(of: projects[0])[0].record.worktreeBranch == "b0", "a project's worktree is found")
    check(model.worktrees(of: projects[100]).isEmpty, "a project without worktrees has none")
    check(model.sidechats(of: projects[0]).first!.lastActivity >= model.sidechats(of: projects[0]).last!.lastActivity, "Sidechats come newest activity first")

    // Drawing: every thread's family, twenty times over, as the sidebar and Home do.
    let rebuilt = model.sessionIndexRebuilds
    let started = Date()
    var families = 0
    for _ in 0..<20 {
        for project in projects {
            var family = [project] + model.sidechats(of: project)
            for branch in model.worktrees(of: project) { family += [branch] + model.sidechats(of: branch) }
            families += family.filter { !model.showsInsideParentCard($0) }.count
        }
        _ = model.pinnedThreads
    }
    let elapsed = Date().timeIntervalSince(started)
    // Sidechats show inside their parent's card (showsInsideParentCard), so a family drawn is
    // the project and its worktrees.
    check(families == 20 * (300 + 60), "families cover every project and worktree once per pass (\(families / 20))")
    check(model.sessionIndexRebuilds == rebuilt, "drawing 6000 families didn't rebuild the index (rebuilds: \(model.sessionIndexRebuilds))")
    print("INFO 6000 families in \(Int(elapsed * 1000)) ms")
    check(elapsed < 2, "6000 families take under 2 s")

    // Changes to a session's place rebuild it; other changes don't.
    let child = sidechats[projects[0].id]![0]
    var before = model.sessionIndexRebuilds
    child.setArchived(true)
    check(!model.sidechats(of: projects[0]).contains { $0 === child }, "an archived Sidechat leaves its parent's list")
    check(model.sessionIndexRebuilds == before + 1, "archiving rebuilt the index once")
    child.setArchived(false)
    check(model.sidechats(of: projects[0]).contains { $0 === child }, "unarchived, it's back")
    child.record.sidechatOf = projects[1].id
    check(model.sidechats(of: projects[1]).contains { $0 === child } && !model.sidechats(of: projects[0]).contains { $0 === child }, "a Sidechat moved to another parent is listed there")
    let fresh = model.newSidechat(of: projects[2])
    check(model.sidechats(of: projects[2]).first === fresh, "a new Sidechat is listed at once")
    before = model.sessionIndexRebuilds
    projects[4].record.title = "Renamed"
    projects[4].record.items.append(DisplayItem(kind: .assistant, text: "Done.", phase: .final))
    _ = model.sidechats(of: projects[4])
    check(model.sessionIndexRebuilds == before, "a title or transcript change doesn't rebuild the index")
    model.pinnedThreadIDs = [projects[3].id, projects[7].id]
    check(model.pinnedThreads.map(\.id) == [projects[3].id, projects[7].id], "pinned threads come from the index, in pin order")
    model.archive(projects[7])
    check(model.pinnedThreads.map(\.id) == [projects[3].id], "an archived pinned thread drops out")
    check(model.showsInsideParentCard(fresh) && !model.hasVisibleSidechatParent(projects[2]), "parent lookups answer from the index")
    let groups = HomeThreads.groups(model)
    check(groups.first?.id == "projects" && groups.first!.threads.count >= 300, "Home's groups draw from the same index (\(groups.first!.threads.count) project threads)")
    print("All session index checks passed.")
}
Task { @MainActor in do { try run(); exit(0) } catch { print("FAIL \(error)"); exit(1) } }
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

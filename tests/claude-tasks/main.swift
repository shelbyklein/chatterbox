import AppKit
@testable import ChatterboxTestEngine

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

@MainActor func run() {
    let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
    precondition(root.hasPrefix("/tmp/chatterbox-claude-tasks."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"keepMacAwake":false,"mobilePushConfigured":false],forName:UserDefaults.argumentDomain)
    let session = AppModel().newChat(backend: .claude)
    func create(_ id: String, _ subject: String) {
        session.claudeTaskResult("TaskCreate", input: ["subject": .string(subject)], result: "Task #\(id) created successfully: \(subject)")
    }
    func update(_ fields: [String: JSON]) { session.claudeTaskToolUsed("TaskUpdate", input: .object(fields), useID: "u") }
    func steps() -> [PlanStep] { session.record.items.last(where: { $0.kind == .plan })?.planSteps ?? [] }
    func names() -> [String] { (session.record.claudeTasks ?? []).map(\.subject) }
    func check(_ ok: Bool, _ label: String) { precondition(ok, "FAIL \(label)"); print("PASS \(label)") }
    func reset() {
        session.record.claudeTasks = nil
        session.record.items.removeAll()
        session.claudePlanItem = nil
    }

    create("1", "First"); create("2", "Second")
    check(steps().map(\.step) == ["First", "Second"], "create shows both tasks")

    update(["taskId": "1", "status": "deleted", "subject": "Deleted title"])
    check(names() == ["Second"] && steps().map(\.step) == ["Second"], "delete first with subject leaves second's name")

    update(["taskId": "2", "status": "deleted"])
    check(names().isEmpty && !session.record.items.contains { $0.kind == .plan } && session.claudePlanItem == nil, "delete last task clears the plan")

    reset()
    create("1", "A"); create("2", "B"); create("3", "C")
    update(["taskId": "2", "status": "deleted", "subject": "Gone"])
    check(names() == ["A", "C"], "delete middle with subject")
    update(["taskId": "3", "status": "deleted"])
    check(names() == ["A"] && steps().count == 1, "delete last of several")

    update(["taskId": "99", "status": "deleted", "subject": "Ghost"])
    check(names() == ["A"], "delete unknown id is a no-op")
    update(["taskId": "99", "status": "completed"])
    check(names() == ["A"], "status-only update of unknown id is a no-op")
    update(["taskId": 1, "status": "in_progress"])
    check(session.record.claudeTasks?.first?.status == "in_progress" && steps().first?.status == "in_progress", "status update by numeric id")
    update(["taskId": "1", "status": "completed", "subject": "A2"])
    check(session.record.claudeTasks?.first?.status == "completed" && names() == ["A2"], "status plus subject by id")
    update(["taskId": "1", "subject": ""])
    check(names() == ["A2"], "empty subject ignored")
    update(["taskId": "1", "status": "bogus"])
    check(session.record.claudeTasks?.first?.status == "pending", "unknown status becomes pending")

    reset()
    create("10", "Ten"); create("2", "Two"); create("2", "Two again")
    check(steps().map(\.step) == ["Two", "Ten"], "plan is ordered by numeric id; duplicate create ignored")
    update(["taskId": "2", "status": "deleted"])
    check(steps().map(\.step) == ["Ten"], "delete in reordered list hits the right task")

    reset()
    session.record.claudeTasks = [ClaudeTask(id: "1", subject: "X", status: "pending"), ClaudeTask(id: "1", subject: "Y", status: "pending"), ClaudeTask(id: "2", subject: "Z", status: "pending")]
    update(["taskId": "1", "status": "deleted", "subject": "Q"])
    check(names() == ["Z"], "duplicate ids all deleted, neighbour untouched")

    reset()
    update(["taskId": "7", "subject": "Fresh", "status": "in_progress"])
    check(names() == ["Fresh"] && steps().first?.status == "in_progress", "update of unknown id with subject creates it")
    print("ALL PASS")
}
MainActor.assumeIsolated { run() }
exit(0)

import Foundation
import Darwin
// The always-on Desk's inbox (plans/always-on-desk.md): duplicates dropped; a burst is one
// run; one run at a time, with events that arrive mid-run in the next; a failed run retries,
// then gives up; a crash mid-run is retried after a restart.
/// A fake ClickUp: answers the watcher's requests from `FakeClickUp.tasks` and `.comments`.
final class FakeClickUp: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var tasks: [[String: Any]] = []
    nonisolated(unsafe) static var comments: [String: [[String: Any]]] = [:]
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fake-clickup.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requests.append(url.path + "?" + (url.query ?? ""))
        var body: Any = [:]
        if url.path.hasSuffix("/comment") {
            let id = url.pathComponents[url.pathComponents.count - 2]
            body = ["comments": Self.comments[id] ?? []]
        } else {
            let since = Int64(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "date_updated_gt" }?.value ?? "0") ?? 0
            body = ["tasks": Self.tasks.filter { Int64($0["date_updated"] as! String)! > since }, "last_page": true]
        }
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure("FAIL: " + text) }; print("PASS: \(text)")
}
@MainActor func wait(_ what: String, seconds: Double = 5, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() { if Date() > until { throw RuntimeFailure("Timed out: \(what)") }; try await Task.sleep(for: .milliseconds(10)) }
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-test-desk-inbox."))
    let file = root.appendingPathComponent("Desk/inbox.json")
    DeskInbox.settle = .milliseconds(150)
    func event(_ id: String, _ kind: String = "task.updated") -> DeskEvent {
        DeskEvent(source: "clickup", sourceEventID: id, kind: kind, title: "Task " + id)
    }

    var inbox = DeskInbox(file: file)
    var batches: [[String]] = []
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false
    var failNext = 0
    inbox.runner = { events in
        batches.append(events.map(\.sourceEventID))
        if holdNext { holdNext = false; await withCheckedContinuation { gate = $0 } }
        if failNext > 0 { failNext -= 1; throw RuntimeFailure("agent failed") }
    }

    // Duplicates are dropped.
    try check(inbox.add(event("a")), "a new change is added")
    try check(!inbox.add(event("a")), "the same change again is dropped")
    // A burst is one run.
    inbox.add(event("b")); inbox.add(event("c"))
    try await wait("the first batch") { inbox.events.allSatisfy { $0.status == .done } }
    try check(batches == [["a", "b", "c"]], "three changes in a burst make one run (\(batches))")

    // One run at a time: what arrives mid-run goes in the next.
    holdNext = true
    inbox.add(event("d"))
    try await wait("the held run to start") { gate != nil }
    inbox.add(event("e"))
    try await Task.sleep(for: .milliseconds(400))
    try check(batches.count == 2 && inbox.isRunning, "a change mid-run doesn't start a second run")
    gate?.resume(); gate = nil
    try await wait("the next batch") { batches.count == 3 && !inbox.isRunning }
    try check(batches[1] == ["d"] && batches[2] == ["e"], "it goes in the next run (\(batches))")

    // A failed run is retried, then given up on after three tries.
    failNext = 1
    inbox.add(event("f"))
    try await wait("the retry") { inbox.events.first { $0.sourceEventID == "f" }?.status == .done }
    try check(inbox.events.first { $0.sourceEventID == "f" }?.attempts == 2, "a failed run is tried again, and succeeds")
    failNext = 5
    inbox.add(event("g"))
    try await wait("giving up", seconds: 8) { inbox.events.first { $0.sourceEventID == "g" }?.status == .failed }
    let g = inbox.events.first { $0.sourceEventID == "g" }
    try check(g?.attempts == DeskInbox.maxAttempts && g?.problem == "agent failed", "after three failures it stops, with the reason")
    failNext = 0

    // A crash mid-run: a new inbox on the same file tries those events again.
    holdNext = true
    inbox.add(event("h"))
    try await wait("the run to start") { gate != nil }
    try check(inbox.events.first { $0.sourceEventID == "h" }?.status == .running, "mid-run, the event is running")
    let saved = try Data(contentsOf: file)
    inbox = DeskInbox(file: file)   // as after a crash: the old one never finishes
    var after: [[String]] = []
    inbox.runner = { events in after.append(events.map(\.sourceEventID)) }
    try check(inbox.pending.map(\.sourceEventID) == ["h"] && saved.count > 0, "after a restart, the cut-short event is pending again")
    try check(!inbox.add(event("a")), "the restarted inbox still knows what it has seen")
    inbox.wake(now: true)
    try await wait("the retried run") { after == [["h"]] }
    try check(inbox.events.first { $0.sourceEventID == "h" }?.status == .done, "and runs it once")
    // ClickUp: the first check learns where things stand; later checks report real changes.
    URLProtocol.registerClass(FakeClickUp.self)
    let watcher = ClickUpWatcher()
    watcher.base = URL(string: "https://fake-clickup.test/api/v2")!
    watcher.token = { "test-token" }
    watcher.checkpointsFile = root.appendingPathComponent("Desk/checkpoints.json")
    var seen: [DeskEvent] = []
    DeskInbox.shared.runner = { seen += $0 }
    let t0 = Int64(Date().timeIntervalSince1970 * 1000)
    func task(_ id: String, _ name: String, status: String, updated: Int64, created: Int64, priority: String? = "normal") -> [String: Any] {
        ["id": id, "name": name, "status": ["status": status], "priority": priority.map { ["priority": $0] } as Any,
         "date_updated": "\(updated)", "date_created": "\(created)", "url": "https://app.clickup.com/t/\(id)", "text_content": "Brief for \(name)",
         "list": ["name": "Design"]]
    }
    FakeClickUp.tasks = [task("old1", "Banner", status: "in progress", updated: t0 - 5000, created: t0 - 900_000)]
    let firstAdded = await watcher.check(now: Date(timeIntervalSince1970: Double(t0 - 10_000) / 1000))
    try check(firstAdded == 0 && DeskCheckpoints.load(watcher.checkpointsFile).clickupTasks["old1"] != nil, "the first check learns where things stand, adding nothing")
    // A new task, a status change, a comment from someone else, and one from Shelby.
    FakeClickUp.tasks = [task("old1", "Banner", status: "in review", updated: t0 + 2000, created: t0 - 900_000),
                         task("new1", "Flyer", status: "to do", updated: t0 + 3000, created: t0 + 3000)]
    FakeClickUp.comments = ["old1": [["id": "c1", "date": "\(t0 + 1500)", "user": ["id": 111, "username": "Sierra"], "comment_text": "Looks great, small tweak"],
                                     ["id": "c2", "date": "\(t0 + 1600)", "user": ["id": ClickUpWatcher.me, "username": "Shelby Klein"], "comment_text": "Thanks!"]]]
    let added = await watcher.check()
    let kinds = DeskInbox.shared.events.filter { $0.sourceEventID.contains(":") }.map(\.kind).sorted()
    try check(added == 3 && kinds == ["comment.new", "task.new", "task.updated"], "a new task, a status change and someone else's comment become events (\(kinds))")
    try check(DeskInbox.shared.events.first { $0.kind == "task.updated" && $0.sourceEventID.hasPrefix("task:") }?.detail.contains("status in progress → in review") == true, "the update says what changed")
    try check(!DeskInbox.shared.events.contains { $0.detail.contains("Thanks!") }, "Shelby's own comment is ignored")
    // Nothing new: nothing added, and the same comment isn't reported twice.
    let quiet = await watcher.check(); try check(quiet == 0, "a quiet check adds nothing")
    // An update to a task whose watched fields didn't change (only a comment from Shelby) adds nothing.
    FakeClickUp.tasks[1]["date_updated"] = "\(t0 + 9000)"
    let unchanged = await watcher.check(); try check(unchanged == 0, "an update that changes nothing watched adds nothing")
    // Rate limited: nothing added, the checkpoint stays, the problem shows.
    let before = DeskCheckpoints.load(watcher.checkpointsFile).clickupUpdatedAfter
    FakeClickUp.status = 429
    FakeClickUp.tasks[0]["status"] = ["status": "complete"]; FakeClickUp.tasks[0]["date_updated"] = "\(t0 + 20_000)"
    let limitedCount = await watcher.check(); try check(limitedCount == 0, "a rate-limited check adds nothing")
    let limited = DeskCheckpoints.load(watcher.checkpointsFile)
    try check(limited.clickupUpdatedAfter == before && limited.problems["clickup"]?.contains("slow down") == true, "and keeps its checkpoint, noting the problem")
    FakeClickUp.status = 200
    let caught = await watcher.check(); try check(caught == 1 && DeskCheckpoints.load(watcher.checkpointsFile).problems["clickup"] == nil, "the next check catches up and clears the problem")
    // Apple Mail: a stand-in index and accounts database (the real ones are never touched).
    func sql(_ file: URL, _ statement: String) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3"); p.arguments = [file.path, statement]
        try p.run(); p.waitUntilExit()
    }
    let accounts = root.appendingPathComponent("Accounts4.sqlite"), index = root.appendingPathComponent("Envelope Index")
    try sql(accounts, "CREATE TABLE ZACCOUNT (ZIDENTIFIER TEXT, ZUSERNAME TEXT, ZACCOUNTDESCRIPTION TEXT); INSERT INTO ZACCOUNT VALUES ('PC-1','info@playcase.gg','Exchange');")
    try sql(index, """
        CREATE TABLE mailboxes (ROWID INTEGER PRIMARY KEY, url TEXT); CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT);
        CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT); CREATE TABLE summaries (ROWID INTEGER PRIMARY KEY, summary TEXT);
        CREATE TABLE messages (ROWID INTEGER PRIMARY KEY, message_id INTEGER, sender INTEGER, subject INTEGER, summary INTEGER, date_received INTEGER, mailbox INTEGER, deleted INTEGER DEFAULT 0);
        INSERT INTO mailboxes VALUES (1,'ews://UA-1/Inbox'),(2,'ews://UA-1/Sent Items'),(3,'ews://PC-1/Inbox');
        INSERT INTO addresses VALUES (1,'callie@usarchery.org','Callie Grieser'),(2,'store@playcase.gg','');
        INSERT INTO subjects VALUES (1,'Old news'); INSERT INTO summaries VALUES (1,'Earlier');
        INSERT INTO messages VALUES (1,9001,1,1,1,1795000000,1,0);
        """)
    let mail = MailWatcher()
    mail.indexFile = index; mail.accountsFile = accounts; mail.keepMailOpen = false
    mail.checkpointsFile = watcher.checkpointsFile
    mail.domain = { "usarchery.org" }
    let missing = await mail.check()
    try check(missing == 0 && DeskCheckpoints.load(mail.checkpointsFile).problems["mail"]?.contains("Add your usarchery.org account to Apple Mail") == true,
              "without the account in Mail, it says what to do")
    try sql(accounts, "INSERT INTO ZACCOUNT VALUES ('UA-1','shelby@usarchery.org','Exchange');")
    let learned = await mail.check()
    try check(learned == 0 && DeskCheckpoints.load(mail.checkpointsFile).mailAfterRow == 1, "with the account, the first check learns where Mail is")
    try sql(index, """
        INSERT INTO subjects VALUES (2,'Banner proof feedback'),(3,'Sent by me'),(4,'PlayCase order');
        INSERT INTO summaries VALUES (2,'Can we make the logo bigger?');
        INSERT INTO messages VALUES (2,9002,1,2,2,1795100000,1,0),(3,9003,1,3,NULL,1795100100,2,0),(4,9004,2,4,NULL,1795100200,3,0),(5,9005,1,2,2,1795100300,1,1);
        """)
    let newMail = await mail.check()
    let email = DeskInbox.shared.events.first { $0.kind == "email.new" }
    try check(newMail == 1 && email?.title == "Banner proof feedback" && email?.detail.contains("Callie Grieser <callie@usarchery.org>") == true
              && email?.detail.contains("logo bigger") == true, "a new USA Archery inbox message becomes an event, with sender and summary")
    try check(!DeskInbox.shared.events.contains { $0.title == "Sent by me" || $0.title == "PlayCase order" }, "sent mail, other accounts and deleted mail are left out")
    let again = await mail.check()
    try check(again == 0, "the same mail isn't reported twice")
    print("ALL PASS")
}
MainActor.assumeIsolated {
    Task { @MainActor in do { try await run(); exit(0) } catch { print(error); exit(1) } }
}
RunLoop.main.run()

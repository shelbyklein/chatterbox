import Foundation
import Darwin
// Work threads (plans/work-threads.md), as the service runs them, with real turns through the
// fixture providers: a project's front thread starts work threads over the service socket (an
// agent only from its own front thread mid-reply, like a sidequest; never from a work thread:
// one level); each is a fresh thread in the same folder whose first message is its brief (not
// the front thread's transcript), on the front thread's agent unless chosen, carrying its own
// task on the Desk; its finished reply (or `work report`) arrives in the front thread, and its
// task moves to Ready. A turn that ends with background work running is progress (the task stays
// Working); the turn that ends with nothing running reports, or, if none comes, a safety net once
// it's sat idle. The phone's routes start and list them too.
func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure(text) }; print("PASS: \(text)")
}
@MainActor func wait(_ what: String, seconds: Double = 15, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() { if Date() > until { throw RuntimeFailure("Timed out: \(what)") }; try await Task.sleep(for: .milliseconds(20)) }
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-test-work."))
    let fake = ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!
    AppPreferences.defaults.setVolatileDomain(["companionEnabled": true, "mobilePushEnabled": false, "keepMacAwake": false,
                                               "claudePath": fake, "codexPath": fake, "codexFolder": root.path,
                                               "easyCLIProxyEnabled": false, "remoteControlClaudeChats": false,
                                               "pcSSHHost": "chatterbox-test-no-pc.invalid"],
                                              forName: UserDefaults.argumentDomain)
    let runtime = try ConversationRuntime(root: root)
    await runtime.resume()
    let model = DaemonContext(runtime), server = CompanionServer.shared
    server.model = model
    let desk = DeskStore.shared
    // As the service wires it (ChatterboxDaemon/main.swift).
    RuntimeHooks.turnEnded = { session in
        session.automaticTurn = false
        if let parent = session.record.sidequestOf { DispatchQueue.main.async { session.sidequestTurnEnded(parent: runtime.session(parent)) } }
        if let front = session.record.workOf { DispatchQueue.main.async { session.workTurnEnded(front: runtime.session(front)) } }
    }
    func lines(_ name: String) -> [String] {
        ((try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    // A project's front thread, on Claude, that has talked a while.
    let folder = root.appendingPathComponent("Dogear"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var frontRecord = ConversationRecord(model: "sonnet", effort: "high", personality: .pragmatic)
    frontRecord.title = "Dogear"; frontRecord.projectFolder = folder.path; frontRecord.projectNickname = "Dogear"; frontRecord.activeBackend = .claude
    let front = try runtime.insert(frontRecord)
    front.send("FRONT_ONLY_CONTEXT: plan the highlights sync")
    try await wait("the front thread's first reply") { !front.isRunning && front.items.contains { $0.kind == .assistant } }

    // The service socket: the app (ui) and an agent.
    let socket = RuntimeServer(runtime: runtime)
    try socket.start()
    defer { socket.stop() }
    let ui = RuntimeClient(socketName: "daemon.sock"), agent = RuntimeClient(socketName: "daemon.sock")
    ui.start(role: "ui"); agent.start(role: "agent")
    try await wait("both connect") { ui.connected && agent.connected }
    func start(_ client: RuntimeClient, from chat: ChatSession, _ title: String, brief: String, agent other: String? = nil) async throws -> Companion.ChatDetail {
        var body: [String: JSON] = ["action": "start", "chatID": .string(chat.id.uuidString), "title": .string(title), "brief": .string(brief)]
        if let other { body["agent"] = .string(other) }
        return try await client.request("work", body: .object(body)).decode(Companion.ChatDetail.self)
    }
    func refused(_ what: String, _ expected: String, _ call: () async throws -> Any) async throws {
        do { _ = try await call(); try check(false, what) } catch { try check(error.localizedDescription.contains(expected), "\(what): \(error.localizedDescription)") }
    }

    // The permission rule, as a sidequest's: an agent only from its own front thread mid-reply.
    try await refused("an agent can't start one from a thread that isn't working", "permission_denied") {
        try await start(agent, from: front, "Highlights sync", brief: "Fix the sync.")
    }
    try check(!runtime.sessions.contains { $0.record.workOf != nil }, "nothing started")
    try await refused("a brief is needed", "brief") { try await start(ui, from: front, "Highlights sync", brief: "  ") }
    let frontReplies = front.items.filter { $0.kind == .assistant }.count
    front.isRunning = true   // mid-reply: its agent runs `work start`
    let brief = "Fix the highlights sync in Sync.swift; plans/sync.md has what's decided. Report what changed."
    let first = try await start(agent, from: front, "Highlights sync", brief: brief)
    front.isRunning = false
    let work = runtime.session(first.summary.id)!
    try check(work.record.workOf == front.id && first.summary.workOf == front.id && work.record.sidechatOf == front.id
              && work.workingFolder == front.workingFolder, "a fresh thread in the front thread's folder, its work thread")
    try check(work.title == "Highlights sync" && work.record.backend == .claude && work.record.model == "sonnet" && work.record.effort == "high",
              "named as asked, on the front thread's agent and model")
    try check(work.items.first { $0.kind == .user }?.text == brief, "the brief is its first message")
    try check(front.items.last?.kind == .notice && front.items.last?.sidequest == work.id && front.items.last?.text.contains("Highlights sync") == true,
              "the front thread notes it started, with a way to open it")
    let task = desk.openTask(for: work.id)
    try check(task?.text == "Highlights sync" && task?.proposed?.id == front.id && task?.proposed?.kind == "project" && task?.source == "claude",
              "its own task, linked, in the front thread's project, from Claude")

    // What it was given: the framing and the brief, not the front thread's conversation.
    try await wait("the brief reaches its agent") { lines("claude-input.jsonl").contains { $0.contains("Fix the highlights sync in Sync.swift") } }
    let given = lines("claude-input.jsonl").first { $0.contains("Fix the highlights sync in Sync.swift") }!
    try check(given.contains("<work_thread>") && given.contains("Dogear") && !given.contains("FRONT_ONLY_CONTEXT"),
              "told it's a work thread for the front thread, without the front thread's transcript")
    try check(work.record.parentContext == nil, "no transcript handoff kept either")

    // Its finished reply goes back to the front thread, which carries on; its task is Ready.
    try await wait("the result arrives in the front thread") { front.items.contains { $0.kind == .user && $0.sidequest == work.id && $0.automatic == true } }
    let back = front.items.last { $0.kind == .user && $0.sidequest == work.id }!
    try check(back.text.contains("<work_result>") && back.text.contains("Fixture reply.") && back.text.contains("Highlights sync")
              && back.detail == "Work thread \u{201C}Highlights sync\u{201D} finished", "the result: its final reply, labelled, with a way to open it")
    try await wait("the front thread carries on") { !front.isRunning && front.items.filter { $0.kind == .assistant }.count > frontReplies }
    try check(work.record.workReported != nil && work.unreportedWorkReply == nil && work.record.archivedAt == nil,
              "the reply is recorded as reported; the work thread stays open (Mark complete archives it)")
    let board = desk.snapshot()
    try check(board.ready?.first { $0.id == work.id }?.task == task?.id && board.ready?.first { $0.id == work.id }?.place == "Dogear"
              && !board.incoming.contains { $0.id == task?.id }, "its task is Ready to mark complete")
    try check(!(board.ready ?? []).contains { $0.id == front.id } && !board.working.contains { $0.id == front.id },
              "the front thread, with no task of its own, isn't on the board")

    // One level only: a work thread doesn't start work threads, from its agent or the app.
    work.isRunning = true
    try await refused("a work thread's agent can't start one", "nested_work") { try await start(agent, from: work, "Deeper", brief: "x") }
    work.isRunning = false
    try await refused("nor can the app, from a work thread", "nested_work") { try await start(ui, from: work, "Deeper", brief: "x") }
    try check(runtime.sessions.filter { $0.record.workOf != nil }.count == 1, "nothing more started")

    // Another agent when chosen; `work report` sends a result before the turn ends, and the reply
    // ending that turn isn't sent again.
    front.isRunning = true
    let second = try await start(agent, from: front, "Cover art", brief: "Draw three covers. hold", agent: "codex")
    front.isRunning = false
    let art = runtime.session(second.summary.id)!
    try check(art.record.backend == .codex && art.record.codex?.folder == front.workingFolder, "another agent when chosen, in the same folder")
    try await wait("the second work thread is working") { art.isRunning }
    try await refused("only a work thread reports", "not_work_thread") {
        try await agent.request("work", body: ["action": "report", "chatID": .string(front.id.uuidString), "text": "x"])
    }
    let reports = front.items.filter { $0.sidequest == art.id && $0.kind == .user }.count
    _ = try await agent.request("work", body: ["action": "report", "chatID": .string(art.id.uuidString), "text": "Three covers in covers/."])
    let reported = front.items.last { $0.sidequest == art.id && $0.kind == .user }
    try check(front.items.filter { $0.sidequest == art.id && $0.kind == .user }.count == reports + 1 && reported?.text.contains("Three covers in covers/.") == true
              && reported?.text.contains("reported back") == true && reported?.detail == "Work thread \u{201C}Cover art\u{201D} reported",
              "work report: the result arrives now")
    art.send("Carry on")   // steers the held turn, which then finishes
    try await wait("the second work thread finishes") { !art.isRunning && art.items.contains { $0.kind == .assistant && $0.phase == .final } }
    try await wait("its reply is marked reported") { art.record.workReported != nil }
    try await Task.sleep(for: .milliseconds(300))
    try check(front.items.filter { $0.sidequest == art.id && $0.kind == .user }.count == reports + 1, "the reply ending that turn isn't sent again")
    try await wait("the front thread settles") { !front.isRunning }

    // list: from the front thread or one of its work threads, newest first, with their state.
    let listed = try await agent.request("work", body: ["action": "list", "chatID": .string(work.id.uuidString)]).decode([Companion.WorkThread].self)
    try check(listed.map(\.id) == [art.id, work.id] && listed.allSatisfy { $0.state == "ready" } && listed.last?.task == task?.id
              && listed.first?.backend == "codex", "list: the front thread's work threads, newest first, with their state")
    // Mark complete: the work thread archives, its task into Done, and the strip says done.
    try desk.complete(work.id)
    let afterDone = desk.workThreads(of: front)
    try check(work.record.archivedAt != nil && afterDone.first { $0.id == work.id }?.state == "done"
              && desk.snapshot().done?.first?.id == work.id, "Mark complete archives it: done in the strip and on the board")

    // The phone: start and list from a front thread; ChatDetail carries the strip and the header.
    func request(_ method: String, _ path: String, _ body: Data = Data(), _ headers: [String: String] = [:]) -> HTTPResponse {
        server.respond(to: HTTPRequest(method: method, path: path, query: [:], headers: headers, body: body))
    }
    let paired = request("POST", "/v1/pair", try Companion.encoder.encode(Companion.PairRequest(code: server.pairingCode, deviceName: "Work fixture")))
    let token = try Companion.decoder.decode(Companion.PairResponse.self, from: paired.body).token
    let auth = [Companion.tokenHeader.lowercased(): token]
    let phoneStart = request("POST", "/v1/chats/\(front.id)/work", try Companion.encoder.encode(Companion.WorkStartRequest(title: "Release notes", brief: "Write the 2.1 release notes.")), auth)
    let phoneWork = try Companion.decoder.decode(Companion.ChatDetail.self, from: phoneStart.body)
    try check(phoneStart.status == 200 && phoneWork.summary.workOf == front.id && phoneWork.workOfTitle == "Dogear"
              && desk.openTask(for: phoneWork.summary.id)?.source == "you", "the phone starts one (from you); its detail names the front thread")
    try check(request("POST", "/v1/chats/\(phoneWork.summary.id)/work", try Companion.encoder.encode(Companion.WorkStartRequest(title: "x", brief: "y")), auth).status == 409,
              "the phone can't start one from a work thread either")
    let frontDetail = try Companion.decoder.decode(Companion.ChatDetail.self, from: request("GET", "/v1/chats/\(front.id)", Data(), auth).body)
    try check(frontDetail.work?.map(\.id) == [phoneWork.summary.id, art.id, work.id] && frontDetail.work?.last?.state == "done" && frontDetail.workOfTitle == nil,
              "the front thread's detail lists its work threads (the Work strip)")
    let phoneList = try Companion.decoder.decode([Companion.WorkThread].self, from: request("GET", "/v1/chats/\(front.id)/work", Data(), auth).body)
    try check(phoneList.map(\.id) == frontDetail.work?.map(\.id), "GET …/work lists them")
    try await wait("the phone's work thread reports back") { front.items.contains { $0.sidequest == phoneWork.summary.id && $0.kind == .user } }

    // A turn that ends with background work still running is progress, not the result: nothing
    // goes back, its task stays Working with that reply as its status line, until the agent picks
    // back up by itself and finishes with nothing running; that reply is the result.
    try await wait("the front thread settles first") { !front.isRunning }
    func results(_ work: ChatSession) -> [DisplayItem] { front.items.filter { $0.kind == .user && $0.sidequest == work.id } }
    let suite = runtime.session(try await start(ui, from: front, "Run the suite", brief: "Run the full suite. background").summary.id)!
    try await wait("its turn ends with the suite still running") { !suite.isRunning && suite.record.workTurnEndedAt != nil }
    try check(suite.hasBackgroundWork && suite.isWorkPending && suite.items.contains { $0.kind == .assistant && $0.text.contains("notified") },
              "its turn ended saying it'll be notified, with the suite still running")
    try check(results(suite).isEmpty, "that reply doesn't go back to the front thread")
    var suiteBoard = desk.snapshot()
    try check(suiteBoard.working.contains { $0.id == suite.id } && !(suiteBoard.ready ?? []).contains { $0.id == suite.id }, "its task stays Working on the board")
    let suiteListed = try await agent.request("work", body: ["action": "list", "chatID": .string(front.id.uuidString)]).decode([Companion.WorkThread].self)
        .first { $0.id == suite.id }
    try check(suiteListed?.state == "working" && suiteListed?.status?.contains("Suite running") == true,
              "the Work strip shows it Working, with its latest status line: \(suiteListed?.status ?? "none")")
    try await wait("it picks back up and finishes; the result goes back") { !results(suite).isEmpty }
    try check(results(suite).count == 1 && results(suite)[0].text.contains("Suite passed: all 42 tests green.") && !results(suite)[0].text.contains("notified")
              && results(suite)[0].detail == "Work thread \u{201C}Run the suite\u{201D} finished", "the turn that ends with nothing running reports its reply, once")
    try await wait("the front thread carries on") { !front.isRunning }
    suiteBoard = desk.snapshot()
    let suiteState = desk.workThreads(of: front).first { $0.id == suite.id }?.state
    try check(!suite.isWorkPending && !suite.hasBackgroundWork && (suiteBoard.ready ?? []).contains { $0.id == suite.id }
              && !suiteBoard.working.contains { $0.id == suite.id } && suiteState == "ready", "then its task is Ready")

    // The safety net: background work ends but the agent never picks back up. Idle that long,
    // nothing running, it reports what it has; before then it's still Working.
    ChatSession.workIdleReport = 4
    let stall = runtime.session(try await start(ui, from: front, "Nightly build", brief: "Build it. background-stall").summary.id)!
    try await wait("its turn ends with the build still running") { !stall.isRunning && stall.record.workTurnEndedAt != nil }
    try check(stall.isWorkPending && stall.hasBackgroundWork && results(stall).isEmpty, "progress: nothing goes back yet")
    try await wait("the build finishes, and nothing picks back up") { !stall.hasBackgroundWork }
    runtime.reportIdleWork()
    let stallState = desk.workThreads(of: front).first { $0.id == stall.id }?.state
    try check(stall.isWorkPending && results(stall).isEmpty && desk.snapshot().working.contains { $0.id == stall.id } && stallState == "working",
              "idle, but not for long: still Working, nothing sent")
    try await wait("idle long enough, it reports", seconds: 10) { runtime.reportIdleWork(); return !results(stall).isEmpty }
    try check(results(stall).count == 1 && results(stall)[0].text.contains("notified") && !stall.isWorkPending, "the safety net reports its last reply")
    try await wait("the front thread carries on") { !front.isRunning }
    let stallAfter = desk.workThreads(of: front).first { $0.id == stall.id }?.state
    try check(stallAfter == "ready", "and its task is Ready")
    runtime.reportIdleWork()
    try check(results(stall).count == 1, "the safety net reports once")
    try await wait("everything settles") { runtime.sessions.allSatisfy { !$0.isRunning } }
    ui.stop(); agent.stop()
    for session in runtime.sessions { session.shutdown() }
    try runtime.flush()
    runtime.waitForSaves()
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()

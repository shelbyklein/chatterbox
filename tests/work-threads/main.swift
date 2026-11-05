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
// it's sat idle. A task that finished just as the turn ended still owes its agent the wake-up
// Claude Code gives it, and a reply that only says it's waiting is progress too. The phone's
// routes start and list them too.
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
    // The phone's session list: the front thread is the project, its open work threads right
    // after it as its children (the phone nests them in its card), none a project of its own.
    let chatList = try Companion.decoder.decode(Companion.ChatList.self, from: request("GET", "/v1/chats", Data(), auth).body)
    let projectChats = chatList.groups.first { $0.kind == .projects }?.chats ?? []
    let openWork = Set([phoneWork.summary.id, art.id])
    try check(projectChats.first?.id == front.id && Set(projectChats.dropFirst().map(\.id)).isSuperset(of: openWork)
              && projectChats.filter { openWork.contains($0.id) }.allSatisfy { $0.workOf == front.id && $0.sidechatOf == front.id && $0.project == nil },
              "the phone's list has the front thread as the project and its work threads after it, not as projects: \(projectChats.map(\.title))")
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

    // Seen 2026-11-05 ("Keep the Mac usable…"): the background commands finished while the turn's
    // last answer was being written, so nothing was running when the turn ended and its "I'll pick
    // up when they finish" went back as the result; Claude Code then woke the agent with a turn of
    // its own. A finished task is owed that wake-up until a turn starts: the turn it starts reports.
    ChatSession.workWakeupGrace = 1.5
    let race = runtime.session(try await start(ui, from: front, "Rerun the tests", brief: "Rerun them. background-race").summary.id)!
    try await wait("its turn ends just after the rerun finished") { !race.isRunning && race.record.workTurnEndedAt != nil }
    try check(!race.hasBackgroundWork && race.owedWakeups.count == 1 && race.isWorkPending && results(race).isEmpty,
              "nothing runs, but the finished rerun is owed its wake-up: progress, nothing sent")
    try await wait("Claude Code's own turn hands it the news, and that reply reports") { !results(race).isEmpty }
    try check(results(race).count == 1 && results(race)[0].text.contains("Rerun done: all 42 tests pass") && !results(race)[0].text.contains("pick up")
              && race.owedWakeups.isEmpty && !race.isWorkPending, "the result is the woken turn's reply, once")
    try await wait("the front thread carries on") { !front.isRunning }

    // The wake-up never comes: after a short grace the reply reports (it doesn't read as waiting).
    let raceStall = runtime.session(try await start(ui, from: front, "Rerun again", brief: "Rerun them. background-race-stall").summary.id)!
    try await wait("its turn ends just after the rerun finished") { !raceStall.isRunning && raceStall.record.workTurnEndedAt != nil }
    try check(raceStall.isWorkPending && raceStall.owedWakeups.count == 1 && results(raceStall).isEmpty, "held for its wake-up")
    try await wait("no turn comes: it reports after the grace", seconds: 6) { !results(raceStall).isEmpty }
    try check(results(raceStall).count == 1 && results(raceStall)[0].text.contains("Started the test rerun.") && !raceStall.isWorkPending,
              "the grace reports its reply, once, not stuck Working")
    try await wait("the front thread carries on") { !front.isRunning }

    // Delivered within the turn (echoed as a message): nothing's owed, so the turn's answer is the
    // result, at once.
    let delivered = runtime.session(try await start(ui, from: front, "Quick rerun", brief: "Rerun them. background-delivered").summary.id)!
    try await wait("its turn ends") { !delivered.isRunning && delivered.record.workTurnEndedAt != nil }
    try await wait("its result arrives without waiting for a grace", seconds: 0.5) { !results(delivered).isEmpty }
    try check(results(delivered)[0].text.contains("Tests rerun: all 42 pass") && delivered.owedWakeups.isEmpty && !delivered.isWorkPending,
              "a notification handed over within the turn isn't owed")
    try await wait("the front thread carries on") { !front.isRunning }

    // The backstop: nothing Chatterbox can see runs, but the reply says it's waiting (a job it
    // detached itself): progress, shown as its status line, until the safety net.
    let interim = runtime.session(try await start(ui, from: front, "Detached run", brief: "Run it. say-interim").summary.id)!
    try await wait("its turn ends") { !interim.isRunning && interim.record.workTurnEndedAt != nil }
    let interimListed = try await agent.request("work", body: ["action": "list", "chatID": .string(front.id.uuidString)]).decode([Companion.WorkThread].self)
        .first { $0.id == interim.id }
    try check(!interim.hasBackgroundWork && interim.owedWakeups.isEmpty && interim.isWorkPending && results(interim).isEmpty
              && interimListed?.state == "working" && interimListed?.status?.contains("Rerunning now") == true,
              "a reply that says it's waiting stays Working, as the status line: \(interimListed?.status ?? "none")")
    try await wait("the safety net reports it", seconds: 10) { runtime.reportIdleWork(); return !results(interim).isEmpty }
    try await wait("the front thread carries on") { !front.isRunning }

    // A real result that mentions passing tests and what's next (on you) isn't held.
    let real = runtime.session(try await start(ui, from: front, "Ship prep", brief: "Get it ready. say-result").summary.id)!
    try await wait("its turn ends") { !real.isRunning && real.record.workTurnEndedAt != nil }
    try await wait("a real result reports at once", seconds: 0.5) { !results(real).isEmpty }
    try check(results(real)[0].text.contains("All 42 tests pass") && !real.isWorkPending, "a real result goes back at once")
    try await wait("the front thread carries on") { !front.isRunning }

    // The wording check on its own, against the interim replies that went back as results on
    // 2026-11-05, and real results.
    for text in ["Tests are rerunning in the background, with the Chatterbox Dev install queued behind them. I'll pick up when they finish.",
                 "Rerunning now; the Dev install follows if the three tests pass. I'll continue when the notification arrives.",
                 "The full verification chain is running on the rebased tree (Mac build, ten tests, Dev install). Nothing else can proceed until it reports; I'll continue when it finishes.",
                 "The monitor I already have covers it, so I stopped that duplicate watcher. I'll carry on when the phone test reports.",
                 "The first phone test passed. Waiting for the rest.",
                 "Still queued behind the other thread's iPad run. I'll pick it up when it finishes.",
                 "That was the stale run's exit code. Still waiting on the retest and the iOS build.",
                 "My iPhone tests are now running on their own port, so they no longer wait on the iPad run. I\u{2019}ll report back when they finish.",
                 "Suite running. I'll be notified when the suite finishes."] {
        try check(ChatSession.readsAsInterim(text), "reads as waiting: \(text.prefix(50))…")
    }
    for text in ["All 42 tests pass. Committed abc123 and pushed to main.",
                 "Done: the tests pass and Chatterbox Dev is installed. I'll continue when you say ship.",
                 "Tests pass. Waiting for your go-ahead to ship to the real app.",
                 "Fixed the sync. I'll pick up the phone half once Shelby has tried it.",
                 "The Dev service restart is queued and waits until replies finish; tests pass.",
                 "Both features are built and tested. " + String(repeating: "Details of what changed and how it was checked. ", count: 14) + "I'll pick up the rest when the build finishes.",
                 "Draft card passed too.", ""] {
        try check(!ChatSession.readsAsInterim(text), "a result: \(text.prefix(50))…")
    }
    try await wait("the front thread settles after the stall") { !front.isRunning }

    // Agents run below the app (the host starts them through nice) with build caps in their
    // environment (half the cores at OK), and every shell they start inherits the priority.
    let launches = (try? String(contentsOfFile: ProcessInfo.processInfo.environment["FAKE_PROVIDER_LAUNCHES"]!, encoding: .utf8)) ?? ""
    let launch = launches.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }.last
    let half = String(max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    // Nice adds to the test's own priority (an agent shell running this test is already nicer).
    let niced = min(20, Int(getpriority(PRIO_PROCESS, 0)) + 10)
    try check(launch?["nice"] as? Int == niced && (launch?["childNice"] as? String) == String(niced), "an agent runs 10 nicer (\(niced)), and so does a shell it starts: \(launch?["nice"] ?? "none"), \(launch?["childNice"] ?? "none")")
    let caps = launch?["build"] as? [String: String]
    // The caps follow the Mac's real pressure at launch: half the cores at OK, a quarter under pressure.
    let jobs = String(MacPressure.buildJobs(level: MacPressure.current, cores: ProcessInfo.processInfo.activeProcessorCount))
    try check(caps == ["CMAKE_BUILD_PARALLEL_LEVEL": jobs, "MAKEFLAGS": "-j\(jobs)", "CARGO_BUILD_JOBS": jobs] && (MacPressure.current != .ok || jobs == half),
              "its environment caps builds for the Mac's pressure (\(MacPressure.current), \(jobs) jobs): \(caps ?? [:])")

    // Headless unless summoned: a work thread that has reported lets its agent go right away;
    // the front thread keeps its own for the usual two minutes.
    try check(work.releasesAgentWhenDone && art.releasesAgentWhenDone && !front.releasesAgentWhenDone, "reported work threads may let their agent go; the front thread may not")
    runtime.releaseIdleAgents()
    try check(work.claudeProcess == nil && suite.claudeProcess == nil && front.claudeProcess != nil,
              "released at once after reporting (the front thread's agent is kept)")

    // Pressure. A fake reader drives the service's monitor, with no sustain or calm windows.
    var reading = MacPressure.Readings(memory: .normal, swapUsed: 1 << 30, load1: 4, load5: 4, load15: 4, cores: 16, thermal: .nominal)
    var quick = MacPressure.Thresholds(); quick.busyLoadFor = 0; quick.overloadedLoadFor = 0; quick.stepDownAfter = 0
    let monitor = PressureMonitor(runtime: runtime, reader: { reading }, interval: 3600, thresholds: quick)
    monitor.actsForMac = { false }   // never the Mac's pressure.json or simulators
    var told: [Companion.Pressure] = []
    monitor.onChange = { told.append($0) }
    monitor.start()
    defer { monitor.stop(); MacPressure.current = .ok }
    func level(_ load: Double) { reading.load1 = load; monitor.tick() }
    level(30)
    try check(MacPressure.current == .busy && monitor.snapshot?.level == "busy" && told.last?.level == "busy", "load 30 on 16 cores: Busy, and the app is told")

    // Busy: a new work thread is made, with its task, but waits to start.
    let briefCount = lines("claude-input.jsonl").count
    let queued = runtime.session(try await start(ui, from: front, "Held build", brief: "Build the release while it's calm.").summary.id)!
    try check(queued.record.pressureHold?.first == true && !queued.isRunning && !queued.items.contains { $0.kind == .user },
              "Busy: the work thread is made but its brief isn't sent")
    try check(queued.items.last?.kind == .notice && queued.items.last?.text.contains("Waiting to start: the Mac is busy") == true, "it says it's waiting, and why")
    try check(desk.openTask(for: queued.id) != nil && desk.snapshot().working.contains { $0.id == queued.id }, "its task is on the Desk, Working")
    let waitingList = try await agent.request("work", body: ["action": "list", "chatID": .string(front.id.uuidString)]).decode([Companion.WorkThread].self)
    try check(waitingList.first { $0.id == queued.id }?.state == "working" && waitingList.first { $0.id == queued.id }?.status == "Waiting: Mac busy",
              "the Work strip shows it Working: Waiting: Mac busy")
    try check(monitor.snapshot?.waiting == 1 && monitor.snapshot?.holding.contains("1 work thread waiting") == true, "the reading counts it as held back")
    try await Task.sleep(for: .milliseconds(300))
    try check(lines("claude-input.jsonl").count == briefCount, "nothing reached its agent")

    // Overloaded, then Busy again: still waiting (a first turn waits for OK), now saying overloaded.
    level(60)
    try check(MacPressure.current == .overloaded && queued.pressureWaitingText == "Waiting: Mac overloaded", "Overloaded: it says so")
    level(30)
    try check(MacPressure.current == .busy && queued.record.pressureHold != nil, "back to Busy: still waiting for OK")

    // OK: it starts by itself and reports like any other.
    level(4)
    try check(MacPressure.current == .ok && queued.record.pressureHold == nil, "OK: the hold is let go")
    try await wait("its brief reaches its agent") { lines("claude-input.jsonl").contains { $0.contains("Build the release while it's calm.") } }
    try check(queued.items.contains { $0.kind == .notice && $0.text.contains("The Mac is calm again: starting.") }, "it says why it started")
    try await wait("it reports") { !results(queued).isEmpty }
    try await wait("the front thread carries on") { !front.isRunning }

    // Start now: waiting at Busy, started anyway from the app.
    level(30)
    let pushed = runtime.session(try await start(ui, from: front, "Urgent fix", brief: "Fix it now.").summary.id)!
    try check(pushed.record.pressureHold != nil, "Busy: another one waits")
    try await refused("only the app starts one early", "permission_denied") {
        try await agent.request("work", body: ["action": "startNow", "chatID": .string(pushed.id.uuidString)])
    }
    _ = try await ui.request("work", body: ["action": "startNow", "chatID": .string(pushed.id.uuidString)])
    try check(pushed.record.pressureHold == nil && pushed.items.contains { $0.kind == .notice && $0.text.contains("Started now, as you asked") }, "Start now starts it")
    try await wait("it reports") { !results(pushed).isEmpty }
    try await wait("the front thread carries on") { !front.isRunning }

    // Writing in a waiting work thread starts it (the brief first).
    let typed = runtime.session(try await start(ui, from: front, "Docs pass", brief: "Tidy the docs.").summary.id)!
    try check(typed.record.pressureHold != nil, "waiting")
    typed.send("Go ahead, it's urgent.")
    try check(typed.record.pressureHold == nil && typed.items.filter { $0.kind == .user }.map(\.text).first == "Tidy the docs.", "writing there starts it, the brief going first")
    try await wait("it reports") { !results(typed).isEmpty }
    try await wait("the front thread carries on") { !front.isRunning }

    // Overloaded: a finished work thread's next turn (a sidequest's answer coming back) waits
    // until the Mac is Busy or better, labelled as it would have been; the front thread is never held.
    level(60)
    try check(MacPressure.current == .overloaded, "Overloaded")
    let answer = PressureHold.Message(text: "Codex's answer: the covers are in covers/.", automatic: true, detail: "Codex is back from its sidequest", sidequest: UUID())
    queued.sendAutomatic(answer)
    try check(queued.record.pressureHold?.until == "busy" && !queued.isRunning && queued.pressureWaitingText == "Waiting: Mac overloaded"
              && queued.isWorkingOn, "Overloaded: its next turn waits, and it shows Waiting: Mac overloaded")
    try check(front.pressureAllows(.ok), "a front thread is never held")
    // …but not one Shelby is writing in.
    typed.draft = "half a thought"
    typed.sendAutomatic(.init(text: "Another answer: done.", automatic: true, detail: "Claude is back from its sidequest"))
    try check(typed.record.pressureHold == nil && typed.items.last { $0.kind == .user }?.detail == "Claude is back from its sidequest",
              "a thread you're writing in isn't held: the answer goes in, labelled")
    typed.draft = ""
    try await wait("that turn ends") { !typed.isRunning }
    level(30)
    try check(MacPressure.current == .busy && queued.record.pressureHold == nil, "Busy again: the held turn goes")
    let heldTurn = queued.items.last { $0.kind == .user }
    try check(heldTurn?.text == answer.text && heldTurn?.automatic == true && heldTurn?.detail == answer.detail && heldTurn?.sidequest == answer.sidequest,
              "delivered as it would have been, labelled")
    try check(queued.items.contains { $0.kind == .notice && $0.text.contains("The Mac is less loaded: carrying on.") }, "saying why")
    level(4)
    try check(told.contains { $0.level == "overloaded" } && monitor.snapshot?.level == "ok" && monitor.snapshot?.waiting == 0, "back to OK, nothing held")
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

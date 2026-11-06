import Foundation
import Darwin
// Automations from the phone, as the service runs them: a routine that runs on several days
// (one automation per weekday on the Mac) shows as one; edits apply to every day, and its days
// add or remove automations; Run Now starts a run and records it; a paired token is needed for
// each; the app hears automations.changed. No agent ever starts: runs go to a stand-in session.
func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure(text) }; print("PASS: \(text)")
}
@MainActor func wait(_ what: String, seconds: Double = 8, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() { if Date() > until { throw RuntimeFailure("Timed out: \(what)") }; try await Task.sleep(for: .milliseconds(20)) }
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-test-automation-routines."))
    let nowhere = root.appendingPathComponent("no-agent").path
    AppPreferences.defaults.setVolatileDomain(["companionEnabled": true, "mobilePushEnabled": false, "keepMacAwake": false,
                                               "claudePath": nowhere, "codexPath": nowhere, "codexFolder": root.path,
                                               "easyCLIProxyEnabled": false, "remoteControlClaudeChats": false,
                                               "pcSSHHost": "chatterbox-test-no-pc.invalid"],
                                              forName: UserDefaults.argumentDomain)
    let runtime = try ConversationRuntime(root: root), model = DaemonContext(runtime), server = CompanionServer.shared
    server.model = model

    // A project open in Chatterbox (its agent is Codex), and one that isn't anymore.
    func folder(_ name: String) throws -> String {
        let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url.path
    }
    var onTargetRecord = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
    onTargetRecord.title = "On Target"; onTargetRecord.projectFolder = try folder("On Target"); onTargetRecord.projectNickname = "On Target"
    onTargetRecord.activeBackend = .codex
    let onTarget = try runtime.insert(onTargetRecord)
    let goneFolder = try folder("Old Site")

    // The Mac's automations: a morning routine every day (seven automations), a weekly one,
    // one like the morning routine but for its instructions, and a paused one for a closed project.
    let morningText = "Read ClickUp and Outlook, then list today's priorities."
    func automation(_ title: String, _ text: String, weekday: Int, hour: Int, minute: Int = 0, folder: String? = nil,
                    backend: String? = "codex", model: String? = nil, effort: String? = nil, enabled: Bool = true) -> ProjectAutomation {
        var a = ProjectAutomation(projectFolder: folder ?? onTarget.record.projectFolder!, title: title, template: .custom, instructions: text,
                                  weekday: weekday, hour: hour, minute: minute, enabled: enabled)
        a.backend = backend; a.model = model; a.effort = effort
        a.createdAt = Date().addingTimeInterval(-30 * 86_400)
        return a
    }
    let morning = (1...7).map { automation("ClickUp + Outlook morning priorities", morningText, weekday: $0, hour: 8, minute: 30, model: "gpt-5.5", effort: "high") }
    try check(try ProjectAutomations.deskSourceRoutine(in: morning).count == 7, "Desk source check selects the explicit routine across weekdays")
    do { _ = try ProjectAutomations.deskSourceRoutine(in: []); throw RuntimeFailure("missing source routine accepted") }
    catch let error as NSError { try check(error.domain == "DeskSources", "missing source routine reports setup needed") }
    let runMessage = ProjectAutomations.message(for: morning[0], manual: false)
    try check(runMessage.contains("--source-url") && runMessage.contains("Never invent an ID or URL")
              && morning[0].instructions == morningText, "automation runs preserve source links without rewriting the user's saved prompt")
    let intakeMessage = ProjectAutomations.deskSourceInstructions(morningText, includeNew: true)
    try check(runMessage.contains("complete `tasks` inventory") && intakeMessage.contains("complete `tasks` inventory")
              && runMessage.contains("Review, silenced and Done") && intakeMessage.contains("never compare only incoming"),
              "scheduled and manual intake compare the entire stored task inventory")
    let weekly = automation("WordPress updates", ProjectAutomations.wordpressInstructions, weekday: 2, hour: 9, backend: "claude")
    let other = automation("ClickUp + Outlook morning priorities", "Only Outlook.", weekday: 3, hour: 8, minute: 30, model: "gpt-5.5", effort: "high")
    let paused = automation("Broken links", "Crawl for broken links.", weekday: 6, hour: 16, folder: goneFolder, backend: nil, enabled: false)
    // In the file, the days of a routine needn't sit together.
    do { _ = try ProjectAutomations.deskSourceRoutine(in: morning + [other]); throw RuntimeFailure("ambiguous source routines accepted") }
    catch let error as NSError { try check(error.domain == "DeskSources", "ambiguous source routines cannot start unrelated work") }
    try ProjectAutomations.save(Array(morning[0..<3]) + [weekly] + Array(morning[3...]) + [other, paused])

    // The phone's routes need a paired token.
    func request(_ method: String, _ path: String, _ body: Data = Data(), _ headers: [String: String]) -> HTTPResponse {
        server.respond(to: HTTPRequest(method: method, path: path, query: [:], headers: headers, body: body))
    }
    let paired = request("POST", "/v1/pair", try Companion.encoder.encode(Companion.PairRequest(code: server.pairingCode, deviceName: "Automations fixture")), [:])
    try check(paired.status == 200, "a phone pairs")
    let token = try Companion.decoder.decode(Companion.PairResponse.self, from: paired.body).token
    let auth = [Companion.tokenHeader.lowercased(): token]
    func call(_ method: String, _ path: String, _ body: Data = Data()) -> HTTPResponse { request(method, path, body, auth) }
    func list() throws -> [Companion.AutomationRoutine] {
        let response = call("GET", "/v1/automations")
        guard response.status == 200 else { throw RuntimeFailure("GET /v1/automations: \(response.status)") }
        return try Companion.decoder.decode([Companion.AutomationRoutine].self, from: response.body)
    }
    func edit(_ id: UUID, _ change: Companion.AutomationEdit) throws -> HTTPResponse {
        call("POST", "/v1/automations/\(id.uuidString)", try Companion.encoder.encode(change))
    }
    func routine(_ response: HTTPResponse) throws -> Companion.AutomationRoutine {
        guard response.status == 200 else { throw RuntimeFailure("Expected a routine, got \(response.status): \(String(decoding: response.body, as: UTF8.self))") }
        return try Companion.decoder.decode(Companion.AutomationRoutine.self, from: response.body)
    }
    func saved(_ ids: [UUID]) -> [ProjectAutomation] { ProjectAutomations.load().filter { ids.contains($0.id) } }

    // Auth: nothing without the token, and nothing changes or runs.
    let before = try Data(contentsOf: ProjectAutomations.configFile)
    try check(request("GET", "/v1/automations", Data(), [:]).status == 401, "the list needs a paired token")
    try check(request("POST", "/v1/automations/\(morning[0].id)", try Companion.encoder.encode(Companion.AutomationEdit(enabled: false)), [:]).status == 401,
              "editing needs one")
    try check(request("POST", "/v1/automations/\(morning[0].id)/run", Data("{}".utf8), ["x-chatterbox-token": "wrong"]).status == 401, "running needs one")
    try check(try Data(contentsOf: ProjectAutomations.configFile) == before && !FileManager.default.fileExists(atPath: ProjectAutomations.stateFile.path),
              "nothing changed or ran without it")

    // Grouping: seven weekday automations are one routine with seven days.
    let routines = try list()
    try check(routines.count == 4, "four routines: \(routines.map(\.title))")
    guard let daily = routines.first(where: { $0.instructions == morningText }) else { throw RuntimeFailure("no morning routine") }
    try check(daily.ids.count == 7 && Set(daily.ids) == Set(morning.map(\.id)) && daily.days == [1, 2, 3, 4, 5, 6, 7] && daily.id == morning[0].id,
              "seven weekday automations: one routine, every day")
    try check(daily.hour == 8 && daily.minute == 30 && daily.agent == "codex" && daily.model == "gpt-5.5" && daily.effort == "High"
              && daily.project == "On Target" && daily.projectFolder == onTarget.record.projectFolder && daily.enabled && daily.pausedDays == nil,
              "with its time, agent, model, effort and project")
    let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 30), matchingPolicy: .nextTime)
    try check(daily.nextRunAt == next, "its next run: the next 8:30")
    try check(daily.lastRunAt == nil && daily.lastThreadID == nil, "not run yet")
    let onlyOutlook = routines.first { $0.instructions == "Only Outlook." }
    try check(onlyOutlook?.ids == [other.id] && onlyOutlook?.days == [3], "other instructions: a routine of its own")
    let closed = routines.first { $0.title == "Broken links" }
    try check(closed?.project == "Old Site" && closed?.enabled == false && closed?.nextRunAt == nil && closed?.agent == "claude",
              "a closed project's routine: named by its folder, paused, no next run")
    let dated = routines.compactMap(\.nextRunAt)
    try check(dated == dated.sorted() && routines.last?.title == "Broken links", "soonest next run first, paused last")
    try check(routines.first { $0.title == "WordPress updates" }?.agent == "claude", "each routine's own agent")

    // The app hears automations.changed through the service socket.
    let socket = RuntimeServer(runtime: runtime)
    try socket.start()
    defer { socket.stop() }
    let ui = RuntimeClient(socketName: "daemon.sock")
    var heard = 0
    ui.onEvent = { event in if event.kind == "automations.changed" { heard += 1 } }
    ui.start(role: "ui")
    try await wait("the app connects") { ui.connected }

    // Edits apply to every day: instructions, time, enabled.
    let edited = try routine(edit(daily.ids[3], .init(instructions: "Priorities from ClickUp, Outlook and Slack.", hour: 7, minute: 45)))
    try check(edited.ids.count == 7 && edited.instructions == "Priorities from ClickUp, Outlook and Slack." && edited.hour == 7 && edited.minute == 45,
              "an edit through any day's id answers with the routine changed")
    try check(saved(daily.ids).count == 7 && saved(daily.ids).allSatisfy { $0.instructions == edited.instructions && $0.hour == 7 && $0.minute == 45 },
              "and is saved to every day, where the Mac's runner reads it")
    try check(saved(daily.ids).allSatisfy { !ProjectAutomations.isDue($0, state: nil, now: Date()) },
              "a new time runs from now on: none of its days runs the moment it's set")
    try check(saved([other.id]).first?.instructions == "Only Outlook." && saved([weekly.id]).first?.hour == 9, "other routines are left alone")
    try await wait("automations.changed after an edit") { heard >= 1 }
    try check(true, "the app hears automations.changed")
    let off = try routine(edit(daily.id, .init(enabled: false)))
    try check(!off.enabled && off.nextRunAt == nil && saved(daily.ids).allSatisfy { !$0.enabled }, "switching it off switches off every day")
    let backOn = try routine(edit(daily.id, .init(enabled: true)))
    try check(backOn.enabled && saved(daily.ids).allSatisfy(\.enabled), "and on again")
    try check(try list().count == 4, "still four routines")

    // A day switched off on the Mac: still one routine, that day paused.
    var all = ProjectAutomations.load()
    if let index = all.firstIndex(where: { $0.id == morning[0].id }) { all[index].enabled = false }
    try ProjectAutomations.save(all)
    let mixed = try list().first { $0.id == daily.id }
    try check(mixed?.ids.count == 7 && mixed?.enabled == true && mixed?.pausedDays == [1], "a day off on the Mac: one routine, Sunday paused")
    let allOn = try routine(edit(daily.id, .init(enabled: true)))
    try check(allOn.pausedDays == nil && saved(daily.ids).allSatisfy(\.enabled), "on from the phone: every day on")

    // Days: removing deletes those days' automations; adding copies the routine.
    let weekdays = try routine(edit(daily.ids[6], .init(days: [2, 3, 4, 5, 6])))
    try check(weekdays.days == [2, 3, 4, 5, 6] && weekdays.ids == Array(daily.ids[1...5]), "weekdays only: Sunday's and Saturday's go")
    try check(saved(daily.ids).count == 5 && !ProjectAutomations.load().contains { $0.id == morning[0].id || $0.id == morning[6].id },
              "their automations are deleted")
    let fresh = Date()
    let changedDays = try routine(edit(weekdays.ids[0], .init(days: [2, 4, 6, 7])))
    let added = ProjectAutomations.load().filter { changedDays.ids.contains($0.id) && !morning.map(\.id).contains($0.id) }
    try check(changedDays.days == [2, 4, 6, 7] && changedDays.ids.count == 4 && added.count == 1 && added[0].weekday == 7,
              "Mon, Wed, Fri, Sat: Tue and Thu go, Saturday is added")
    try check(added[0].instructions == edited.instructions && added[0].hour == 7 && added[0].minute == 45 && added[0].backend == "codex"
              && added[0].model == "gpt-5.5" && added[0].effort == "high" && added[0].projectFolder == onTarget.record.projectFolder
              && added[0].title == daily.title && added[0].enabled && added[0].createdAt >= fresh.addingTimeInterval(-1),
              "a new day copies the routine, and runs from now on")
    try check(!ProjectAutomations.isDue(added[0], state: nil, now: Date()), "a new day doesn't run for a time already past")
    let saturday = ProjectAutomations.load().firstIndex { $0.id == added[0].id }, friday = ProjectAutomations.load().firstIndex { $0.id == morning[5].id }
    try check(saturday != nil && friday != nil && saturday! == friday! + 1, "saved beside the routine's other days")

    // The agent: the same one keeps the model; another starts on its defaults.
    let same = try routine(edit(changedDays.id, .init(agent: "codex")))
    try check(same.model == "gpt-5.5" && saved(same.ids).allSatisfy { $0.model == "gpt-5.5" && $0.effort == "high" }, "the agent it has: model and effort stay")
    let claude = try routine(edit(changedDays.id, .init(title: "  Morning priorities  ", agent: "claude")))
    try check(claude.agent == "claude" && claude.model == nil && claude.effort == nil && claude.title == "Morning priorities"
              && saved(claude.ids).allSatisfy { $0.backend == "claude" && $0.model == nil && $0.effort == nil && $0.title == "Morning priorities" },
              "Claude: on its default model and effort, with the new name, every day")
    try check(claude.ids.count == 4, "still one routine")

    // Bad changes are refused, and nothing changes.
    let kept = try Data(contentsOf: ProjectAutomations.configFile)
    let refused: [(Companion.AutomationEdit, String)] = [(.init(days: []), "no days"), (.init(days: [0, 8]), "days that aren't weekdays"),
                                                         (.init(title: "   "), "an empty name"), (.init(hour: 24), "an hour past 23"),
                                                         (.init(minute: 60), "minute 60"), (.init(agent: "gpt"), "an agent that isn't Claude or Codex")]
    for (change, what) in refused {
        try check(try edit(claude.id, change).status == 400, "refused: \(what)")
    }
    try check(try edit(UUID(), .init(enabled: false)).status == 404 && call("POST", "/v1/automations/nope", Data("{}".utf8)).status == 404,
              "an unknown automation: gone")
    try check(call("POST", "/v1/automations/\(claude.id)", Data("not json".utf8)).status == 400, "a body that isn't a change")
    try check(try Data(contentsOf: ProjectAutomations.configFile) == kept, "nothing saved")

    // Run Now: needs the service's runner.
    AutomationRunner.shared = nil
    try check(call("POST", "/v1/automations/\(claude.id)/run").status == 503, "no runner yet: not now")
    let runner = AutomationRunner(model)
    var started: [(automation: ProjectAutomation, manual: Bool)] = []
    runner.startRun = { automation, project, manual in
        started.append((automation, manual))
        let quest = try model.newSidechat(of: project)
        quest.record.sidequestOf = project.id
        quest.setTitle("Automation · " + automation.title)
        return quest
    }
    AutomationRunner.shared = runner
    let heardBeforeRun = heard
    let ran = call("POST", "/v1/automations/\(claude.ids[2])/run")
    try check(ran.status == 200, ran.status == 200 ? "Run Now answers" : "Run Now: \(String(decoding: ran.body, as: UTF8.self))")
    let detail = try Companion.decoder.decode(Companion.ChatDetail.self, from: ran.body)
    let thread = runtime.session(detail.summary.id)
    try check(thread != nil && thread?.record.sidechatOf == onTarget.id && started.count == 1 && started[0].manual
              && claude.ids.contains(started[0].automation.id), "it runs by hand, in a session of its project; the answer is that session")
    let state = ProjectAutomations.loadState()
    try check(state[started[0].automation.id.uuidString]?.threadID == detail.summary.id && state[started[0].automation.id.uuidString]?.lastRun != nil,
              "the run is recorded, as the Mac's Run Now records it")
    let afterRun = try list().first { $0.id == claude.id }
    try check(afterRun?.lastThreadID == detail.summary.id && afterRun?.lastRunAt != nil && afterRun?.isRunning == false,
              "the routine shows its last run and its session")
    try await wait("automations.changed after a run") { heard > heardBeforeRun }
    try check(true, "the app hears the run")

    // The last run still going: left alone. Whichever day's id names it.
    thread?.isRunning = true
    let again = call("POST", "/v1/automations/\(claude.ids[0])/run")
    try check(again.status == 409 && String(decoding: again.body, as: UTF8.self).contains("still going") && started.count == 1,
              "its last run still going: no second run")
    try check(try list().first { $0.id == claude.id }?.isRunning == true, "and the routine says it's running")
    thread?.isRunning = false

    // A retried Run Now (the phone's retry envelope) is answered once, not run twice.
    var envelope = auth
    for (key, value) in call("GET", "/v1/addresses").headers { envelope[key.lowercased()] = value }
    envelope[CompanionRetry.operationHeader.lowercased()] = UUID().uuidString
    let once = request("POST", "/v1/automations/\(claude.id)/run", Data("{}".utf8), envelope)
    let twice = request("POST", "/v1/automations/\(claude.id)/run", Data("{}".utf8), envelope)
    try check(once.status == 200 && twice.body == once.body && started.count == 2, "a retried run replays, once")

    // A closed project's routine can't run; an unknown one is gone.
    let closedRun = call("POST", "/v1/automations/\(paused.id)/run")
    try check(closedRun.status == 409 && String(decoding: closedRun.body, as: UTF8.self).contains("isn't open") && started.count == 2,
              "a closed project's routine: can't run")
    try check(call("POST", "/v1/automations/\(UUID())/run").status == 404, "an unknown routine: gone")

    // Desk refresh reuses the configured routine. Stand-in sessions make this read-only
    // test exercise the real HTTP, state and duplicate guards without calling a model.
    try ProjectAutomations.save(morning + [weekly])
    try check(request("POST", "/v1/desk/check-sources", Data(), [:]).status == 401, "Desk source check needs pairing")
    do { _ = try DeskStore.shared.operation(["action": "checkSources"], agent: true); throw RuntimeFailure("agent started source check") }
    catch { try check(error.localizedDescription.contains("Only you"), "agents cannot request source pulls") }
    let sourceConfig = try Data(contentsOf: ProjectAutomations.configFile)
    let countBefore = started.count
    let pulled = call("POST", "/v1/desk/check-sources")
    try check(pulled.status == 200, "Desk source check starts")
    let pull = try Companion.decoder.decode(Companion.Desk.self, from: pulled.body).sourcePull
    try check(started.count == countBefore + 1 && pull?.lastRequestedAt != nil && pull?.threadID != nil, "Desk exposes last requested time and report session")
    let instructions = started.last!.automation.instructions
    try check(instructions.contains(morningText) && instructions.contains("Read only") && instructions.contains("last verified coverage checkpoint")
              && instructions.contains("desk list --json") && instructions.contains("never advance"), "source check preserves scope, de-duplicates and retains partial-source checkpoints")
    try check(try Data(contentsOf: ProjectAutomations.configFile) == sourceConfig, "manual source check never rewrites configured prompts or schedules")
    let sourceThread = runtime.session(pull!.threadID!)!
    sourceThread.isRunning = true
    let repeated = call("POST", "/v1/desk/check-sources")
    let repeatedDesk = try Companion.decoder.decode(Companion.Desk.self, from: repeated.body)
    try check(repeated.status == 200 && started.count == countBefore + 1 && repeatedDesk.sourcePull?.isRunning == true, "repeated taps reuse the current source check")
    sourceThread.isRunning = false
    try check(call("POST", "/v1/desk/check-sources").status == 200 && started.count == countBefore + 2, "a finished check can be requested again")

    try check(runtime.sessions.allSatisfy { $0.claudeProcess == nil } && !CodexAppServer.shared.isRunning, "no agent started")
    ui.stop()
    runtime.waitForSaves()
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()

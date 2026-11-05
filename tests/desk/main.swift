import Foundation
import Darwin
// The Desk, as the service runs it (plans/front-desk.md): proposals for Studios and projects,
// places, ignore, desk.json across a reload, Needs you and Working from sessions (named as the
// session lists name them), silence (kept, pruned, shown again when something new waits), the
// phone's routes with a paired token, the service socket's "desk" operation and desk.changed, Claude's
// propose_work, and starting a request in a Studio, as a project's work thread, or loose. The board
// (plans/desk-board.md): Ready to mark complete (silenced until something new), Mark complete
// into Done, Reopen, older bodies. Tasks (plans/work-threads.md): a request stays a task once
// started, linked to its thread; Working and Ready show only threads with a task, Needs you every
// thread; link, unlink and Make this a task (one task per thread); a thread archived elsewhere
// completes its task, a deleted one sends it back to To do; desk.json from before tasks. No
// agent ever starts: the first message goes to a stand-in, and the agents' paths lead nowhere.
func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure(text) }; print("PASS: \(text)")
}
@MainActor func wait(_ what: String, seconds: Double = 8, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() { if Date() > until { throw RuntimeFailure("Timed out: \(what)") }; try await Task.sleep(for: .milliseconds(20)) }
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-test-desk."))
    let nowhere = root.appendingPathComponent("no-agent").path
    AppPreferences.defaults.setVolatileDomain(["companionEnabled": true, "mobilePushEnabled": false, "keepMacAwake": false,
                                               "claudePath": nowhere, "codexPath": nowhere, "codexFolder": root.path,
                                               "easyCLIProxyEnabled": false, "remoteControlClaudeChats": false,
                                               // The phone's settings list the PC's models: not from the real PC.
                                               "pcSSHHost": "chatterbox-test-no-pc.invalid"],
                                              forName: UserDefaults.argumentDomain)
    let runtime = try ConversationRuntime(root: root), model = DaemonContext(runtime), server = CompanionServer.shared
    server.model = model
    let desk = DeskStore.shared
    var sent: [(chat: UUID, text: String)] = []
    // What each message went out on: switching a continued session comes first.
    var sentOn: [String] = []
    desk.sendFirstMessage = { session, text in
        sent.append((session.id, text))
        sentOn.append("\(session.record.backend.rawValue) \(session.record.backend == .codex ? session.record.codex?.model ?? "" : session.record.model) \(session.record.backend == .codex ? session.record.codex?.effort ?? "" : session.record.effort)")
        _ = session.appendItem(DisplayItem(kind: .user, text: text))
    }
    var announced: [Companion.Desk] = []
    desk.onChange = { announced.append($0) }

    // Places: two Studios (and an archived one), a project with a brief, its Sidechat.
    func folder(_ name: String) throws -> String {
        let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url.path
    }
    var archery = Studio(name: "USA Archery", folder: try folder("USA Archery"))
    archery.instructions = "Website, print and marketing for USA Archery: banners, flyers, guides and the homepage."
    var playcase = Studio(name: "PlayCase Arcade", folder: try folder("PlayCase Arcade"))
    playcase.instructions = "The PlayCase Arcade iOS games, levels, App Store builds and TestFlight."
    var old = Studio(name: "Old Studio", folder: try folder("Old Studio")); old.archivedAt = Date()
    try runtime.updateStudios([archery, playcase, old])
    func record(_ title: String, studio: Studio? = nil, items: [DisplayItem] = []) -> ConversationRecord {
        var r = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
        r.title = title; r.studioID = studio?.id; r.studioFolder = studio?.folder; r.items = items
        return r
    }
    var dogearRecord = record("Dogear", items: [DisplayItem(kind: .user, text: "Ship it"), DisplayItem(kind: .assistant, text: "Shipped.", phase: .final)])
    dogearRecord.projectFolder = try folder("Dogear"); dogearRecord.projectNickname = "Dogear"
    dogearRecord.brief = "A reading app for iPhone: highlights, bookmarks and the book import."
    let dogear = try runtime.insert(dogearRecord)
    _ = try model.newSidechat(of: dogear)

    // The phone's routes need a paired token.
    func request(_ method: String, _ path: String, _ body: Data = Data(), _ headers: [String: String], query: [String: String] = [:]) -> HTTPResponse {
        server.respond(to: HTTPRequest(method: method, path: path, query: query, headers: headers, body: body))
    }
    let paired = request("POST", "/v1/pair", try Companion.encoder.encode(Companion.PairRequest(code: server.pairingCode, deviceName: "Desk fixture")), [:])
    try check(paired.status == 200, "a phone pairs")
    let token = try Companion.decoder.decode(Companion.PairResponse.self, from: paired.body).token
    let auth = [Companion.tokenHeader.lowercased(): token]
    func call(_ method: String, _ path: String, _ body: Data = Data(), query: [String: String] = [:]) -> HTTPResponse { request(method, path, body, auth, query: query) }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys; e.dateEncodingStrategy = .iso8601; return try e.encode(value)
    }
    func deskOf(_ response: HTTPResponse) throws -> Companion.Desk { try Companion.decoder.decode(Companion.Desk.self, from: response.body) }
    func add(_ text: String, place: String? = nil, note: String? = nil) throws -> HTTPResponse {
        call("POST", "/v1/desk", try encode(Companion.DeskAddRequest(text: text, place: place, note: note)))
    }

    try check(request("GET", "/v1/desk", Data(), [:]).status == 401, "the Desk needs a paired token")
    try check(request("POST", "/v1/desk", try encode(Companion.DeskAddRequest(text: "x")), [:]).status == 401 && desk.requests.isEmpty, "adding needs one too")
    let empty = try deskOf(call("GET", "/v1/desk"))
    try check(empty.needsYou.isEmpty && empty.incoming.isEmpty && empty.working.isEmpty, "a healthy Desk is empty")

    // Proposals: a Studio from its instructions, a project from its brief, nothing when unsure.
    let banner = try add("Banner ideas for the fall camp flyers and the homepage")
    let bannerDesk = try deskOf(banner)
    let bannerRequest = bannerDesk.incoming[0]
    try check(banner.status == 200 && bannerRequest.proposed == .init(kind: "studio", id: archery.id, name: "USA Archery", detail: archery.instructions)
              && bannerRequest.source == "you", "a request is proposed for the Studio it fits, from you")
    try check(bannerDesk.revision > empty.revision && announced.last?.revision == bannerDesk.revision, "adding changes the revision and is announced")
    let highlights = try deskOf(add("Fix the highlights sync, the bookmarks list and the book import")).incoming[0]
    try check(highlights.proposed?.kind == "project" && highlights.proposed?.id == dogear.id && highlights.proposed?.name == "Dogear"
              && highlights.proposed?.detail == dogearRecord.brief, "a request is proposed for the project its brief fits")
    let weather = try deskOf(add("What's the weather tomorrow?")).incoming[0]
    try check(weather.proposed == nil, "nothing clearly fits: no proposal")
    let named = try deskOf(add("Look at this", place: "playcase arcade", note: "It's the game's art")).incoming[0]
    try check(named.proposed?.id == playcase.id && named.note == "It's the game's art", "a named place is proposed, with the note")
    try check(try deskOf(add("Loose thing", place: "loose")).incoming[0].proposed == DeskStore.loose, "loose can be named")
    let unknown = try add("Something", place: "Nowhere")
    try check(unknown.status == 404 && desk.requests.count == 5, "an unknown place is refused, nothing added")
    try check(try add("   ").status == 400 && call("POST", "/v1/desk", Data("{}".utf8)).status == 400, "nothing to do is refused")
    let incoming = try deskOf(call("GET", "/v1/desk")).incoming
    try check(incoming.map(\.text) == ["Loose thing", "Look at this", "What's the weather tomorrow?",
                                       "Fix the highlights sync, the bookmarks list and the book import",
                                       "Banner ideas for the fall camp flyers and the homepage"], "incoming is newest first")

    // Places: open Studios with instructions, the project's own session with its brief, loose last.
    let places = try Companion.decoder.decode([Companion.DeskPlace].self, from: call("GET", "/v1/desk/places").body)
    try check(places.map(\.name) == ["PlayCase Arcade", "USA Archery", "Dogear", "Loose session"]
              && places.map(\.kind) == ["studio", "studio", "project", "loose"], "places: Studios, projects, then loose: \(places.map(\.name))")
    try check(places[1].id == archery.id && places[1].detail == archery.instructions && places[2].id == dogear.id
              && places[2].detail == dogearRecord.brief && places[3].id == nil, "each place says what belongs there")

    // Ignore.
    let ignored = try deskOf(call("POST", "/v1/desk/\(weather.id)/ignore", Data("{}".utf8)))
    try check(!ignored.incoming.contains { $0.id == weather.id } && ignored.incoming.count == 4, "ignore takes it off the Desk")
    try check(call("POST", "/v1/desk/\(weather.id)/ignore").status == 404, "ignoring it again: gone")

    // Kept across a reload: desk.json in the data folder.
    let file = root.appendingPathComponent("desk.json")
    let reloaded = DeskStore(file: file)
    try check(reloaded.requests == desk.requests && reloaded.tasks == desk.tasks && reloaded.revision == desk.revision + 1, "the tasks and revision survive a reload")
    let bad = root.appendingPathComponent("broken.json"); try Data("not json".utf8).write(to: bad)
    try check(DeskStore(file: bad).requests.isEmpty && FileManager.default.fileExists(atPath: root.appendingPathComponent("broken.unreadable.json").path)
              && !FileManager.default.fileExists(atPath: bad.path), "an unreadable desk.json is kept aside, not overwritten")

    // A retried add (the phone's retry envelope) is answered once, not added twice.
    var envelope = auth
    for (key, value) in call("GET", "/v1/addresses").headers { envelope[key.lowercased()] = value }
    envelope[CompanionRetry.operationHeader.lowercased()] = UUID().uuidString
    let once = try encode(Companion.DeskAddRequest(text: "Retry me"))
    let first = request("POST", "/v1/desk", once, envelope), again = request("POST", "/v1/desk", once, envelope)
    try check(first.status == 200 && again.body == first.body && desk.requests.filter { $0.text == "Retry me" }.count == 1, "a retried add replays, once")
    let retried = desk.requests.first { $0.text == "Retry me" }!

    // Needs you: an approval, a plan, questions, a question in a reply; Working: what's running.
    var deployItem = DisplayItem(kind: .approval, text: "Run deploy.sh", approvalState: .pending)
    deployItem.detail = "./deploy.sh --env production\n--force"
    let approval = try runtime.insert(record("Deploy the site", studio: archery, items: [DisplayItem(kind: .user, text: "Deploy"), deployItem]))
    approval.isRunning = true
    let plan = try runtime.insert(record("Plan the levels", items: [
        DisplayItem(kind: .user, text: "Plan"), DisplayItem(kind: .approval, text: "Claude has a plan. Start building?", approvalState: .pending, approvalStyle: .plan)]))
    let asking = try runtime.insert(record("Banner sizes", studio: archery, items: [
        DisplayItem(kind: .user, text: "Banners"),
        DisplayItem(kind: .questions, approvalState: .pending, questions: [
            AgentQuestion(id: "size", header: "Size", question: "Which banner size?", options: [.init(label: "Wide", detail: "1920 by 600")], multiSelect: false, isSecret: false),
            AgentQuestion(id: "color", header: "Color", question: "Which color?", options: [.init(label: "Blue", detail: "")], multiSelect: false, isSecret: false)])]))
    let replied = try runtime.insert(record("Ship Dogear", items: [
        DisplayItem(kind: .user, text: "Get it ready"), DisplayItem(kind: .assistant, text: "Done: the build passes.\n\n**Want me to upload it to TestFlight?**", phase: .final)]))
    let oldQuestion = try runtime.insert(record("Old question", items: [
        DisplayItem(kind: .user, text: "Hi"), DisplayItem(kind: .assistant, timestamp: Date().addingTimeInterval(-3 * 86_400), text: "Shall I go on?", phase: .final)]))
    let finished = try runtime.insert(record("Finished", items: [DisplayItem(kind: .user, text: "Hi"), DisplayItem(kind: .assistant, text: "All done. The flyers are in the folder.", phase: .final)]))
    let busy = try runtime.insert(record("Render the poster", studio: playcase, items: [DisplayItem(kind: .user, text: "Render")]))
    busy.isRunning = true
    let sidechat = try model.newSidechat(of: dogear)
    sidechat.isRunning = true
    let now = try deskOf(call("GET", "/v1/desk"))
    func waiting(_ chat: ChatSession) -> Companion.DeskWaiting? { now.needsYou.first { $0.chatID == chat.id } }
    try check(waiting(approval)?.kind == "approval" && waiting(approval)?.text == "Run deploy.sh" && waiting(approval)?.place == "USA Archery"
              && waiting(approval)?.id == approval.items[1].id, "needs you: a pending approval, with its place and item id")
    try check(waiting(approval)?.detail == "./deploy.sh --env production\n--force", "an approval carries its exact command, lines kept")
    try check(waiting(plan)?.kind == "plan" && waiting(plan)?.place == nil && waiting(plan)?.detail == nil, "needs you: a plan, without a command")
    try check(waiting(asking)?.kind == "questions" && waiting(asking)?.questions?.map(\.id) == ["size", "color"]
              && waiting(asking)?.questions?.first?.options.first?.label == "Wide" && waiting(asking)?.text == "Which banner size? (and 1 more)",
              "needs you: questions, with the questions to answer in place")
    try check(waiting(replied)?.kind == "reply" && waiting(replied)?.text == "Want me to upload it to TestFlight?" && waiting(replied)?.id == replied.id,
              "needs you: a reply that ends on a question")
    try check(now.needsYou.count == 4, "not an old question, a finished reply, or a running session: \(now.needsYou.map(\.title))")
    try check(now.needsYou.allSatisfy { $0.task == nil } && now.working.isEmpty && (now.ready ?? []).isEmpty,
              "threads with no task: only in Needs you (marked as not a task), never Working or Ready")
    // Make this a task: a new task, already linked; then it's on the board by its thread's state.
    func makeTask(_ chat: ChatSession, _ text: String? = nil) throws -> Companion.Desk {
        let response = call("POST", "/v1/desk/task", try encode(Companion.DeskTaskRequest(chatID: chat.id, text: text)))
        try check(response.status == 200, "make a task answers with the Desk")
        return try deskOf(response)
    }
    _ = try makeTask(busy)
    let tasked = try makeTask(sidechat, "Highlights pass")
    try check(tasked.working.map(\.id).sorted { $0.uuidString < $1.uuidString } == [busy.id, sidechat.id].sorted { $0.uuidString < $1.uuidString }
              && tasked.working.first { $0.id == busy.id }?.place == "PlayCase Arcade" && tasked.working.first { $0.id == sidechat.id }?.place == "Dogear",
              "working: running threads with a task, with their places, not one waiting on you")
    try check(tasked.working.first { $0.id == busy.id }?.taskText == "Render the poster" && tasked.working.first { $0.id == sidechat.id }?.taskText == "Highlights pass"
              && tasked.linked?.contains { $0.chatID == sidechat.id && $0.text == "Highlights pass" } == true && !tasked.incoming.contains { $0.text == "Highlights pass" },
              "a made task is named for its thread (or as given), linked, not to do")
    try check(desk.tasks.first { $0.chatID == busy.id }?.proposed?.id == playcase.id && desk.tasks.first { $0.chatID == sidechat.id }?.proposed?.id == dogear.id,
              "in its thread's place: the Studio, or the project for its Sidechat")
    try check(call("POST", "/v1/desk/task", try encode(Companion.DeskTaskRequest(chatID: busy.id))).status == 409, "one task per thread: a second is refused")
    try check(call("POST", "/v1/desk/task", try encode(Companion.DeskTaskRequest(chatID: UUID()))).status == 404, "a thread that's gone: 404")
    try check(try deskOf(call("GET", "/v1/desk")).revision == tasked.revision, "nothing changed: the same revision")
    sidechat.isRunning = false
    let quieter = try deskOf(call("GET", "/v1/desk"))
    try check(quieter.revision > tasked.revision && quieter.working.map(\.id) == [busy.id] && quieter.ready?.first?.id == sidechat.id
              && quieter.ready?.first?.text == "No reply yet." && announced.last?.revision == quieter.revision,
              "a thread stopping moves its task to Ready; the revision changes, and is announced")
    // Unlink: back to To do; the thread carries on, off Working and Ready.
    let sidechatTask = desk.openTask(for: sidechat.id)!.id
    let unlinked = try deskOf(call("POST", "/v1/desk/\(sidechatTask)/unlink"))
    try check(unlinked.incoming.first { $0.id == sidechatTask }?.text == "Highlights pass" && unlinked.ready?.contains { $0.id == sidechat.id } == false
              && desk.openTask(for: sidechat.id) == nil, "unlink: the task goes back to To do; the thread leaves the board")
    try check(call("POST", "/v1/desk/\(UUID())/unlink").status == 404, "unlinking a task that's gone: 404")
    _ = try desk.ignore(sidechatTask)
    try check(DeskStore.question(in: "Here it is:\n```\nwhy?\n```") == nil && DeskStore.question(in: "All set.") == nil
              && DeskStore.question(in: "1. One\n2. Two\n\nWhich do you want? (A or B)") == nil
              && DeskStore.question(in: "Ready. Should I open v1.2 or v2?") == "Should I open v1.2 or v2?", "a question in a reply, only at its end")

    // Named as the session lists name them: a project's session by its project, its own title
    // under that; a worktree's by its branch; others by their title.
    var buildingRecord = record("Building Chatterbox", items: [
        DisplayItem(kind: .user, text: "Build it"), DisplayItem(kind: .assistant, text: "The build passes. Want me to?", phase: .final)])
    buildingRecord.projectFolder = try folder("Chatterbox"); buildingRecord.projectNickname = "Chatterbox"
    let building = try runtime.insert(buildingRecord)
    var branchRecord = record("Fix the highlight sync")
    branchRecord.projectFolder = try folder("Dogear-highlights"); branchRecord.worktreeOf = dogearRecord.projectFolder
    branchRecord.worktreeBranch = "highlights-sync"; branchRecord.projectNickname = "Dogear"
    let branch = try runtime.insert(branchRecord)
    branch.isRunning = true
    _ = try makeTask(branch)
    let named1 = try deskOf(call("GET", "/v1/desk"))
    let buildingWaiting = named1.needsYou.first { $0.chatID == building.id }
    let list = try Companion.decoder.decode(Companion.ChatList.self, from: call("GET", "/v1/chats").body)
    let listed = list.groups.flatMap(\.chats).first { $0.id == building.id }
    try check(buildingWaiting?.title == "Chatterbox" && buildingWaiting?.subtitle == "Building Chatterbox" && buildingWaiting?.place == "Chatterbox"
              && buildingWaiting?.text == "Want me to?" && buildingWaiting?.title == listed?.project,
              "a project's session: its project's name, as the list has it, and its own title under it: \(String(describing: buildingWaiting))")
    let branchWorking = named1.working.first { $0.id == branch.id }
    try check(branchWorking?.title == "highlights-sync" && branchWorking?.subtitle == "Fix the highlight sync" && branchWorking?.place == "Dogear",
              "a worktree's session: its branch, its own title under it: \(String(describing: branchWorking))")
    let deploy = named1.needsYou.first { $0.chatID == approval.id }
    try check(deploy?.title == "Deploy the site" && deploy?.subtitle == nil && deploy?.place == "USA Archery", "a Studio's session: its title, nothing under it")
    try check(named1.needsYou.first { $0.chatID == replied.id }?.subtitle == nil, "a loose session: its title")
    branch.isRunning = false

    // Silence: off the Desk (and its counts) on every device, still waiting in its session.
    try check(call("POST", "/v1/desk/silence", Data("{}".utf8)).status == 400, "silence needs what to silence")
    let approvalItem = approval.items[1].id
    func silence(_ chat: UUID, _ id: UUID, _ text: String? = nil) throws -> Companion.Desk {
        let response = call("POST", "/v1/desk/silence", try encode(Companion.DeskSilenceRequest(chatID: chat, id: id, text: text)))
        try check(response.status == 200, "silence answers with the Desk")
        return try deskOf(response)
    }
    let beforeSilence = try deskOf(call("GET", "/v1/desk"))
    let quiet = try silence(approval.id, approvalItem, "Run deploy.sh")
    try check(!quiet.needsYou.contains { $0.chatID == approval.id } && quiet.needsYou.count == beforeSilence.needsYou.count - 1,
              "a silenced approval leaves Needs you, and its count")
    try check(quiet.silenced?.map(\.id) == [approvalItem] && approval.items[1].approvalState == .pending && approval.pendingRequests.map(\.id) == [approvalItem],
              "listed as silenced; the approval stays pending in its session")
    try check(approval.isRunning && !quiet.working.contains { $0.id == approval.id }, "waiting on what's silenced: not Working either")
    try check(quiet.revision > beforeSilence.revision && announced.last?.revision == quiet.revision, "silencing changes the revision, and is announced")
    try check(try silence(approval.id, approvalItem).revision == quiet.revision && desk.silences.count == 1, "silencing it again changes nothing")
    // A reply: the question it asks says which one; an old copy of it silences nothing.
    let stale = try silence(replied.id, replied.id, "Want me to upload it somewhere else?")
    try check(stale.needsYou.contains { $0.chatID == replied.id } && desk.silences.count == 1, "a reply that's since changed isn't silenced")
    let quieter2 = try silence(replied.id, replied.id, "Want me to upload it to TestFlight?")
    try check(!quieter2.needsYou.contains { $0.chatID == replied.id } && quieter2.silenced?.contains { $0.chatID == replied.id && $0.kind == "reply" } == true,
              "a silenced reply leaves Needs you")
    try check(try silence(UUID(), UUID()).revision == quieter2.revision, "something not waiting: nothing changes")
    // Unsilence (Undo, and the silenced list): back on the Desk on every device; the same body.
    func unsilence(_ chat: UUID, _ id: UUID, _ text: String? = nil) throws -> Companion.Desk {
        let response = call("POST", "/v1/desk/unsilence", try encode(Companion.DeskSilenceRequest(chatID: chat, id: id, text: text)))
        try check(response.status == 200, "unsilence answers with the Desk")
        return try deskOf(response)
    }
    try check(call("POST", "/v1/desk/unsilence", Data("{}".utf8)).status == 400, "unsilence needs what to unsilence")
    let back = try unsilence(approval.id, approvalItem)
    try check(back.needsYou.first { $0.chatID == approval.id }?.id == approvalItem && back.silenced?.contains { $0.id == approvalItem } == false
              && desk.silences.count == 1, "an unsilenced approval is back in Needs you, off the silenced list")
    try check(back.revision > quieter2.revision && announced.last?.revision == back.revision, "unsilencing changes the revision, and is announced")
    try check(try unsilence(approval.id, approvalItem).revision == back.revision && (try unsilence(UUID(), UUID())).revision == back.revision,
              "unsilencing what isn't silenced changes nothing")
    try check(try unsilence(replied.id, replied.id, "Want me to upload it somewhere else?").silenced?.contains { $0.chatID == replied.id } == true,
              "a reply's unsilence names what it asked")
    // The service socket's "desk" operation (the Mac app) takes the same body.
    let unsilencedViaSocket = try desk.operation(.object(["action": "unsilence", "chatID": .string(replied.id.uuidString), "id": .string(replied.id.uuidString),
                                                "text": "Want me to upload it to TestFlight?"]), agent: false).decode(Companion.Desk.self)
    try check(unsilencedViaSocket.needsYou.contains { $0.chatID == replied.id } && desk.silences.isEmpty && unsilencedViaSocket.silenced?.isEmpty == true,
              "socket: unsilence puts a reply back")
    var refused = false
    do { _ = try desk.operation(.object(["action": "unsilence"]), agent: false) } catch { refused = true }
    try check(refused, "socket: unsilence needs what to unsilence")
    // Silenced again, as before, for what follows.
    _ = try silence(approval.id, approvalItem)
    _ = try desk.operation(.object(["action": "silence", "chatID": .string(replied.id.uuidString), "id": .string(replied.id.uuidString),
                                    "text": "Want me to upload it to TestFlight?"]), agent: false)
    try check(desk.silences.count == 2, "silenced again")
    // Kept across a reload, in desk.json; an older desk.json without silences still loads.
    let kept = DeskStore(file: file)
    try check(kept.silences == desk.silences && kept.silences.count == 2 && !kept.snapshot().needsYou.contains { $0.chatID == approval.id || $0.chatID == replied.id },
              "silences survive a reload")
    let older = root.appendingPathComponent("desk-older.json")
    try Data(#"{"revision":7,"requests":[{"id":"\#(UUID().uuidString)","text":"Old request","source":"you","createdAt":"2026-11-01T10:00:00Z"}]}"#.utf8).write(to: older)
    let olderStore = DeskStore(file: older)
    try check(olderStore.requests.map(\.text) == ["Old request"] && olderStore.silences.isEmpty && olderStore.tasks.map(\.text) == ["Old request"]
              && olderStore.tasks.allSatisfy { $0.chatID == nil && $0.isOpen } && olderStore.revision == 8,
              "a desk.json from before silencing (and the board, and tasks) loads: its requests are tasks to do")
    // Something new from the same session shows again.
    _ = replied.appendItem(DisplayItem(kind: .user, text: "Not yet"))
    _ = replied.appendItem(DisplayItem(kind: .assistant, text: "Fine. Shall I tag the release instead?", phase: .final))
    let newer = try deskOf(call("GET", "/v1/desk"))
    try check(newer.needsYou.first { $0.chatID == replied.id }?.text == "Shall I tag the release instead?", "a newer reply that asks shows again")
    try check(!desk.silences.contains { $0.chatID == replied.id } && newer.silenced?.map(\.id) == [approvalItem], "and the old reply's silence is gone")
    _ = approval.appendItem(DisplayItem(kind: .approval, text: "Run publish.sh", approvalState: .pending))
    let next = try deskOf(call("GET", "/v1/desk"))
    try check(next.needsYou.first { $0.chatID == approval.id }?.text == "Run publish.sh" && next.silenced?.map(\.id) == [approvalItem],
              "a new approval in the same session shows; the silenced one stays silenced")
    // Answered in its session, a silenced approval's silence goes.
    if let index = approval.record.items.firstIndex(where: { $0.id == approvalItem }) { approval.record.items[index].approvalState = .denied }
    let answered = try deskOf(call("GET", "/v1/desk"))
    try check(desk.silences.isEmpty && answered.silenced?.isEmpty == true && answered.needsYou.first { $0.chatID == approval.id }?.text == "Run publish.sh",
              "silences that no longer match anything waiting are pruned")
    try await wait("the pruned silences saved") { DeskStore(file: file).silences.isEmpty }

    // The board (plans/desk-board.md). Working says what each is doing.
    try check(answered.working.first { $0.id == busy.id }?.activity == "Working\u{2026}", "working: what it's doing now")
    // The board's tasks done with for what follows.
    for chat in [busy, branch] { if let task = desk.openTask(for: chat.id) { try desk.unlink(task.id); try desk.ignore(task.id) } }
    // Ready to mark complete: a thread with a task, idle, asking nothing, however long ago.
    func reply(_ text: String, daysAgo: Double = 0) -> [DisplayItem] {
        [DisplayItem(kind: .user, text: "Go"), DisplayItem(kind: .assistant, timestamp: Date().addingTimeInterval(-daysAgo * 86_400), text: text, phase: .final)]
    }
    let weekOld = try runtime.insert(record("Last month's flyers", items: reply("Done.", daysAgo: 8)))
    let sixDays = try runtime.insert(record("Camp schedule", studio: archery, items: reply("The schedule is posted.", daysAgo: 6)))
    var questRecord = record("A sidequest", items: reply("Found it.")); questRecord.sidequestOf = finished.id
    let quest = try runtime.insert(questRecord)
    var runRecord = record("Morning run", items: reply("Three priorities.")); runRecord.automationID = UUID()
    let run = try runtime.insert(runRecord)
    var shelvedRecord = record("Shelved", items: reply("Done.")); shelvedRecord.archivedAt = Date()
    let shelved = try runtime.insert(shelvedRecord)
    let stillGoing = try runtime.insert(record("Still going", items: reply("Halfway there.")))
    stillGoing.isRunning = true
    let untasked = try deskOf(call("GET", "/v1/desk"))
    try check(untasked.ready?.isEmpty == true && untasked.working.isEmpty, "finished threads with no task aren't Ready (or Working)")
    for chat in [finished, weekOld, sixDays, stillGoing, dogear] { _ = try makeTask(chat) }
    try check(call("POST", "/v1/desk/task", try encode(Companion.DeskTaskRequest(chatID: quest.id))).status == 409
              && call("POST", "/v1/desk/task", try encode(Companion.DeskTaskRequest(chatID: run.id))).status == 409
              && call("POST", "/v1/desk/task", try encode(Companion.DeskTaskRequest(chatID: shelved.id))).status == 404,
              "sidequests and automation runs aren't tasks; an archived thread can't be made one")
    let board = try deskOf(call("GET", "/v1/desk"))
    let ready = board.ready ?? []
    func readyItem(_ chat: ChatSession) -> Companion.DeskReady? { ready.first { $0.id == chat.id } }
    try check(readyItem(finished)?.text == "All done." && readyItem(finished)?.title == "Finished" && readyItem(finished)?.place == nil
              && readyItem(finished)?.taskText == "Finished",
              "ready: a finished reply, its first sentence, with its task: \(String(describing: readyItem(finished)))")
    try check(readyItem(sixDays)?.place == "USA Archery" && readyItem(weekOld) != nil && readyItem(dogear)?.title == "Dogear",
              "a task stays Ready however old its reply; named as the lists name it")
    try check([quest, run, shelved, stillGoing, approval, replied, plan, asking, busy, oldQuestion].allSatisfy { readyItem($0) == nil },
              "not a sidequest, an automation run, archived, working, waiting on you, or a thread with no task: \(ready.map(\.title))")
    try check(board.working.map(\.id) == [stillGoing.id], "a working thread with a task is Working")
    try check(ready.map(\.finishedAt) == ready.map(\.finishedAt).sorted(by: >) && ready.last?.id == weekOld.id, "newest first")
    try check(board.done?.isEmpty == true, "nothing done yet")
    // Silencing a ready task hides it until something new happens in its thread.
    let staleReady = try silence(finished.id, finished.id, "Something it no longer says.")
    try check(staleReady.ready?.contains { $0.id == finished.id } == true && desk.silences.isEmpty, "a ready session that's since changed isn't silenced")
    let quietReady = try silence(finished.id, finished.id, "All done.")
    try check(quietReady.ready?.contains { $0.id == finished.id } == false && desk.silences.map(\.kind) == ["ready"]
              && quietReady.silenced?.contains { $0.chatID == finished.id } != true && finished.record.archivedAt == nil,
              "silenced: off Ready, not archived, and not in the waiting silences")
    try check(DeskStore(file: file).silences.map(\.kind) == ["ready"], "kept in desk.json")
    _ = finished.appendItem(DisplayItem(kind: .user, text: "One more thing"))
    _ = finished.appendItem(DisplayItem(kind: .assistant, text: "Added the back page too.", phase: .final))
    let shownAgain = try deskOf(call("GET", "/v1/desk"))
    try check(shownAgain.ready?.first { $0.id == finished.id }?.text == "Added the back page too." && desk.silences.isEmpty,
              "something new shows it again, and the silence goes")
    // Mark complete: archives the thread, its task into Done; refused while working.
    try check(call("POST", "/v1/desk/complete", Data("{}".utf8)).status == 400, "complete needs a session")
    try check(call("POST", "/v1/desk/complete", try encode(Companion.DeskSessionRequest(chatID: UUID()))).status == 404, "a session that's gone: 404")
    try check(call("POST", "/v1/desk/complete", try encode(Companion.DeskSessionRequest(chatID: stillGoing.id))).status == 409 && stillGoing.record.archivedAt == nil,
              "a working session isn't completed (or stopped)")
    let finishedTask = desk.openTask(for: finished.id)!.id
    let completedResponse = call("POST", "/v1/desk/complete", try encode(Companion.DeskSessionRequest(chatID: finished.id)))
    let completed = try deskOf(completedResponse)
    try check(completedResponse.status == 200 && finished.record.archivedAt != nil, "complete archives the thread")
    try check(completed.done?.map(\.id) == [finished.id] && completed.done?.first?.title == "Finished" && completed.done?.first?.task == finishedTask
              && completed.ready?.contains { $0.id == finished.id } == false && completed.linked?.first { $0.id == finishedTask }?.completedAt != nil,
              "and its task moves from Ready to Done")
    try check(completed.revision > shownAgain.revision && announced.last?.revision == completed.revision, "completing changes the revision, and is announced")
    try check(DeskStore(file: file).tasks.first { $0.id == finishedTask }?.completedAt != nil, "completed tasks are kept in desk.json")
    // Done is a week: an older completed task goes.
    let lastWeek = root.appendingPathComponent("desk-last-week.json")
    var aged = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    aged["tasks"] = (aged["tasks"] as! [[String: Any]]).map { task in
        var task = task
        if task["id"] as? String == finishedTask.uuidString { task["completedAt"] = "2026-01-01T10:00:00Z" }
        return task
    }
    try JSONSerialization.data(withJSONObject: aged).write(to: lastWeek)
    let agedStore = DeskStore(file: lastWeek)
    try check(agedStore.snapshot().done?.isEmpty == true && !agedStore.tasks.contains { $0.id == finishedTask },
              "Done: tasks completed in the last week only; older ones are pruned")
    // Reopen: unarchived, the task out of Done, and ready again.
    let reopened = try deskOf(call("POST", "/v1/desk/reopen", try encode(Companion.DeskSessionRequest(chatID: finished.id))))
    try check(finished.record.archivedAt == nil && reopened.done?.isEmpty == true && reopened.ready?.contains { $0.id == finished.id } == true
              && desk.openTask(for: finished.id)?.id == finishedTask, "reopen unarchives it: the task out of Done, back in Ready")
    try check(call("POST", "/v1/desk/reopen", try encode(Companion.DeskSessionRequest(chatID: UUID()))).status == 404, "reopening a session that's gone: 404")
    // Archived elsewhere (not from the board): its task is done; unarchived elsewhere, open again.
    model.archive(sixDays)
    let elsewhereArchived = try deskOf(call("GET", "/v1/desk"))
    try check(elsewhereArchived.done?.first?.id == sixDays.id && elsewhereArchived.ready?.contains { $0.id == sixDays.id } == false,
              "archived elsewhere: its task goes to Done")
    sixDays.setArchived(false)
    try check(try deskOf(call("GET", "/v1/desk")).ready?.contains { $0.id == sixDays.id } == true && desk.openTask(for: sixDays.id) != nil,
              "unarchived elsewhere: open again, Ready")
    // Deleted: its task goes back to To do.
    let sixDaysTask = desk.openTask(for: sixDays.id)!.id
    try runtime.remove(sixDays.id)
    try check(try deskOf(call("GET", "/v1/desk")).incoming.contains { $0.id == sixDaysTask }, "a deleted thread's task shows in To do at once")
    desk.threadDeleted(sixDays.id)
    try check(desk.tasks.first { $0.id == sixDaysTask }?.chatID == nil && desk.requests.contains { $0.id == sixDaysTask },
              "and its deletion unlinks it for good")
    try desk.ignore(sixDaysTask)
    for chat in [weekOld, dogear] { if let task = desk.openTask(for: chat.id) { try desk.unlink(task.id); try desk.ignore(task.id) } }
    // Older phones and services: bodies without the board still decode, and older ones ignore it.
    let olderDesk = try Companion.decoder.decode(Companion.Desk.self, from: Data(#"{"revision":3,"needsYou":[],"incoming":[],"working":[{"id":"\#(UUID().uuidString)","title":"Galley","place":null}]}"#.utf8))
    try check(olderDesk.ready == nil && olderDesk.done == nil && olderDesk.working.first?.activity == nil, "a Desk from an older service decodes, without the board's columns")
    struct OlderDesk: Decodable { var revision: Int; var needsYou: [Companion.DeskWaiting]; var incoming: [Companion.DeskRequest]; var working: [Companion.DeskWorking] }
    try check((try? Companion.decoder.decode(OlderDesk.self, from: call("GET", "/v1/desk").body))?.working.isEmpty == false, "an older phone reads the new Desk")
    stillGoing.isRunning = false

    // Start: in its Studio, as the project's Sidechat, or loose; never an agent.
    let started = call("POST", "/v1/desk/\(bannerRequest.id)/start", Data("{}".utf8))
    let detail = try Companion.decoder.decode(Companion.ChatDetail.self, from: started.body)
    let bannerChat = runtime.session(detail.summary.id)
    try check(started.status == 200 && bannerChat?.record.studioID == archery.id && bannerChat?.record.studioFolder == archery.folder,
              "start: a new session in the proposed Studio")
    try check(detail.summary.title == "Banner ideas for the fall camp flyers and the\u{2026}" && sent.last?.chat == detail.summary.id
              && sent.last?.text == bannerRequest.text && detail.items.contains { $0.kind == .user && $0.text == bannerRequest.text },
              "named from the request, which is its first message: \(detail.summary.title)")
    let afterStart = try deskOf(call("GET", "/v1/desk"))
    try check(!desk.requests.contains { $0.id == bannerRequest.id } && !afterStart.incoming.contains { $0.id == bannerRequest.id },
              "and the request leaves To do")
    try check(desk.openTask(for: detail.summary.id)?.id == bannerRequest.id && afterStart.linked?.contains { $0.id == bannerRequest.id && $0.chatID == detail.summary.id } == true
              && afterStart.ready?.first { $0.id == detail.summary.id }?.task == bannerRequest.id,
              "it stays a task, linked to the session it started, and moves with it (Ready: it isn't working)")
    try check(call("POST", "/v1/desk/\(bannerRequest.id)/start", Data("{}".utf8)).status == 404, "starting it again: gone")
    let side = try Companion.decoder.decode(Companion.ChatDetail.self, from: call("POST", "/v1/desk/\(highlights.id)/start", Data("{}".utf8)).body)
    let sideChat = runtime.session(side.summary.id)
    try check(sideChat?.record.sidechatOf == dogear.id && side.summary.sidechatOf == dogear.id && sideChat?.record.projectFolder == nil
              && side.summary.title.hasPrefix("Fix the highlights sync"), "start: a project's work is a new Sidechat of it")
    try check(sideChat?.record.workOf == dogear.id && side.summary.workOf == dogear.id && sideChat?.record.parentContext == nil
              && sideChat?.record.pendingHandoff?.contains("<work_thread>") == true && sideChat?.record.pendingHandoff?.contains("Ship it") != true,
              "…a work thread of the project's session, framed as one, without its transcript")
    try check(dogear.items.last?.kind == .notice && dogear.items.last?.sidequest == side.summary.id && desk.openTask(for: side.summary.id)?.id == highlights.id,
              "the project's session hears it started, with a way to open it; the task is linked to it")
    try check(call("POST", "/v1/desk/\(retried.id)/start", Data("{}".utf8)).status == 400 && desk.requests.contains { $0.id == retried.id },
              "no place proposed or chosen: refused, and kept")
    let loose = Companion.DeskStartRequest(place: DeskStore.loose, agent: "codex")
    let looseDetail = try Companion.decoder.decode(Companion.ChatDetail.self, from: call("POST", "/v1/desk/\(named.id)/start", try encode(loose)).body)
    let looseChat = runtime.session(looseDetail.summary.id)
    try check(looseChat?.record.studioID == nil && looseChat?.record.sidechatOf == nil && looseChat?.record.projectFolder == nil
              && looseChat?.record.backend == .codex, "start: another place (loose) and agent chosen instead")
    try check(sent.last?.text == "Look at this\n\n---\nNote from Shelby with this request: It's the game's art", "the note goes along, labelled")
    try check(call("POST", "/v1/desk/\(retried.id)/start", try encode(Companion.DeskStartRequest(place: .init(kind: "studio", id: old.id, name: "Old Studio")))).status == 404
              && desk.requests.contains { $0.id == retried.id }, "a Studio that's gone: refused, and kept")
    try check(call("POST", "/v1/desk/\(retried.id)/start", try encode(Companion.DeskStartRequest(place: .init(kind: "project", id: busy.id, name: "Render")))).status == 404,
              "a chat that isn't a project isn't one")
    // New chats from the phone start the same way (CompanionServer.newSession).
    let phoneSide = try Companion.decoder.decode(Companion.ChatDetail.self, from: call("POST", "/v1/chats", try encode(Companion.NewChatRequest(project: dogear.id, title: "From the phone"))).body)
    try check(phoneSide.summary.sidechatOf == dogear.id && phoneSide.summary.title == "From the phone", "the phone's new chat in a project is still a Sidechat")
    let gone = call("POST", "/v1/chats", try encode(Companion.NewChatRequest(studio: old.id)))
    try check(gone.status == 404 && (try? Companion.decoder.decode(Companion.ErrorResponse.self, from: gone.body))?.error == "That Studio is gone.", "and a Studio that's gone is still refused")
    try check(runtime.sessions.allSatisfy { $0.claudeProcess == nil } && !CodexAppServer.shared.isRunning, "no agent started")

    // Threads: sessions already in the place doing the same work, to continue instead.
    let elsewhereSync = try runtime.insert(record("Fix the highlight sync", studio: archery, items: [DisplayItem(kind: .user, text: "Fix the highlight sync")]))
    var archivedSync = record("Fix the highlights sync and the bookmarks"); archivedSync.sidechatOf = dogear.id; archivedSync.archivedAt = Date()
    _ = try runtime.insert(archivedSync)
    let followUp = try deskOf(add("Fix the highlights sync followUp: bookmarks vanish after the book import")).incoming[0]
    try check(followUp.proposed?.id == dogear.id, "a follow-up is proposed for the same project")
    func threadsOf(_ response: HTTPResponse) throws -> [Companion.DeskThread] { try Companion.decoder.decode([Companion.DeskThread].self, from: response.body) }
    let threads = try threadsOf(call("GET", "/v1/desk/\(followUp.id)/threads"))
    try check(threads.first?.id == side.summary.id && threads.first?.match == "clear" && threads.first?.title == side.summary.title,
              "threads: the session started for the same work first, a clear match: \(threads.map { "\($0.title) \($0.match)" })")
    try check(threads.contains { $0.id == branch.id && $0.match == "possible" } && threads.count <= DeskStore.threadLimit,
              "and the project's worktree doing similar work, as possible")
    try check(!threads.contains { $0.id == elsewhereSync.id } && !threads.contains { $0.title == archivedSync.title } && !threads.contains { $0.id == phoneSide.summary.id },
              "only the place's own open sessions that share the work: not another Studio's, an archived one, or an unrelated Sidechat")
    try check(threads.first?.settings?.isEmpty == false && threads.first?.isRunning == false, "each says its agent and whether it's working")
    let inArchery = try threadsOf(call("GET", "/v1/desk/\(followUp.id)/threads", query: ["place": archery.id.uuidString]))
    try check(inArchery.map(\.id) == [elsewhereSync.id], "threads in another place chosen: that place's own")
    try check(call("GET", "/v1/desk/\(followUp.id)/threads", query: ["place": UUID().uuidString]).status == 404 && call("GET", "/v1/desk/\(UUID())/threads").status == 404,
              "an unknown place or request: 404")
    try check(try threadsOf(call("GET", "/v1/desk/\(followUp.id)/threads", query: ["place": "loose"])).allSatisfy { runtime.session($0.id)?.record.studioID == nil && runtime.session($0.id)?.record.sidechatOf == nil },
              "loose threads are loose sessions")
    let close = try deskOf(add("Fix the highlight sync", place: "Dogear")).incoming[0]
    let closeThreads = try threadsOf(call("GET", "/v1/desk/\(close.id)/threads"))
    try check(closeThreads.count >= 2 && closeThreads.allSatisfy { $0.match == "possible" }, "two as likely: neither is a clear match: \(closeThreads.map { "\($0.title) \($0.match)" })")
    let unrelated = try deskOf(add("Buy coffee filters", place: "Dogear")).incoming[0]
    try check(try threadsOf(call("GET", "/v1/desk/\(unrelated.id)/threads")).isEmpty, "nothing like it: no threads")
    try check(threads.first?.task == highlights.text && threads.first { $0.id == branch.id }?.task == nil, "a thread carrying an open task says which")
    // Link a thread (from a To do card): every thread in the place, best matches first.
    let everything = try threadsOf(call("GET", "/v1/desk/\(unrelated.id)/threads", query: ["all": "1"]))
    try check(everything.contains { $0.id == dogear.id } && everything.contains { $0.id == phoneSide.summary.id } && everything.allSatisfy { $0.match == "other" },
              "all=1: every open thread in the place, even with nothing in common")
    let followUpAll = try threadsOf(call("GET", "/v1/desk/\(close.id)/threads", query: ["all": "1"]))
    try check(followUpAll.count > closeThreads.count && Array(followUpAll.prefix(closeThreads.count)).map(\.id) == closeThreads.map(\.id)
              && followUpAll.dropFirst(closeThreads.count).allSatisfy { $0.match == "other" }, "matches first, then the rest")
    func link(_ task: UUID, _ chat: UUID, replace: Bool? = nil) throws -> HTTPResponse {
        call("POST", "/v1/desk/\(task)/link", try encode(Companion.DeskLinkRequest(chatID: chat, replace: replace)))
    }
    let linkedDesk = try deskOf(try link(unrelated.id, phoneSide.summary.id))
    try check(desk.openTask(for: phoneSide.summary.id)?.id == unrelated.id && !linkedDesk.incoming.contains { $0.id == unrelated.id }
              && linkedDesk.ready?.first { $0.id == phoneSide.summary.id }?.taskText == unrelated.text, "link: the task leaves To do, on the board by its thread")
    try check(try link(unrelated.id, phoneSide.summary.id).status == 200, "linking it again changes nothing")
    let plants = try deskOf(add("Water the plants", place: "Dogear")).incoming[0]
    let asks = try link(plants.id, phoneSide.summary.id)
    try check(asks.status == 409 && desk.openTask(for: phoneSide.summary.id)?.id == unrelated.id, "one task per thread: linking a thread that carries one asks first")
    _ = try deskOf(try link(plants.id, phoneSide.summary.id, replace: true))
    try check(desk.openTask(for: phoneSide.summary.id)?.id == plants.id && desk.requests.contains { $0.id == unrelated.id },
              "linked anyway: the old task goes back to To do")
    try check(try link(UUID(), phoneSide.summary.id).status == 404 && (try link(plants.id, UUID())).status == 404, "a task or thread that's gone: 404")
    try desk.unlink(plants.id); try desk.ignore(plants.id)

    // Continue: the request is that session's next message (queued while it works); nothing new starts.
    let sideSession = runtime.session(side.summary.id)!
    sideSession.isRunning = true
    let before = runtime.sessions.count
    let carrying = call("POST", "/v1/desk/\(followUp.id)/start", try encode(Companion.DeskStartRequest(continueChat: side.summary.id)))
    try check(carrying.status == 409 && (try? Companion.decoder.decode(Companion.ErrorResponse.self, from: carrying.body))?.error.contains("already carries a task") == true
              && desk.requests.contains { $0.id == followUp.id } && sent.last?.chat != side.summary.id,
              "one task per thread: continuing a thread that carries another open task asks first")
    let continued = call("POST", "/v1/desk/\(followUp.id)/start", try encode(Companion.DeskStartRequest(continueChat: side.summary.id, replace: true)))
    let continuedDetail = try Companion.decoder.decode(Companion.ChatDetail.self, from: continued.body)
    try check(continued.status == 200 && continuedDetail.summary.id == side.summary.id && runtime.sessions.count == before,
              "continue: that session's ChatDetail, and no new session")
    try check(sent.last?.chat == side.summary.id && sent.last?.text == followUp.text && sideSession.items.last?.text == followUp.text,
              "the request goes to it as its next message, while it works")
    try check(!desk.requests.contains { $0.id == followUp.id } && sideSession.record.title == side.summary.title, "it leaves To do; the session keeps its name")
    try check(desk.openTask(for: side.summary.id)?.id == followUp.id && desk.requests.contains { $0.id == highlights.id },
              "linked to that thread; the task it carried goes back to To do")
    sideSession.isRunning = false
    try check(sentOn.last == "claude opus medium" && sideSession.record.model == "opus", "continuing without a model: on its own")

    // Continue on another model: the step shows what the session would run on, untouched; Continue
    // switches it (as Session Settings would) before the request is sent.
    let exporting = try runtime.insert(record("Highlights export", items: [DisplayItem(kind: .user, text: "Export them"), DisplayItem(kind: .assistant, text: "Exported.", phase: .final)]))
    func optionsQuery(_ query: [String: String]) throws -> Companion.ChatOptions {
        try Companion.decoder.decode(Companion.ChatOptions.self, from: call("GET", "/v1/new-chat-options", query: query).body)
    }
    let own = try optionsQuery(["chat": exporting.id.uuidString])
    try check(own.backend == "claude" && own.model == "opus" && own.effort == "medium", "options for a session: its own model (\(own.model) \(own.effort))")
    let wouldRun = try optionsQuery(["chat": exporting.id.uuidString, "model": "sonnet", "effort": "high"])
    try check(wouldRun.model == "sonnet" && wouldRun.effort == "high" && exporting.record.model == "opus" && exporting.record.effort == "medium" && exporting.items.count == 2,
              "with picks: what it would run on; the session isn't changed")
    let wouldSwitch = try optionsQuery(["chat": exporting.id.uuidString, "backend": "codex", "model": "gpt-6.1-sol"])
    try check(wouldSwitch.backend == "codex" && wouldSwitch.model == "gpt-6.1-sol" && exporting.record.backend == .claude && exporting.record.pendingHandoff == nil,
              "another agent's model: as switched, the session still on its own")
    try check(call("GET", "/v1/new-chat-options", query: ["chat": UUID().uuidString]).status == 404, "options for a session that's gone: 404")
    try check(try desk.options(for: DeskStore.loose, picks: .init(effort: "low"), chat: exporting.id).effort == "low", "the Desk's options for a session take the picks")
    let exportTask = try deskOf(add("Tighten the highlights export", place: "loose")).incoming[0]
    exporting.isRunning = true
    let busyAgent = call("POST", "/v1/desk/\(exportTask.id)/start", try encode(Companion.DeskStartRequest(agent: "codex", model: "gpt-6.1-sol", continueChat: exporting.id)))
    try check(busyAgent.status == 409 && exporting.record.backend == .claude && desk.requests.contains { $0.id == exportTask.id } && sent.last?.chat != exporting.id,
              "working: another agent waits (409), nothing changes or is sent")
    let switched = call("POST", "/v1/desk/\(exportTask.id)/start", try encode(Companion.DeskStartRequest(agent: "claude", model: "sonnet", effort: "high", continueChat: exporting.id)))
    try check(switched.status == 200 && exporting.record.model == "sonnet" && exporting.record.effort == "high" && sent.last?.chat == exporting.id && sentOn.last == "claude sonnet high",
              "continue with a model: the session switches to it before the request is sent (\(sentOn.last ?? ""))")
    try check(desk.openTask(for: exporting.id)?.id == exportTask.id && runtime.sessions.count == before + 1, "linked to it; nothing new starts")
    exporting.isRunning = false
    try desk.unlink(exportTask.id); try desk.ignore(exportTask.id)
    let idle = try runtime.insert(record("Highlights import", items: [DisplayItem(kind: .user, text: "Import them"), DisplayItem(kind: .assistant, text: "Imported.", phase: .final)]))
    let importTask = try deskOf(add("Speed up the highlights import", place: "loose")).incoming[0]
    let toCodex = call("POST", "/v1/desk/\(importTask.id)/start", try encode(Companion.DeskStartRequest(agent: "codex", model: "gpt-6.1-sol", continueChat: idle.id)))
    try check(toCodex.status == 200 && idle.record.backend == .codex && idle.record.codex?.model == "gpt-6.1-sol" && sentOn.last == "codex gpt-6.1-sol "
              && idle.record.pendingHandoff != nil, "between replies, another agent: switched (caught up), then sent (\(sentOn.last ?? ""))")
    try desk.unlink(importTask.id); try desk.ignore(importTask.id)
    let sessionCount = runtime.sessions.count
    try check(call("POST", "/v1/desk/\(close.id)/start", try encode(Companion.DeskStartRequest(continueChat: UUID()))).status == 404
              && desk.requests.contains { $0.id == close.id } && runtime.sessions.count == sessionCount, "continuing a session that's gone: refused, and kept")
    // The model chosen: applied before the first message.
    let picked = call("POST", "/v1/desk/\(close.id)/start", try encode(Companion.DeskStartRequest(place: DeskStore.loose, agent: "claude", model: "sonnet", effort: "high")))
    let pickedChat = runtime.session(try Companion.decoder.decode(Companion.ChatDetail.self, from: picked.body).summary.id)
    try check(picked.status == 200 && pickedChat?.record.backend == .claude && pickedChat?.record.model == "sonnet" && pickedChat?.record.effort == "high",
              "start with a model: the new session runs it, at the effort chosen")
    let codexPick = try deskOf(add("Rename the export menu", place: "loose")).incoming[0]
    let codexChat = runtime.session(try Companion.decoder.decode(Companion.ChatDetail.self, from: call("POST", "/v1/desk/\(codexPick.id)/start",
        try encode(Companion.DeskStartRequest(agent: "codex", model: "gpt-6.1-sol"))).body).summary.id)
    try check(codexChat?.record.backend == .codex && codexChat?.record.codex?.model == "gpt-6.1-sol", "and Codex's model for a Codex session")
    // An older phone's body, without the new fields, still starts where proposed.
    let oldBody = try deskOf(add("Plan the archery banner print run", place: "USA Archery")).incoming[0]
    let oldStart = call("POST", "/v1/desk/\(oldBody.id)/start", Data(#"{"agent":"claude"}"#.utf8))
    try check(oldStart.status == 200 && runtime.session(try Companion.decoder.decode(Companion.ChatDetail.self, from: oldStart.body).summary.id)?.record.studioID == archery.id,
              "a start without the new fields is unchanged")
    // New chat options for a project's Sidechat, as the start step shows them.
    let projectOptions = try Companion.decoder.decode(Companion.ChatOptions.self, from: call("GET", "/v1/new-chat-options", query: ["project": dogear.id.uuidString]).body)
    try check(projectOptions.backend == dogear.record.backend.rawValue, "new chat options for a project: its Sidechat's agent")
    try check(try desk.options(for: .init(kind: "project", id: dogear.id, name: "Dogear"), picks: .init(backend: "codex")).backend == "codex", "the Desk's options take the picks")
    try check(runtime.sessions.allSatisfy { $0.claudeProcess == nil } && !CodexAppServer.shared.isRunning, "no agent started by continuing or picking a model")

    // Claude's connector: propose_work puts work on the Desk from Claude.
    let (proposed, failed) = await ConnectorTools.call("propose_work", arguments: ["text": "Draft the fall camp flyers, banners and homepage copy", "note": "Camp starts in October"], token: token)
    try check(!failed && proposed.contains("Studio USA Archery") && desk.requests.first?.source == "claude" && desk.requests.first?.note == "Camp starts in October",
              "propose_work: on the Desk from Claude, with the place it fits: \(proposed)")
    let (nowhereText, nowhereFailed) = await ConnectorTools.call("propose_work", arguments: ["text": "Something", "place": "Nowhere"], token: token)
    try check(nowhereFailed && nowhereText.contains("Places:") && nowhereText.contains("Project Dogear"), "propose_work to an unknown place lists the real ones")

    // The service socket: the app does everything, an agent looks and proposes; desk.changed.
    let socketTodo = try desk.add(.init(text: "Print the camp email", place: "loose"))
    let wrapUpLater = try runtime.insert(record("Camp email", items: [DisplayItem(kind: .user, text: "Write it"), DisplayItem(kind: .assistant, text: "Written.", phase: .final)]))
    let socket = RuntimeServer(runtime: runtime)
    try socket.start()
    defer { socket.stop() }
    desk.onChange = { runtime.publishUIRequest("desk.changed", payload: (try? JSON.value($0)) ?? .null) }
    let ui = RuntimeClient(socketName: "daemon.sock"), agent = RuntimeClient(socketName: "daemon.sock")
    var changes: [Companion.Desk] = []
    ui.onEvent = { event in if event.kind == "desk.changed", let desk = try? event.payload?.decode(Companion.Desk.self) { changes.append(desk) } }
    ui.start(role: "ui"); agent.start(role: "agent")
    try await wait("both connect") { ui.connected && agent.connected }
    let got = try await agent.request("desk", body: ["action": "get"]).decode(Companion.Desk.self)
    try check(got.revision == desk.revision && got.incoming == desk.requests, "socket get: the Desk")
    let socketPlaces = try await agent.request("desk", body: ["action": "places"]).decode([Companion.DeskPlace].self)
    try check(socketPlaces == desk.places(), "socket places")
    let socketThreads = try await agent.request("desk", body: ["action": "threads", "id": .string(unrelated.id.uuidString),
                                                               "place": try .value(Companion.DeskPlace(kind: "studio", id: archery.id, name: "USA Archery"))])
    try check((try socketThreads.decode([Companion.DeskThread].self)) == (try desk.threads(for: unrelated.id, place: .init(kind: "studio", id: archery.id, name: "USA Archery"))),
              "socket threads, in the place given (an agent may look)")
    let socketOptions = try await ui.request("desk", body: ["action": "options", "place": try .value(DeskStore.loose), "picks": ["backend": "codex"]]).decode(Companion.ChatOptions.self)
    try check(socketOptions.backend == "codex", "socket options: a new session's, with the picks")
    let socketChatOptions = try await ui.request("desk", body: ["action": "options", "place": try .value(DeskStore.loose), "chat": .string(dogear.id.uuidString),
                                                                "picks": ["effort": "high"]]).decode(Companion.ChatOptions.self)
    try check(socketChatOptions.model == dogear.record.model && socketChatOptions.effort == "high" && dogear.record.effort == "medium",
              "socket options with chat: as that session would run, untouched")
    let fromAgent = try await agent.request("desk", body: ["action": "add", "text": "Tidy the PlayCase Arcade level list for TestFlight", "source": "you"]).decode(Companion.Desk.self)
    try check(fromAgent.incoming[0].source == "claude" && fromAgent.incoming[0].proposed?.id == playcase.id, "an agent's add is from Claude, never from you")
    try await wait("desk.changed after the add") { changes.contains { $0.incoming.first?.id == fromAgent.incoming[0].id } }
    try check(true, "the app hears desk.changed, with the Desk")
    for action in ["start", "ignore"] {
        do { _ = try await agent.request("desk", body: ["action": .string(action), "id": .string(fromAgent.incoming[0].id.uuidString)]); try check(false, "an agent may not \(action)") }
        catch { try check(error.localizedDescription == "permission_denied", "an agent may not \(action)") }
    }
    let addID = UUID().uuidString
    let note: JSON = ["action": "add", "text": "Write the camp email", "place": "USA Archery", "note": "Shelby asked"]
    let uiAdd = try await ui.request("desk", body: note, id: addID).decode(Companion.Desk.self)
    let uiAgain = try await ui.request("desk", body: note, id: addID).decode(Companion.Desk.self)
    try check(uiAdd.incoming[0].source == "you" && uiAgain.incoming == uiAdd.incoming && desk.requests.filter { $0.text == "Write the camp email" }.count == 1,
              "the app's add is from you; a retried request ID is answered once")
    let viaSocket = try await ui.request("desk", body: ["action": "start", "id": .string(fromAgent.incoming[0].id.uuidString)]).decode(Companion.ChatDetail.self)
    try check(runtime.session(viaSocket.summary.id)?.record.studioID == playcase.id && sent.last?.chat == viaSocket.summary.id, "socket start: a ChatDetail of the new session")
    let elsewhere = try await ui.request("desk", body: ["action": "start", "id": .string(uiAdd.incoming[0].id.uuidString),
                                                         "place": try .value(Companion.DeskPlace(kind: "project", id: dogear.id, name: "Dogear"))]).decode(Companion.ChatDetail.self)
    try check(runtime.session(elsewhere.summary.id)?.record.sidechatOf == dogear.id, "socket start with another place")
    let afterIgnore = try await ui.request("desk", body: ["action": "ignore", "id": .string(retried.id.uuidString)]).decode(Companion.Desk.self)
    try check(!afterIgnore.incoming.contains { $0.id == retried.id }, "socket ignore")
    do { _ = try await ui.request("desk", body: ["action": "ignore", "id": .string(retried.id.uuidString)]); try check(false, "ignoring a gone request fails") }
    catch { try check(error.localizedDescription == "That request is gone.", "ignoring a gone request says so") }
    // Mark done: done outside Chatterbox, straight to Done with no thread; an agent may not; Reopen sends it back.
    let doneLater = try await ui.request("desk", body: ["action": "add", "text": "Call the venue about parking"]).decode(Companion.Desk.self)
    let doneTask = doneLater.incoming.first { $0.text == "Call the venue about parking" }!
    do { _ = try await agent.request("desk", body: ["action": "markDone", "id": .string(doneTask.id.uuidString)]); try check(false, "an agent can't mark a task done") }
    catch { try check(error.localizedDescription.contains("permission_denied"), "an agent can't mark a task done") }
    let afterDone = try await ui.request("desk", body: ["action": "markDone", "id": .string(doneTask.id.uuidString)]).decode(Companion.Desk.self)
    try check(!afterDone.incoming.contains { $0.id == doneTask.id } && afterDone.done?.contains { $0.id == doneTask.id && $0.task == doneTask.id && $0.title == "Call the venue about parking" } == true,
              "mark done: off To do, into Done without a thread")
    let backToDo = try await ui.request("desk", body: ["action": "reopen", "chatID": .string(doneTask.id.uuidString)]).decode(Companion.Desk.self)
    try check(backToDo.incoming.contains { $0.id == doneTask.id } && backToDo.done?.contains { $0.id == doneTask.id } != true, "reopen: back to To do")
    _ = try await ui.request("desk", body: ["action": "ignore", "id": .string(doneTask.id.uuidString)])
    // Tasks over the socket: the app may make, link and unlink them; an agent may not.
    let taskBody: JSON = ["action": "makeTask", "chatID": .string(wrapUpLater.id.uuidString), "text": "Wrap the camp email"]
    for body in [taskBody, ["action": "link", "id": .string(socketTodo.id.uuidString), "chatID": .string(wrapUpLater.id.uuidString)] as JSON,
                 ["action": "unlink", "id": .string(socketTodo.id.uuidString)] as JSON] {
        do { _ = try await agent.request("desk", body: body); try check(false, "an agent may not \(body["action"]?.string ?? "")") }
        catch { try check(error.localizedDescription == "permission_denied", "an agent may not \(body["action"]?.string ?? "")") }
    }
    let socketTask = try await ui.request("desk", body: taskBody).decode(Companion.Desk.self)
    try check(socketTask.linked?.contains { $0.chatID == wrapUpLater.id && $0.text == "Wrap the camp email" } == true, "socket makeTask")
    do { _ = try await ui.request("desk", body: ["action": "link", "id": .string(socketTodo.id.uuidString), "chatID": .string(wrapUpLater.id.uuidString)]); try check(false, "linking a carrying thread asks") }
    catch { try check(error.localizedDescription.contains("already carries a task"), "socket link: a thread that carries a task asks first") }
    let socketLinked = try await ui.request("desk", body: ["action": "link", "id": .string(socketTodo.id.uuidString), "chatID": .string(wrapUpLater.id.uuidString),
                                                         "replace": true]).decode(Companion.Desk.self)
    try check(socketLinked.linked?.first { $0.chatID == wrapUpLater.id }?.id == socketTodo.id && socketLinked.incoming.contains { $0.text == "Wrap the camp email" },
              "socket link with replace: linked, the old task back to To do")
    let socketUnlinked = try await ui.request("desk", body: ["action": "unlink", "id": .string(socketTodo.id.uuidString)]).decode(Companion.Desk.self)
    try check(socketUnlinked.incoming.contains { $0.id == socketTodo.id } && desk.openTask(for: wrapUpLater.id) == nil, "socket unlink")
    // Silence over the socket: the app may, an agent may not; desk.changed says so.
    let planItem = plan.pendingRequests[0].id
    let silenceBody: JSON = ["action": "silence", "chatID": .string(plan.id.uuidString), "id": .string(planItem.uuidString)]
    do { _ = try await agent.request("desk", body: silenceBody); try check(false, "an agent may not silence") }
    catch { try check(error.localizedDescription == "permission_denied", "an agent may not silence") }
    let heard = changes.count
    let socketQuiet = try await ui.request("desk", body: silenceBody).decode(Companion.Desk.self)
    try check(!socketQuiet.needsYou.contains { $0.chatID == plan.id } && socketQuiet.silenced?.contains { $0.id == planItem } == true
              && plan.pendingRequests.map(\.id) == [planItem], "socket silence: off the Desk, still pending")
    try await wait("desk.changed after silencing") { changes.count > heard && changes.last?.silenced?.contains { $0.id == planItem } == true }
    try check(true, "the app hears the silence")
    // Unsilence over the socket: the same; the app's Undo.
    let unsilenceBody: JSON = ["action": "unsilence", "chatID": .string(plan.id.uuidString), "id": .string(planItem.uuidString)]
    do { _ = try await agent.request("desk", body: unsilenceBody); try check(false, "an agent may not unsilence") }
    catch { try check(error.localizedDescription == "permission_denied", "an agent may not unsilence") }
    let undone = try await ui.request("desk", body: unsilenceBody).decode(Companion.Desk.self)
    try check(undone.needsYou.contains { $0.id == planItem } && undone.silenced?.contains { $0.id == planItem } == false, "socket unsilence: back on the Desk")
    try await wait("desk.changed after unsilencing") { changes.last?.needsYou.contains { $0.id == planItem } == true }
    _ = try await ui.request("desk", body: silenceBody)
    // Mark complete and Reopen over the socket: the app may, an agent may not.
    let wrapUp = try runtime.insert(record("Wrap up the camp email", items: [DisplayItem(kind: .user, text: "Wrap up"), DisplayItem(kind: .assistant, text: "Sent.", phase: .final)]))
    let completeBody: JSON = ["action": "complete", "chatID": .string(wrapUp.id.uuidString)]
    for body in [completeBody, ["action": "reopen", "chatID": .string(wrapUp.id.uuidString)] as JSON] {
        do { _ = try await agent.request("desk", body: body); try check(false, "an agent may not \(body["action"]?.string ?? "")") }
        catch { try check(error.localizedDescription == "permission_denied" && wrapUp.record.archivedAt == nil, "an agent may not \(body["action"]?.string ?? "")") }
    }
    _ = try desk.makeTask(.init(chatID: wrapUp.id))
    let heardBefore = changes.count
    let socketDone = try await ui.request("desk", body: completeBody).decode(Companion.Desk.self)
    try check(wrapUp.record.archivedAt != nil && socketDone.done?.first?.id == wrapUp.id && socketDone.ready?.contains { $0.id == wrapUp.id } == false,
              "socket complete: archived, in Done")
    try await wait("desk.changed after completing") { changes.count > heardBefore && changes.last?.done?.first?.id == wrapUp.id }
    try check(true, "the app hears the completion")
    let socketReopened = try await ui.request("desk", body: ["action": "reopen", "chatID": .string(wrapUp.id.uuidString)]).decode(Companion.Desk.self)
    try check(wrapUp.record.archivedAt == nil && socketReopened.done?.contains { $0.id == wrapUp.id } == false && socketReopened.ready?.contains { $0.id == wrapUp.id } == true,
              "socket reopen: unarchived, Ready again")
    do { _ = try await ui.request("desk", body: ["action": "complete"]); try check(false, "complete without a session fails") }
    catch { try check(error.localizedDescription == "Say which session.", "complete without a session says so") }
    // A session starting work changes Working: announced without anyone asking.
    busy.isRunning = true
    _ = try desk.makeTask(.init(chatID: busy.id))
    try await wait("desk.changed with the busy task") { changes.last?.working.contains { $0.id == busy.id } == true }
    let seen = changes.count
    busy.isRunning = false; busy.onChange?(busy)
    try await wait("desk.changed when a session stops") { changes.count > seen && changes.last?.working.contains { $0.id == busy.id } == false }
    try check(true, "a session's change to Working is announced")
    // Put on the Desk as a thread is made (New Chat's toggle): a task linked to it, in its
    // place, named from its first message and then with the thread.
    func newChat(_ request: Companion.NewChatRequest) throws -> ChatSession {
        let response = call("POST", "/v1/chats", try encode(request))
        try check(response.status == 200, "a new chat answers with its detail")
        let detail = try Companion.decoder.decode(Companion.ChatDetail.self, from: response.body)
        return runtime.session(detail.summary.id)!
    }
    let fresh = try newChat(.init(studio: archery.id, desk: true))
    let freshTask = desk.openTask(for: fresh.id)
    try check(freshTask?.followsThread == true && freshTask?.proposed?.id == archery.id && freshTask?.source == "you",
              "new chat with desk: a task linked to it, in its Studio")
    try check(desk.snapshot().linked?.contains { $0.chatID == fresh.id } == true, "the new chat's task is on the board")
    _ = fresh.appendItem(DisplayItem(kind: .user, text: "Make the fall banner set\nthree sizes, by Friday"))
    fresh.setTitleIfNeeded(UserMessage(text: "Make the fall banner set\nthree sizes, by Friday", attachments: []))
    _ = desk.snapshot()
    try check(desk.openTask(for: fresh.id)?.text == "Make the fall banner set", "named from its first message: \(desk.openTask(for: fresh.id)?.text ?? "")")
    fresh.setTitle("Fall banners")
    _ = desk.snapshot()
    try check(desk.openTask(for: fresh.id)?.text == "Fall banners", "renaming the thread renames its task")
    let plainNew = try newChat(.init(studio: archery.id))
    try check(desk.openTask(for: plainNew.id) == nil, "without desk: no task, as before")
    let deskSide = try newChat(.init(project: dogear.id, desk: true))
    try check(deskSide.record.sidechatOf == dogear.id && desk.openTask(for: deskSide.id)?.proposed?.id == dogear.id, "a project's new session on the Desk: in the project")
    _ = deskSide.appendItem(DisplayItem(kind: .user, text: "Tighten the highlight export"))
    _ = desk.snapshot()
    try check(desk.openTask(for: deskSide.id)?.text == "Tighten the highlight export", "a Sidechat's task is named from its first message, not \u{201C}Sidechat\u{201D}")
    let deskNamed = try newChat(.init(studio: playcase.id, title: "Level pack 3", desk: true))
    try check(desk.openTask(for: deskNamed.id)?.text == "Level pack 3", "named in the sheet: the task has that name")
    // The Mac's way: the session first, then the socket's makeTask with follow.
    let macNew = try runtime.insert(record("New chat", studio: playcase))
    let macBoard = try await ui.request("desk", body: ["action": "makeTask", "chatID": .string(macNew.id.uuidString), "follow": true, "text": "Icons"]).decode(Companion.Desk.self)
    try check(macBoard.linked?.contains { $0.chatID == macNew.id && $0.text == "Icons" } == true && desk.openTask(for: macNew.id)?.followsThread == true,
              "socket makeTask with follow: linked, named as given")
    macNew.setTitle("App icons")
    _ = desk.snapshot()
    try check(desk.openTask(for: macNew.id)?.text == "App icons", "and it follows the thread's name")
    try check(runtime.sessions.allSatisfy { $0.claudeProcess == nil } && !CodexAppServer.shared.isRunning, "still no agent started")
    ui.stop(); agent.stop()
    runtime.waitForSaves()
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()

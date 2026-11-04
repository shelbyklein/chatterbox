import Foundation
import Darwin
// The Desk, as the service runs it (plans/front-desk.md): proposals for Studios and projects,
// places, ignore, desk.json across a reload, Needs you and Working from sessions (named as the
// session lists name them), silence (kept, pruned, shown again when something new waits), the
// phone's routes with a paired token, the service socket's "desk" operation and desk.changed, Claude's
// propose_work, and starting a request in a Studio, as a project's Sidechat, or loose. No
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
    desk.sendFirstMessage = { session, text in
        sent.append((session.id, text))
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
    try check(reloaded.requests == desk.requests && reloaded.revision == desk.revision + 1, "the requests and revision survive a reload")
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
    let approval = try runtime.insert(record("Deploy the site", studio: archery, items: [
        DisplayItem(kind: .user, text: "Deploy"), DisplayItem(kind: .approval, text: "Run deploy.sh", approvalState: .pending)]))
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
    _ = try runtime.insert(record("Old question", items: [
        DisplayItem(kind: .user, text: "Hi"), DisplayItem(kind: .assistant, timestamp: Date().addingTimeInterval(-3 * 86_400), text: "Shall I go on?", phase: .final)]))
    _ = try runtime.insert(record("Finished", items: [DisplayItem(kind: .user, text: "Hi"), DisplayItem(kind: .assistant, text: "All done.", phase: .final)]))
    let busy = try runtime.insert(record("Render the poster", studio: playcase, items: [DisplayItem(kind: .user, text: "Render")]))
    busy.isRunning = true
    let sidechat = try model.newSidechat(of: dogear)
    sidechat.isRunning = true
    let now = try deskOf(call("GET", "/v1/desk"))
    func waiting(_ chat: ChatSession) -> Companion.DeskWaiting? { now.needsYou.first { $0.chatID == chat.id } }
    try check(waiting(approval)?.kind == "approval" && waiting(approval)?.text == "Run deploy.sh" && waiting(approval)?.place == "USA Archery"
              && waiting(approval)?.id == approval.items[1].id, "needs you: a pending approval, with its place and item id")
    try check(waiting(plan)?.kind == "plan" && waiting(plan)?.place == nil, "needs you: a plan")
    try check(waiting(asking)?.kind == "questions" && waiting(asking)?.questions?.map(\.id) == ["size", "color"]
              && waiting(asking)?.questions?.first?.options.first?.label == "Wide" && waiting(asking)?.text == "Which banner size? (and 1 more)",
              "needs you: questions, with the questions to answer in place")
    try check(waiting(replied)?.kind == "reply" && waiting(replied)?.text == "Want me to upload it to TestFlight?" && waiting(replied)?.id == replied.id,
              "needs you: a reply that ends on a question")
    try check(now.needsYou.count == 4, "not an old question, a finished reply, or a running session: \(now.needsYou.map(\.title))")
    try check(now.working.map(\.id).sorted { $0.uuidString < $1.uuidString } == [busy.id, sidechat.id].sorted { $0.uuidString < $1.uuidString }
              && now.working.first { $0.id == busy.id }?.place == "PlayCase Arcade" && now.working.first { $0.id == sidechat.id }?.place == "Dogear",
              "working: running sessions with their places, not one waiting on you")
    try check(try deskOf(call("GET", "/v1/desk")).revision == now.revision, "nothing changed: the same revision")
    sidechat.isRunning = false
    let quieter = try deskOf(call("GET", "/v1/desk"))
    try check(quieter.revision > now.revision && quieter.working.map(\.id) == [busy.id] && announced.last?.revision == quieter.revision,
              "a session stopping changes the revision, and is announced")
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
    // Kept across a reload, in desk.json; an older desk.json without silences still loads.
    let kept = DeskStore(file: file)
    try check(kept.silences == desk.silences && kept.silences.count == 2 && !kept.snapshot().needsYou.contains { $0.chatID == approval.id || $0.chatID == replied.id },
              "silences survive a reload")
    let older = root.appendingPathComponent("desk-older.json")
    try Data(#"{"revision":7,"requests":[{"id":"\#(UUID().uuidString)","text":"Old request","source":"you","createdAt":"2026-11-01T10:00:00Z"}]}"#.utf8).write(to: older)
    let olderStore = DeskStore(file: older)
    try check(olderStore.requests.map(\.text) == ["Old request"] && olderStore.silences.isEmpty && olderStore.revision == 8, "a desk.json from before silencing loads")
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

    // Start: in its Studio, as the project's Sidechat, or loose; never an agent.
    let started = call("POST", "/v1/desk/\(bannerRequest.id)/start", Data("{}".utf8))
    let detail = try Companion.decoder.decode(Companion.ChatDetail.self, from: started.body)
    let bannerChat = runtime.session(detail.summary.id)
    try check(started.status == 200 && bannerChat?.record.studioID == archery.id && bannerChat?.record.studioFolder == archery.folder,
              "start: a new session in the proposed Studio")
    try check(detail.summary.title == "Banner ideas for the fall camp flyers and the\u{2026}" && sent.last?.chat == detail.summary.id
              && sent.last?.text == bannerRequest.text && detail.items.contains { $0.kind == .user && $0.text == bannerRequest.text },
              "named from the request, which is its first message: \(detail.summary.title)")
    try check(!desk.requests.contains { $0.id == bannerRequest.id } && !(try deskOf(call("GET", "/v1/desk"))).incoming.contains { $0.id == bannerRequest.id },
              "and the request leaves the Desk")
    try check(call("POST", "/v1/desk/\(bannerRequest.id)/start", Data("{}".utf8)).status == 404, "starting it again: gone")
    let side = try Companion.decoder.decode(Companion.ChatDetail.self, from: call("POST", "/v1/desk/\(highlights.id)/start", Data("{}".utf8)).body)
    let sideChat = runtime.session(side.summary.id)
    try check(sideChat?.record.sidechatOf == dogear.id && side.summary.sidechatOf == dogear.id && sideChat?.record.projectFolder == nil
              && side.summary.title.hasPrefix("Fix the highlights sync"), "start: a project's work is a new Sidechat of it")
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

    // Continue: the request is that session's next message (queued while it works); nothing new starts.
    let sideSession = runtime.session(side.summary.id)!
    sideSession.isRunning = true
    let before = runtime.sessions.count
    let continued = call("POST", "/v1/desk/\(followUp.id)/start", try encode(Companion.DeskStartRequest(continueChat: side.summary.id)))
    let continuedDetail = try Companion.decoder.decode(Companion.ChatDetail.self, from: continued.body)
    try check(continued.status == 200 && continuedDetail.summary.id == side.summary.id && runtime.sessions.count == before,
              "continue: that session's ChatDetail, and no new session")
    try check(sent.last?.chat == side.summary.id && sent.last?.text == followUp.text && sideSession.items.last?.text == followUp.text,
              "the request goes to it as its next message, while it works")
    try check(!desk.requests.contains { $0.id == followUp.id } && sideSession.record.title == side.summary.title, "it leaves the Desk; the session keeps its name")
    sideSession.isRunning = false
    try check(call("POST", "/v1/desk/\(close.id)/start", try encode(Companion.DeskStartRequest(continueChat: UUID()))).status == 404
              && desk.requests.contains { $0.id == close.id } && runtime.sessions.count == before, "continuing a session that's gone: refused, and kept")
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
    // A session starting work changes Working: announced without anyone asking.
    let seen = changes.count
    busy.isRunning = false; busy.onChange?(busy)
    try await wait("desk.changed when a session stops") { changes.count > seen && changes.last?.working.contains { $0.id == busy.id } == false }
    try check(true, "a session's change to Working is announced")
    try check(runtime.sessions.allSatisfy { $0.claudeProcess == nil } && !CodexAppServer.shared.isRunning, "still no agent started")
    ui.stop(); agent.stop()
    runtime.waitForSaves()
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()

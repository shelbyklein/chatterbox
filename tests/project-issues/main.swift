import Foundation
import Darwin
// Project issue boards (plans/project-issues.md), as the service runs them: a project with a game
// catalog groups issues by game; add (with an attachment copied in), update, statuses by hand,
// delete; issues.json across a reload; start an issue as a work thread of the project's session
// (its brief as the first message) and follow the thread (working → In progress, finished →
// Review, archived → Done); link and unlink; the service socket's "issues" operation (an agent
// may list and add, nothing else; filed as its agent); the phone's routes and attachment file.
// No agent ever starts: the first message goes to a stand-in.
func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure(text) }; print("PASS: \(text)")
}
@MainActor func wait(_ what: String, seconds: Double = 8, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() { if Date() > until { throw RuntimeFailure("Timed out: \(what)") }; try await Task.sleep(for: .milliseconds(20)) }
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-test-issues."))
    let nowhere = root.appendingPathComponent("no-agent").path
    AppPreferences.defaults.setVolatileDomain(["companionEnabled": true, "mobilePushEnabled": false, "keepMacAwake": false,
                                               "claudePath": nowhere, "codexPath": nowhere, "codexFolder": root.path,
                                               "easyCLIProxyEnabled": false, "remoteControlClaudeChats": false,
                                               "pcSSHHost": "chatterbox-test-no-pc.invalid"],
                                              forName: UserDefaults.argumentDomain)
    let runtime = try ConversationRuntime(root: root), model = DaemonContext(runtime), server = CompanionServer.shared
    server.model = model
    let store = ProjectIssueStore.shared
    var sent: [(chat: UUID, text: String)] = []
    store.sendFirstMessage = { session, text in sent.append((session.id, text)); _ = session.appendItem(DisplayItem(kind: .user, text: text)) }
    var announced: [String] = []
    store.onChange = { announced.append($0) }

    // A PlayCase-like project: a catalog of two games, one with a preview picture.
    let arcade = root.appendingPathComponent("playcase-arcade")
    try FileManager.default.createDirectory(at: arcade.appendingPathComponent("catalog"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: arcade.appendingPathComponent("game-previews"), withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: arcade.appendingPathComponent("game-previews/descent.png"))
    try """
    {"schema":1,"games":[{"id":"descent","title":"Descent","image":"game-previews/descent.png"},{"id":"bowl","title":"Bowl","image":"game-previews/missing.png"}]}
    """.write(to: arcade.appendingPathComponent("catalog/games.json"), atomically: true, encoding: .utf8)
    func record(_ title: String) -> ConversationRecord {
        var r = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic); r.title = title; return r
    }
    var front = record("Playcase Arcade"); front.projectFolder = arcade.path; front.projectNickname = "Playcase Arcade"
    let project = try runtime.insert(front)
    let side = try model.newSidechat(of: project)
    let plain = try runtime.insert(record("Loose chat"))

    // Games and the project, from any session in it.
    let games = ProjectIssueStore.games(in: arcade.path)
    try check(games.map(\.id) == ["descent", "bowl"] && games[0].title == "Descent" && games[0].image?.hasSuffix("descent.png") == true && games[1].image == nil,
              "the catalog's games, in order; a missing preview is left out")
    try check(try store.project(of: ["chatID": .string(side.id.uuidString)]) == arcade.path, "a Sidechat belongs to its project's board")
    do { _ = try store.project(of: ["chatID": .string(plain.id.uuidString)]); try check(false, "a loose chat has no board") }
    catch { try check(error.localizedDescription.contains("isn't in a project"), "a loose chat has no board") }

    // Add: game by id or title, type and priority checked, an attachment copied in.
    let shot = root.appendingPathComponent("glitch.png")
    try Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]).write(to: shot)
    let first = try store.add(.init(chatID: project.id, title: "Wordmark flickers on the title screen", notes: "Seen on the Duo.", game: "Descent",
                                    type: "bug", priority: "high", attachments: [shot.path]), in: arcade.path, by: "you")
    try check(first.number == 1 && first.game == "descent" && first.status == "open" && first.priority == "high" && first.createdBy == "you",
              "an issue: #1, under Descent (named by title), open, high")
    try check(first.attachments.count == 1 && first.attachments[0].mediaType == "image/png" && first.attachments[0].path != shot.path
              && FileManager.default.contentsEqual(atPath: first.attachments[0].path, andPath: shot.path), "its screenshot is copied in, kept with the issue")
    let general = try store.add(.init(chatID: project.id, title: "Shelf scroll stutters", type: "polish"), in: arcade.path, by: "claude")
    try check(general.number == 2 && general.game == nil && general.priority == "normal" && general.createdBy == "claude", "General, normal by default, filed by Claude")
    for (bad, why) in [(Companion.IssueAddRequest(chatID: project.id, title: "  "), "a title"),
                       (Companion.IssueAddRequest(chatID: project.id, title: "x", game: "Pong"), "catalog"),
                       (Companion.IssueAddRequest(chatID: project.id, title: "x", type: "chore"), "bug, feature or polish"),
                       (Companion.IssueAddRequest(chatID: project.id, title: "x", priority: "urgent"), "low, normal or high"),
                       (Companion.IssueAddRequest(chatID: project.id, title: "x", attachments: ["/nope.png"]), "No file")] {
        do { _ = try store.add(bad, in: arcade.path, by: "you"); try check(false, "refused: \(why)") }
        catch { try check(error.localizedDescription.contains(why), "refused: \(why) (\(error.localizedDescription))") }
    }
    try check(announced.last == arcade.path, "a change is announced with the project's folder")

    // More files later; filing by the project's folder (the Mac's board), not a session.
    let later = root.appendingPathComponent("later.mov"); try Data([0, 0, 0, 20]).write(to: later)
    try store.attach([later.path], to: first.id, in: arcade.path)
    try check(store.board(for: arcade.path).issues.first { $0.id == first.id }?.attachments.map(\.mediaType) == ["image/png", "video/quicktime"], "attach adds a recording")
    let byFolder = try store.operation(["action": "add", "project": .string(arcade.path), "title": "Filed from the board"], agent: nil).decode(Companion.ProjectIssue.self)
    try check(byFolder.number == 3, "filed by the project's folder")
    try store.delete(byFolder.id, in: arcade.path)
    // Update and move by hand; the board's order.
    try store.update(general.id, in: arcade.path, .init(notes: "Only with 30+ games.", game: "bowl", priority: "high", status: "review"))
    var board = store.board(for: arcade.path)
    let moved = board.issues.first { $0.id == general.id }!
    try check(moved.game == "bowl" && moved.priority == "high" && moved.status == "review" && moved.notes == "Only with 30+ games.", "update: game, priority, notes, status")
    try check(board.issues.map(\.number) == [2, 1] && board.projectName == "Playcase Arcade" && board.games.count == 2, "Review before Open; the project's name and games")
    try store.update(general.id, in: arcade.path, .init(game: ""))
    try check(store.board(for: arcade.path).issues.first { $0.id == general.id }?.game == nil, "\"\" files it back under General")

    // Start: a work thread of the project's session, the issue its first message, then it follows.
    let thread = try store.start(first.id, in: arcade.path)
    try check(thread.record.workOf == project.id && thread.title.hasPrefix("#1 "), "start: a work thread of the project, named #1 …")
    try check(sent.last?.chat == thread.id && sent.last?.text.hasPrefix("Issue #1 (Descent, bug, high priority): Wordmark flickers") == true
              && sent.last?.text.contains(first.attachments[0].path) == true && sent.last?.text.contains("Seen on the Duo.") == true,
              "its brief: game, type, priority, notes and the attachment's path")
    do { _ = try store.start(first.id, in: arcade.path); try check(false, "started twice") }
    catch { try check(error.localizedDescription.contains("already has a thread"), "an issue with a thread isn't started again") }
    thread.isRunning = true
    try check(store.board(for: arcade.path).issues.first { $0.id == first.id }?.status == "inProgress", "its thread working: In progress")
    thread.isRunning = false
    _ = thread.appendItem({ var item = DisplayItem(kind: .assistant, text: "Fixed the flicker."); item.phase = .final; return item }())
    board = store.board(for: arcade.path)
    try check(board.issues.first { $0.id == first.id }?.status == "review" && board.issues.first { $0.id == first.id }?.chatTitle == thread.title,
              "finished: Review, with its thread named")
    model.archive(thread)
    try check(store.board(for: arcade.path).issues.first { $0.id == first.id }?.status == "done", "its thread archived: Done")

    // Link and unlink.
    try store.link(general.id, in: arcade.path, to: side.id)
    try check(store.board(for: arcade.path).issues.first { $0.id == general.id }?.chatID == side.id, "linked to the project's Sidechat")
    do { try store.link(general.id, in: arcade.path, to: plain.id); try check(false, "outside thread") }
    catch { try check(error.localizedDescription.contains("isn't in this project"), "a thread from elsewhere can't be linked") }
    try store.link(general.id, in: arcade.path, to: nil)
    try check(store.board(for: arcade.path).issues.first { $0.id == general.id }.map { $0.chatID == nil && $0.status == "open" } == true, "unlinked: open again")

    // Kept across a reload.
    let reloaded = ProjectIssueStore(root: root)
    try check(reloaded.projects[arcade.path]?.count == 2 && reloaded.projects[arcade.path]?.first { $0.number == 1 }?.chatID == thread.id, "issues.json keeps the board")

    // The service socket: an agent may list and add (filed as its agent), nothing else.
    let socket = RuntimeServer(runtime: runtime)
    try socket.start()
    defer { socket.stop() }
    let ui = RuntimeClient(socketName: "daemon.sock"), agent = RuntimeClient(socketName: "daemon.sock")
    ui.start(role: "ui"); agent.start(role: "agent")
    try await wait("both connect") { ui.connected && agent.connected }
    let listed = try await agent.request("issues", body: ["action": "list", "chatID": .string(side.id.uuidString)]).decode(Companion.IssueBoard.self)
    try check(listed.issues.count == 2 && listed.project == arcade.path, "socket list, from a Sidechat")
    let filed = try await agent.request("issues", body: ["action": "add", "chatID": .string(project.id.uuidString), "title": "Bowl pins clip",
                                                         "game": "bowl", "type": "bug"]).decode(Companion.ProjectIssue.self)
    try check(filed.number == 3 && filed.createdBy == project.record.backend.rawValue, "an agent files an issue, as its agent")
    for action in ["update", "delete", "start", "link", "unlink"] {
        do { _ = try await agent.request("issues", body: ["action": .string(action), "chatID": .string(project.id.uuidString), "id": .string(filed.id.uuidString)])
             try check(false, "an agent may not \(action)") }
        catch { try check(error.localizedDescription.contains("permission_denied"), "an agent may not \(action)") }
    }
    let afterDelete = try await ui.request("issues", body: ["action": "delete", "chatID": .string(project.id.uuidString), "id": .string(filed.id.uuidString)])
        .decode(Companion.IssueBoard.self)
    try check(!afterDelete.issues.contains { $0.id == filed.id }, "the app deletes")

    // The phone: the board by any session in the project, actions, the attachment file only from its place.
    let paired = server.respond(to: HTTPRequest(method: "POST", path: "/v1/pair", query: [:], headers: [:],
                                                body: try Companion.encoder.encode(Companion.PairRequest(code: server.pairingCode, deviceName: "Issues fixture"))))
    let token = try Companion.decoder.decode(Companion.PairResponse.self, from: paired.body).token
    func call(_ method: String, _ path: String, _ body: Data = Data(), query: [String: String] = [:]) -> HTTPResponse {
        server.respond(to: HTTPRequest(method: method, path: path, query: query, headers: [Companion.tokenHeader.lowercased(): token], body: body))
    }
    let phoneBoard = call("GET", "/v1/issues", query: ["chat": side.id.uuidString])
    try check(phoneBoard.status == 200 && (try Companion.decoder.decode(Companion.IssueBoard.self, from: phoneBoard.body)).issues.count == 2, "the phone's board")
    let phoneAdd = call("POST", "/v1/issues", try Companion.encoder.encode(["action": "add", "chatID": project.id.uuidString, "title": "From the phone", "priority": "low"]))
    try check(phoneAdd.status == 200 && (try Companion.decoder.decode(Companion.ProjectIssue.self, from: phoneAdd.body)).priority == "low", "the phone files one")
    let file = call("GET", "/v1/issues/attachment", query: ["path": first.attachments[0].path])
    try check(file.status == 200 && file.fileURL?.path == first.attachments[0].path && file.contentType == "image/png", "the attachment is served")
    try check(call("GET", "/v1/issues/attachment", query: ["path": shot.path]).status == 404, "nothing outside the issues' own folder")
    try check(server.respond(to: HTTPRequest(method: "GET", path: "/v1/issues", query: ["chat": side.id.uuidString], headers: [:], body: Data())).status == 401,
              "the board needs a paired token")
    ui.stop(); agent.stop()
    runtime.waitForSaves()
    print("PASS all")
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()

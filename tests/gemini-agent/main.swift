@testable import Chatterbox
import AppKit

// Gemini (Antigravity CLI, `agy acp`) as a chat's agent, through the real ChatterboxHost and a
// fake agy (fake-agy.py) shaped like the real one's traffic (plans/gemini-agent.md):
// older records decode unchanged; a reply streams; an edit asks and the approval goes back;
// Bypass approves by itself; Stop cancels; a message sent mid-reply goes next; a new process
// resumes the same session without replaying it; a gone session starts a new one caught up;
// model, effort and mode reach agy; pictures go as image blocks.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
setbuf(stdout, nil)

func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure("FAIL: " + text) }
    print("PASS: \(text)")
}

@MainActor func wait(_ what: String, seconds: Double = 15, until done: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !done() {
        if Date() > until { throw RuntimeFailure("Timed out: \(what)") }
        try await Task.sleep(for: .milliseconds(30))
    }
}

@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-gemini-agent."))
    UserDefaults.standard.setVolatileDomain([
        "companionEnabled": false, "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false,
        "nextStepsEnabled": false, "claudeRemoteControl": false,
        "agyPath": root.appendingPathComponent("fake-agy.py").path,
        "claudePath": root.appendingPathComponent("no-agent").path, "codexPath": root.appendingPathComponent("no-agent").path,
    ], forName: UserDefaults.argumentDomain)
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")

    func requests() -> [JSON] {
        let text = (try? String(contentsOf: root.appendingPathComponent("agy-requests.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? JSON.parse(Data($0.utf8)) }
    }
    func methods() -> [String] { requests().compactMap { $0["method"]?.string } }
    func launches() -> Int {
        ((try? String(contentsOf: root.appendingPathComponent("agy-launches.jsonl"), encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    // Older records: no `gemini` field, and they keep their agent.
    let oldClaude = #"{"id":"6F1B0D42-8C1E-4C1F-9C55-2B1A6C9C0001","title":"Old","model":"opus","effort":"","personality":"friendly","createdAt":0,"updatedAt":0,"items":[]}"#
    let decoded = try JSONDecoder().decode(ConversationRecord.self, from: Data(oldClaude.utf8))
    try check(decoded.backend == .claude && decoded.gemini == nil, "an older Claude record decodes unchanged")
    var oldCodex = decoded
    oldCodex.codex = CodexSettings(folder: root.path, canEdit: false)
    try check(oldCodex.backend == .codex, "an older Codex record keeps Codex")
    var g = decoded
    g.activeBackend = .gemini
    g.gemini = GeminiSettings(sessionId: "s1", model: "gemini-3.8-flash", effort: "low", mode: "auto")
    let again = try JSONDecoder().decode(ConversationRecord.self, from: JSONEncoder().encode(g))
    try check(again.backend == .gemini && again.gemini == g.gemini, "a Gemini record round-trips")
    try check(Backend.allCases.count == 3 && Backend.gemini.label == "Gemini" && Backend.gemini.other == .claude, "Gemini is the third agent; its sidequests go to Claude")
    try check(PermissionModes.modes(for: .gemini).map(\.id) == ["auto", "default", "accept-edits", "plan", "bypass"], "Gemini's permission modes")

    // A Gemini chat in a project folder, asking before edits.
    let folder = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var record = ConversationRecord(title: "Gemini chat", model: "opus", effort: "", personality: .neutral)
    record.projectFolder = folder.path
    let chat = ChatSession(record: record)
    chat.setBackend(.gemini)
    try check(chat.record.backend == .gemini && chat.record.gemini != nil, "switching a chat to Gemini sets it up")
    chat.setMode("default")

    chat.send("Say hello")
    try await wait("first reply") { !chat.isRunning && chat.items.contains { $0.kind == .assistant } }
    let hello = chat.items.last { $0.kind == .assistant }
    try check(hello?.text == "Hello from Gemini." && hello?.phase == .final, "a reply streams in pieces and ends final")
    try check(chat.items.contains { $0.kind == .thought && $0.text == "Thinking it over." }, "its thinking shows")
    try check(chat.contextUsage[.gemini]?.used == 12345, "the context meter reads agy's usage")
    let first = requests().first { $0["method"]?.string == "session/prompt" }
    let firstText = (first?["params"]?["prompt"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
    try check(firstText.contains("Say hello") && firstText.count > 200, "a new session's first prompt carries the instructions, then the message")
    try check(methods().prefix(2) == ["initialize", "session/new"], "agy is initialized, then a session opened")
    try check(requests().contains { $0["method"]?.string == "session/set_mode" && $0["params"]?["modeId"]?.string == "default" }, "the chat's mode reaches agy")
    let session = chat.record.gemini?.sessionId
    try check(session?.hasPrefix("fake-session-") == true, "the session id is kept on the chat")

    // An edit asks first; approving it goes back to agy.
    chat.send("Please edit the file")
    try await wait("the approval card") { chat.items.contains { $0.kind == .approval && $0.approvalState == .pending } }
    let card = chat.items.last { $0.kind == .approval }!
    try check(card.text == "Gemini wants to edit hello.txt" && card.detail?.contains("hi") == true, "the card names the file and shows the change")
    chat.resolveApproval(card.id, .approved)
    try await wait("the edit's reply") { !chat.isRunning }
    try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("hello.txt").path), "approved, agy made the edit")
    let tool = chat.items.last { $0.kind == .tool }
    try check(tool?.text == "Edit hello.txt" && tool?.toolState == .done, "the tool row is named for the file and done")
    try check(chat.items.last { $0.kind == .assistant }?.text == "Wrote hello.txt.", "then its reply")
    try check(requests().contains { $0["method"] == nil && $0["result"]?["outcome"]?["optionId"]?.string == "allow" }, "the approval went back as Allow")

    // Bypass: no card, approved here.
    chat.setMode("bypass")
    try FileManager.default.removeItem(at: folder.appendingPathComponent("hello.txt"))
    let cards = chat.items.filter { $0.kind == .approval }.count
    chat.send("edit it again")
    try await wait("the bypassed edit") { !chat.isRunning && chat.items.last { $0.kind == .assistant }?.text == "Wrote hello.txt." && chat.items.filter { $0.kind == .tool }.count == 2 }
    try check(chat.items.filter { $0.kind == .approval }.count == cards, "Bypass approves without a card")
    try check(requests().contains { $0["method"]?.string == "session/set_mode" && $0["params"]?["modeId"]?.string == "auto" }, "Bypass runs agy in Auto")

    // Stop, and a message sent mid-reply waits for the next turn.
    chat.send("count slow please")
    try await wait("the slow reply") { chat.items.last { $0.kind == .assistant }?.text == "Counting: 1 2 3" }
    chat.send("And then this")
    try check(chat.items.last?.queued == true, "a message sent mid-reply waits, marked queued")
    chat.interrupt()
    try await wait("the queued message's reply") { !chat.isRunning && chat.items.last { $0.kind == .assistant }?.text == "Hello from Gemini." }
    try check(methods().contains("session/cancel"), "Stop cancels the turn")
    try check(chat.items.contains { $0.kind == .notice && $0.text.hasPrefix("Stopped") }, "the transcript says it stopped")
    try check(!chat.items.contains { $0.queued == true }, "the queued message was sent after")

    // Model and effort reach agy.
    chat.setGeminiModel("gemini-3.8-flash")
    chat.setGeminiEffort("low")
    try await wait("settings sent") { requests().contains { $0["params"]?["configId"]?.string == "thought_level" && $0["params"]?["value"]?.string == "low" } }
    try check(requests().contains { $0["params"]?["configId"]?.string == "model" && $0["params"]?["value"]?.string == "gemini-3.8-flash" }, "the model reaches agy")
    try check(chat.settingsDescription == "Gemini \u{00B7} Gemini 3.8 Flash \u{00B7} Low effort", "the chat names its Gemini model and effort")
    try check(GeminiModels.shared.models.map(\.id) == ["gemini-4-neon", "gemini-3.8-flash"], "the model list is agy's Gemini models (not its Claude ones)")

    // A new process resumes the same session without a replay.
    let before = launches()
    await chat.restartThread()
    chat.send("Say hello again")
    try await wait("the reply after restart") { !chat.isRunning && chat.items.filter { $0.kind == .assistant && $0.text == "Hello from Gemini." }.count >= 3 }
    try check(launches() == before + 1, "restarting starts a new agy process")
    try check(requests().contains { $0["method"]?.string == "session/resume" && $0["params"]?["sessionId"]?.string == session }, "it resumes the same session")
    try check(chat.record.gemini?.sessionId == session && !chat.items.contains { $0.text.contains("REPLAYED") }, "same session, nothing replayed into the chat")

    // A session agy no longer has: a new one, caught up on the chat.
    chat.record.gemini?.sessionId = "gone"
    await chat.restartThread()
    chat.send("Still there?")
    try await wait("the reply in a new session") { !chat.isRunning && chat.record.gemini?.sessionId?.hasPrefix("fake-session-") == true && chat.record.gemini?.sessionId != session }
    let caughtUp = requests().last { $0["method"]?.string == "session/prompt" }
    let caughtText = (caughtUp?["params"]?["prompt"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
    try check(caughtText.contains("Wrote hello.txt.") && caughtText.contains("Still there?"), "a gone session is replaced by one caught up on the chat")
    try check(chat.items.contains { $0.kind == .notice && $0.text.contains("Couldn't reopen the earlier Gemini session") }, "and the chat says so")

    // Pictures go as image blocks.
    let png = root.appendingPathComponent("dot.png")
    let image = NSImage(size: NSSize(width: 2, height: 2)); image.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2)); image.unlockFocus()
    try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: png)
    chat.send("What's this?", attachments: [Attachment(name: "dot.png", path: png.path, mediaType: "image/png", kind: .image)])
    try await wait("the picture's reply") { !chat.isRunning && requests().last { $0["method"]?.string == "session/prompt" }.map { ($0["params"]?["prompt"]?.array ?? []).contains { $0["type"]?.string == "image" } } == true }
    let block = (requests().last { $0["method"]?.string == "session/prompt" }?["params"]?["prompt"]?.array ?? []).first { $0["type"]?.string == "image" }
    try check(block?["mimeType"]?.string == "image/png" && (block?["data"]?.string?.isEmpty == false), "a picture goes as an image block")

    chat.shutdown()
    print("ALL PASS")
}

Task { @MainActor in
    do { try await run(); exit(0) } catch { print(error.localizedDescription); exit(1) }
}
app.run()

import AppKit
import Foundation

// Empty chats that carry user intent (a name, a Studio, a chosen agent or model) survive a
// relaunch; an untouched "New chat" doesn't; deleting one removes its file.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func check(_ ok: Bool, _ what: String) {
    guard ok else { print("FAIL \(what)"); exit(1) }
    print("PASS \(what)")
}

@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-empty-chat."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns": false, "dotWatchWaiting": false, "dotSummarizeFinished": false,
                                             "dotEmailWatch": false, "companionEnabled": false, "keepMacAwake": false,
                                             "mobilePushConfigured": false], forName: UserDefaults.argumentDomain)
    func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
    func conversationFiles() -> [String] {
        let dir = root.appendingPathComponent("Conversations")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".json") }
    }

    var studioID = UUID(), studioChatID = UUID(), blankID = UUID(), deleteID = UUID()
    do {
        let model = AppModel()
        let studio = model.newStudio(named: "Harness Studio")!
        studioID = studio.id
        let chat = model.chats(in: studio).first!
        studioChatID = chat.id
        chat.setTitle("My named chat")
        chat.setBackend(.codex)
        chat.setCodexModel("gpt-5.5")
        chat.setCodexEffort("high")
        await settle()
        check(conversationFiles().contains("\(chat.id.uuidString).json"), "empty Studio chat with a name and agent is written")

        // A second chat: Claude with a chosen model and effort, no Studio, no title.
        let other = model.newChat(backend: .claude)
        check(other.id != chat.id, "a titled empty chat is not reused as the next new chat")
        other.setModel("opus")
        await settle()
        check(conversationFiles().contains("\(other.id.uuidString).json"), "empty chat with a chosen model is written")
        deleteID = other.id

        // An untouched new chat stays off disk.
        let blank = model.newChat(backend: .claude)
        blank.setBackend(.claude)
        await settle()
        blankID = blank.id
        check(blank.id != other.id, "a chat with a chosen model is not reused either")
        check(!conversationFiles().contains("\(blank.id.uuidString).json"), "untouched new chat is not written")

        model.delete(other)
        await settle()
        check(!conversationFiles().contains("\(deleteID.uuidString).json"), "deleting removes the file")
    }

    let again = AppModel()
    let back = again.sessions.first { $0.id == studioChatID }
    check(back != nil, "Studio chat is back after relaunch")
    check(back?.title == "My named chat", "title survived")
    check(back?.record.studioID == studioID, "Studio membership survived")
    check(again.studios.contains { $0.id == studioID }, "Studio survived")
    check(back?.record.backend == .codex, "agent survived")
    check(back?.record.codex?.model == "gpt-5.5" && back?.record.codex?.effort == "high", "Codex model and effort survived")
    check(!again.sessions.contains { $0.id == deleteID }, "deleted chat stays gone")
    check(!again.sessions.contains { $0.id == blankID }, "untouched chat is not restored")
    print("PASS all")
}

Task {
    do { try await run(); exit(0) } catch { print(error); exit(1) }
}
app.run()

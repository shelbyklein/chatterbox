import Foundation

/// Dot: an assistant that runs your other chats. It's a Claude chat with Chatterbox's
/// chats as tools (chatterbox-mcp): it lists, reads, starts, messages, waits on, and stops
/// them. It can't answer approvals or question cards; those stay with you.
extension ChatSession {
    var isDot: Bool { record.isDot == true }

    /// The tools Dot may use without asking: reading and messaging chats, and everything in
    /// its own computer's browser (which is walled off from the Mac).
    static let dotTools = ["list_chats", "read_chat", "send_message", "start_chat", "wait_for_reply", "stop_chat"]
        .map { "mcp__chatterbox__" + $0 } + ["mcp__computer"]

    /// chatterbox-mcp, bundled next to the app.
    static var dotToolServer: String? {
        Bundle.main.url(forAuxiliaryExecutable: "chatterbox-mcp")?.path
            ?? ProcessInfo.processInfo.environment["CHATTERBOX_MCP_BINARY"]
    }

    /// The `--mcp-config` that gives Dot's Claude Code session Chatterbox's tools.
    var dotMCPConfig: String? {
        guard isDot, let server = Self.dotToolServer else { return nil }
        var env = ["CHATTERBOX_OWN_CHAT": id.uuidString]
        for key in ["CHATTERBOX_DATA_DIR", "CHATTERBOX_AGENT_PORT"] {
            if let value = ProcessInfo.processInfo.environment[key] { env[key] = value }
        }
        var servers: [String: Any] = ["chatterbox": ["command": server, "args": [String](), "env": env]]
        // Its own computer's browser, while that's running.
        if DotComputer.shared.isRunning { servers["computer"] = ["type": "http", "url": DotComputer.shared.toolsURL] }
        let config: [String: Any] = ["mcpServers": servers]
        guard let data = try? JSONSerialization.data(withJSONObject: config) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension AppModel {
    /// Dot's chat, if it's been made.
    var dot: ChatSession? { sessions.first { $0.isDot } }

    /// Where Dot works: ~/Chatterbox/Dot (inside the data folder under tests).
    static var dotFolder: String {
        let base: URL
        if let dir = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], !dir.isEmpty {
            base = URL(fileURLWithPath: dir)
        } else {
            base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Chatterbox")
        }
        let folder = base.appendingPathComponent("Dot", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.path
    }

    /// Dot's chat, made the first time it's asked for.
    @discardableResult
    func ensureDot() -> ChatSession {
        if let dot { return dot }
        let defaults = UserDefaults.standard
        var record = ConversationRecord(
            model: defaults.string(forKey: "defaultModel") ?? "default",
            effort: defaults.string(forKey: "defaultEffort") ?? "",
            personality: Personality(rawValue: defaults.string(forKey: "defaultPersonality") ?? "") ?? .friendly
        )
        record.title = "Dot"
        record.isDot = true
        record.claudeMode = PermissionModes.defaultClaude
        record.activeBackend = .claude
        return insertSession(record)
    }

    /// Starts Dot's computer, and makes Dot's next message pick up its browser tools.
    func startDotComputer() async {
        await DotComputer.shared.start()
        dot?.restartClaudeForNewTools()
    }

    func setUpDotComputer() async {
        await DotComputer.shared.setUp()
        dot?.restartClaudeForNewTools()
    }

    func stopDotComputer() async {
        await DotComputer.shared.stop()
        dot?.restartClaudeForNewTools()
    }

    /// Dot's own chat, opened full size.
    func openDot() {
        selectedID = ensureDot().id
        showingDot = false
    }
}

extension Prompts {
    /// What Dot is for, added to its system prompt.
    static let dotInstructions = """
    # You are Dot
    You're the user's assistant inside Chatterbox. Your job is running their other chats: each is a Claude Code or Codex agent working in a project folder, a Studio (a shared folder for loosely related work), or on its own. Use the chatterbox tools to see what's going on (list_chats, read_chat), hand work to the right chat or start a new one (send_message, start_chat), wait for results (wait_for_reply), and stop a chat that's going the wrong way (stop_chat).

    - When the user names a project or chat, find it with list_chats, and read it before acting on it.
    - Prefer the chat that already has the context: the project's own chat for project work, a chat in the right Studio for creative work. Start a new chat when nothing fits, in a Studio if one matches.
    - Write to other agents the way the user would: clear, complete, with the context they need. They don't see this conversation.
    - Approvals and questions in other chats are for the user alone. Never claim to have answered one; tell the user it's waiting, and in which chat.
    - Report back briefly: what you did, which chats, and what came of it. Don't paste long transcripts; summarize them.
    - You can't see other chats' files directly. Ask that chat's agent, or read its transcript.

    # Your computer
    When the computer tools (browser_*) are available, you have your own computer: a Linux machine with a Chromium browser, separate from the user's Mac, which can't see the user's files. Use it for web work: looking things up, checking sites, reading pages, filling forms. The user can watch its screen and take over.
    - Ask the user before buying anything, sending a message or email to someone, posting publicly, or deleting anything online.
    - Never type the user's passwords. When a site needs a login, ask the user to sign in on the computer's screen themselves, then carry on.
    - Files you download stay on that computer.
    """
}

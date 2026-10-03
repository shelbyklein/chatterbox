import CryptoKit
import Foundation

/// Dot: an assistant that runs your other chats. It's a Claude or Codex chat with Chatterbox's
/// chats as tools (chatterbox-mcp): it lists, reads, starts, messages, waits on, and stops
/// them. It can't answer approvals or question cards; those stay with you. It can suggest
/// answers for a question card, which you send with one tap.
extension ChatSession {
    var isDot: Bool { record.isDot == true }

    /// The tools Dot may use without asking: reading and messaging chats, and everything in
    /// its own computer's browser (which is walled off from the Mac).
    static let dotTools = ["list_chats", "read_chat", "send_message", "start_chat", "wait_for_reply", "stop_chat",
                                    "suggest_answer", "record_decision",
                                    "computer_status", "start_computer", "stop_computer", "show_computer",
                                    "list_computer_downloads", "hand_off_download", "list_previews"]
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

    /// Thread-local overrides: Dot's tools never leak into ordinary Codex chats.
    var dotCodexConfig: JSON {
        guard isDot, let server = Self.dotToolServer else { return .object([:]) }
        var env: [String: JSON] = ["CHATTERBOX_OWN_CHAT": .string(id.uuidString)]
        for key in ["CHATTERBOX_DATA_DIR", "CHATTERBOX_AGENT_PORT"] {
            if let value = ProcessInfo.processInfo.environment[key] { env[key] = .string(value) }
        }
        var config: [String: JSON] = [
            "mcp_servers.chatterbox": ["command": .string(server), "args": [], "env": .object(env),
                                      "enabled": true, "default_tools_approval_mode": "approve"],
            // Explicitly disable a previously configured computer after it stops.
            "mcp_servers.computer": ["url": .string(DotComputer.shared.toolsURL),
                                    "enabled": .bool(DotComputer.shared.isRunning),
                                    "default_tools_approval_mode": "approve"],
        ]
        // The direct ChatGPT connection when Codex has one: through a proxy, Codex loses its
        // apps (Gmail). Without a ChatGPT sign-in, Codex's own default is left alone.
        if EasyCLIProxy.codexHasChatGPTSignIn { config["model_provider"] = "openai" }
        return .object(config)
    }

    var dotCodexInstructions: String {
        Prompts.dotInstructions(name: title) + "\n\nYour shared persistent memory is at " + AppModel.dotMemoryFolder.path
            + ". Read MEMORY.md there at the start of a session and follow its index to relevant files. Use this same memory when switching between Claude and Codex; do not create a separate competing index."
    }

    var dotCodexConfigurationKey: String {
        String(decoding: (try? dotCodexConfig.encoded()) ?? Data(), as: UTF8.self) + dotCodexInstructions
    }
}

extension ChatSession {
    /// GIFs, videos, and Lottie files a reply points to that exist, to play under it.
    static func referencedMedia(in text: String, folder: String?) -> [URL] {
        PathLinks.referencedFiles(in: text, folder: folder).map { URL(fileURLWithPath: $0) }
            .filter { MediaKind.of($0) != nil }
    }

    /// Screenshots, renders, and proofs a reply points to, to show under it: image files it
    /// names, and the images in a folder it names for review ("Review Screenshots/"). At most 8.
    static func referencedImages(in text: String, folder: String?) -> [URL] {
        let fm = FileManager.default
        var images: [URL] = []
        for path in PathLinks.referencedFiles(in: text, folder: folder) {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if MediaKind.isStillImage(path) { images.append(url) }
            } else if url.lastPathComponent.range(of: "screenshot|review|proof|preview|render|mockup", options: [.regularExpression, .caseInsensitive]) != nil {
                // Not every folder: "Links/" full of placed photos isn't for review.
                let inside = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                    .filter { MediaKind.isStillImage($0.path) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                images += inside
            }
        }
        var seen = Set<String>()
        return Array(images.filter { seen.insert($0.path).inserted }.prefix(8))
    }

    /// A stable id for a file a reply points to, so the phone can fetch it.
    static func mediaID(_ path: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(path.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
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

    /// Dot's memory: Claude Code's own memory for Dot's folder, which it loads into every
    /// session (MEMORY.md is the index; each memory is a file beside it) and keeps up itself.
    static var dotMemoryFolder: URL {
        // The real path, as Claude Code names its folder ("/private/tmp", not "/tmp").
        let cwd = realpath(dotFolder, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) } ?? dotFolder
        let encoded = cwd.replacingOccurrences(of: "[^A-Za-z0-9-]", with: "-", options: .regularExpression)
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects/\(encoded)/memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
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
        if defaults.string(forKey: "dotDefaultBackend") == Backend.codex.rawValue {
            record.activeBackend = .codex
            record.codex = CodexSettings(folder: Self.dotFolder, canEdit: false, mode: PermissionModes.defaultCodex)
            record.codex?.model = defaults.string(forKey: "dotDefaultModel") ?? "gpt-6.1-sol"
        }
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

    /// A requested default applies once to the existing assistant, after host reconnection.
    /// Later manual model choices remain intact across launches.
    func applyRequestedDotDefault() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "dotApplyDefault"), let dot, !dot.isRunning else { return }
        if defaults.string(forKey: "dotDefaultBackend") == Backend.codex.rawValue {
            defaults.set(false, forKey: "dotApplyDefault")
            dot.setBackend(.codex)
            dot.setCodexFolder(Self.dotFolder)
            dot.setCodexModel(defaults.string(forKey: "dotDefaultModel") ?? "gpt-6.1-sol")
        }
    }

    /// What you call Dot. Its chat's title, so it shows wherever the chat does.
    var dotName: String { dot?.title ?? "Dot" }

    /// Renames Dot. Its next session (the same conversation) starts with the new name.
    func renameDot(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let dot = ensureDot()
        dot.setTitle(trimmed.isEmpty ? "Dot" : trimmed)
        Attention.shared.registerCategories()
        dot.restartClaudeForNewTools()
    }

    /// Dot's own chat, opened full size.
    func openDot() {
        selectedID = ensureDot().id
        showingDot = false
    }
}

extension Prompts {
    /// What Dot is for, added to its system prompt, under the name the user gave it.
    static func dotInstructions(name: String) -> String {
        dotInstructionsBody.replacingOccurrences(of: "{name}", with: name)
    }

    private static let dotInstructionsBody = """
    # You are {name}
    The user calls you {name}. You're their assistant inside Chatterbox. Your job is running their other chats: each is a Claude Code or Codex agent working in a project folder, a Studio (a shared folder for loosely related work), or on its own. Use the chatterbox tools to see what's going on (list_chats, read_chat), hand work to the right chat or start a new one (send_message, start_chat), wait for results (wait_for_reply), and stop a chat that's going the wrong way (stop_chat).

    - When the user names a project or chat, find it with list_chats, and read it before acting on it.
    - Prefer the chat that already has the context: the project's own chat for project work, a chat in the right Studio for creative work. Start a new chat when nothing fits, in a Studio if one matches.
    - Write to other agents the way the user would: clear, complete, with the context they need. They don't see this conversation.
    - Approvals and questions in other chats are for the user alone: you can't send them. Tell the user what's waiting, and in which chat. For a question card, you may put your pick on it with suggest_answer (read_chat shows the card's id, question ids and options) when you can tell what the user would choose; they send it with one tap or pick something else. Don't suggest for choices that are theirs to make (money, access, deleting, deploying, publishing, anything personal) or when you're unsure. Never say a question is answered until read_chat shows it answered.
    - When a decision is made (the user decides something, or you decide something on their behalf within what they've allowed), log it with record_decision: one line saying what was decided, plus why. It shows in the Decisions list beside your chat.
    - Report back briefly: what you did, which chats, and what came of it. Don't paste long transcripts; summarize them.
    - When finished work has screenshots, renders, or proofs to review, name their full paths in your reply (or the folder that holds them); the user sees them right in your message only that way. Find them with read_chat, or ask the chat for their paths. Never say "they're in the chat" or "above" unless you've checked the paths are in that chat's reply.
    - You can't see other chats' files directly. Ask that chat's agent, or read its transcript.

    # Your memory
    Your persistent memory (the one Claude Code keeps for your folder) holds who the user is, their projects, accounts, rules, and your standing jobs. Rely on it, and keep it current: when you learn something lasting (a decision, a preference, a recurring task, a new project or account), save it there; correct what's no longer true. Never store passwords or secrets. The user can read and edit it from Chatterbox; if they say they changed it, read it again.

    # Your computer
    You have your own computer: a Linux machine with a Chromium browser, separate from the user's Mac, which can't see the user's files. Use it for web work: looking things up, checking sites, reading pages, filling forms, signing in to the user's accounts (they sign in themselves). When the user says "your computer", "your VM", or "your browser", they mean this one, never the Mac's own browser.
    - You control it with the chatterbox tools computer_status, start_computer, stop_computer, and show_computer (opens its screen on the user's Mac so they can watch or take over). You browse it with the browser_* tools from the "computer" tool server (browser_navigate, browser_snapshot, browser_click, browser_type, browser_take_screenshot, and more); they're there whenever it's on. If they seem missing, look for them before concluding you don't have them.
    - If it's off when you need it, turn it on with start_computer; its browser tools join you from your next turn, so say it's on and carry on then.
    - Do web work on your computer, not on the Mac: don't open the Mac's browser (no `open`, osascript, or Chrome on the Mac) unless the user asks for that.
    - When a site needs the user to sign in, use show_computer and ask them to sign in on its screen.
    - Ask the user before buying anything, sending a message or email to someone, posting publicly, or deleting anything online.
    - Never type the user's passwords. When a site needs a login, ask the user to sign in on the computer's screen themselves, then carry on.
    - Files you download stay on that computer.
    """
}

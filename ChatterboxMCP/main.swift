import Foundation

// chatterbox-mcp: Chatterbox's chats as tools for an agent (Dot), over the Model Context
// Protocol on stdin and stdout. It talks to the running Chatterbox through its local agent
// connection (127.0.0.1, with the key Chatterbox writes at each launch). Approvals and
// question cards are left to the person: there's no tool to answer them.

let port = ProcessInfo.processInfo.environment["CHATTERBOX_AGENT_PORT"].flatMap(UInt16.init) ?? 47_320
/// The agent's own chat, which it shouldn't message or wait on.
let ownChat = ProcessInfo.processInfo.environment["CHATTERBOX_OWN_CHAT"].flatMap(UUID.init(uuidString:))

let tokenFile: URL = {
    if let dir = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], !dir.isEmpty {
        return URL(fileURLWithPath: dir).appendingPathComponent("agent-token")
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chatterbox/agent-token")
}()

struct ToolError: Error { var message: String }

// MARK: - Talking to Chatterbox

/// One HTTP call to the running app, waiting for its answer.
func call(_ path: String, method: String = "GET", body: Any? = nil) throws -> Any {
    guard let token = try? String(contentsOf: tokenFile, encoding: .utf8) else {
        throw ToolError(message: "Chatterbox isn't running (no agent key at \(tokenFile.path)).")
    }
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue(token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-Chatterbox-Token")
    if let body {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let done = DispatchSemaphore(value: 0)
    var result: Result<(Data, Int), Error> = .failure(ToolError(message: "No answer from Chatterbox."))
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error { result = .failure(ToolError(message: "Couldn't reach Chatterbox: \(error.localizedDescription)")) }
        else { result = .success((data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0)) }
        done.signal()
    }.resume()
    done.wait()
    let (data, status) = try result.get()
    let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    if status != 200 {
        throw ToolError(message: ((json as? [String: Any])?["error"] as? String) ?? "Chatterbox answered \(status).")
    }
    return json
}

func chatList() throws -> [[String: Any]] {
    ((try call("/v1/chats") as? [String: Any])?["groups"] as? [[String: Any]]) ?? []
}

/// A chat named by its id, or by (part of) its title or project name.
func resolveChat(_ reference: String) throws -> [String: Any] {
    let wanted = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    let chats = try chatList().flatMap { ($0["chats"] as? [[String: Any]]) ?? [] }
    if let exact = chats.first(where: { ($0["id"] as? String)?.lowercased() == wanted.lowercased() }) { return exact }
    func name(_ chat: [String: Any]) -> String { "\(chat["project"] as? String ?? "") \(chat["title"] as? String ?? "")" }
    let matches = chats.filter { name($0).localizedCaseInsensitiveContains(wanted) }
    if matches.count == 1 { return matches[0] }
    if matches.isEmpty {
        // A chat that isn't listed (new and empty, or archived) can still be opened by id.
        if UUID(uuidString: wanted) != nil, let detail = try? call("/v1/chats/\(wanted)") as? [String: Any],
           let summary = detail["summary"] as? [String: Any] { return summary }
        throw ToolError(message: "No chat matches \u{201C}\(wanted)\u{201D}. Use list_chats to see them.")
    }
    let names = matches.prefix(6).map { "\(name($0).trimmingCharacters(in: .whitespaces)) [\($0["id"] as? String ?? "")]" }
    throw ToolError(message: "Several chats match \u{201C}\(wanted)\u{201D}: \(names.joined(separator: "; ")). Use the id.")
}

func chatID(_ arguments: [String: Any]) throws -> String {
    guard let reference = arguments["chat"] as? String, !reference.isEmpty else { throw ToolError(message: "Say which chat (its title or id).") }
    let id = try resolveChat(reference)["id"] as? String ?? reference
    if let ownChat, id.lowercased() == ownChat.uuidString.lowercased() { throw ToolError(message: "That's your own chat.") }
    return id
}

// MARK: - Describing chats

func describe(_ chat: [String: Any]) -> String {
    var status: [String] = [(chat["backend"] as? String) == "codex" ? "Codex" : "Claude"]
    if chat["isWaitingOnYou"] as? Bool == true { status.append("waiting on the user") }
    else if chat["isRunning"] as? Bool == true { status.append("working") }
    let title = [chat["project"] as? String, chat["title"] as? String].compactMap { $0 }.joined(separator: " — ")
    var line = "- \(title) [\(chat["id"] as? String ?? "")] (\(status.joined(separator: ", ")))"
    if let subtitle = chat["subtitle"] as? String, !subtitle.isEmpty { line += "\n  Last: \(subtitle)" }
    return line
}

func transcript(_ detail: [String: Any], last: Int) -> String {
    let summary = detail["summary"] as? [String: Any] ?? [:]
    var out = [describe(summary).dropFirst(2).description, "Settings: \(detail["settings"] as? String ?? "")"]
    if let folder = detail["folder"] as? String { out.append("Folder: \(folder)") }
    let items = ((detail["items"] as? [[String: Any]]) ?? []).suffix(last)
    for item in items {
        let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch item["kind"] as? String {
        case "user": out.append("User: \(text)")
        case "assistant": out.append((item["isCommentary"] as? Bool == true ? "Agent (note): " : "Agent: ") + text)
        case "tool": out.append("[tool \(item["toolState"] as? String ?? "")] \(text)")
        case "notice": out.append("[\(text)]")
        case "plan": out.append("Plan:\n" + text)
        case "shell": out.append("User ran: $ \(text)")
        case "approval":
            let pending = item["isPending"] as? Bool == true
            out.append("[\(pending ? "WAITING FOR THE USER'S APPROVAL" : "approval") — \(text)\((item["detail"] as? String).map { ": " + $0.prefix(300) } ?? "")]")
        case "questions":
            out.append("[\(item["isPending"] as? Bool == true ? "WAITING FOR THE USER TO ANSWER" : "answered") questions: \(text)]")
        case "image": out.append("[image\(text.isEmpty ? "" : ": " + text)]")
        default: break
        }
    }
    return out.joined(separator: "\n\n")
}

// MARK: - The computer

func computerState(_ status: Any) -> String { (status as? [String: Any])?["state"] as? String ?? "unknown" }

func describeComputer(_ status: Any) throws -> String {
    let detail = (status as? [String: Any])?["detail"] as? String ?? ""
    switch computerState(status) {
    case "running": return "Your computer is on. Its browser tools (browser_navigate, browser_snapshot, browser_click, browser_type, browser_take_screenshot, and more) are yours to use; if they aren't in this turn yet, they will be from your next."
    case "stopped": return "Your computer is off. Turn it on with start_computer."
    case "starting", "setting_up", "checking": return "Your computer is still starting" + (detail.isEmpty ? "." : ": " + detail)
    case "not_set_up": return "Your computer hasn't been set up yet. start_computer sets it up (a few minutes the first time) and turns it on."
    case "no_docker": return "Docker isn't installed on the Mac, so your computer can't run. The user can install Docker Desktop."
    case "failed": throw ToolError(message: "Your computer had a problem: " + detail)
    default: return "Your computer's state is unknown."
    }
}

// MARK: - Tools

struct Tool {
    var name: String
    var description: String
    var properties: [String: [String: Any]]
    var required: [String]
    var run: ([String: Any]) throws -> String
}

let tools: [Tool] = [
    Tool(name: "list_chats",
         description: "List the user's Chatterbox chats, grouped as in the sidebar (Projects, each Studio, other chats), with each chat's id, agent, whether it's working or waiting on the user, and its latest line.",
         properties: [:], required: []) { _ in
        let groups = try chatList()
        guard !groups.isEmpty else { return "No chats." }
        return groups.map { group in
            let chats = ((group["chats"] as? [[String: Any]]) ?? []).filter { chat in
                guard let ownChat else { return true }
                return (chat["id"] as? String)?.lowercased() != ownChat.uuidString.lowercased()
            }
            var header = "## \(group["title"] as? String ?? "")"
            if let studio = group["studioID"] as? String { header += " (Studio \(studio))" }
            return ([header] + chats.map(describe)).joined(separator: "\n")
        }.joined(separator: "\n\n")
    },
    Tool(name: "read_chat",
         description: "Read a chat's recent transcript: the user's messages, the agent's replies, tools it used, and anything waiting on the user.",
         properties: ["chat": ["type": "string", "description": "The chat's title (or part of it) or id."],
                      "last": ["type": "integer", "description": "How many recent rows to include (default 30)."]],
         required: ["chat"]) { arguments in
        let id = try chatID(arguments)
        guard let detail = try call("/v1/chats/\(id)") as? [String: Any] else { throw ToolError(message: "Couldn't read that chat.") }
        return transcript(detail, last: arguments["last"] as? Int ?? 30)
    },
    Tool(name: "send_message",
         description: "Send a message to a chat's agent, as if the user typed it. If the agent is working, the message joins its current reply; set send_now to stop it and send right away.",
         properties: ["chat": ["type": "string", "description": "The chat's title (or part of it) or id."],
                      "text": ["type": "string", "description": "The message."],
                      "send_now": ["type": "boolean", "description": "Stop the agent's current reply and send this immediately."]],
         required: ["chat", "text"]) { arguments in
        let id = try chatID(arguments)
        guard let text = arguments["text"] as? String, !text.isEmpty else { throw ToolError(message: "Nothing to send.") }
        _ = try call("/v1/chats/\(id)/messages", method: "POST", body: ["text": text, "now": arguments["send_now"] as? Bool ?? false, "fromDot": true])
        return "Sent. Use wait_for_reply to get the answer, or carry on: if you don't, Chatterbox tells you when the chat finishes so you can report back to the user."
    },
    Tool(name: "start_chat",
         description: "Start a new chat, on its own or inside a Studio, optionally with a first message. Returns the new chat's id.",
         properties: ["studio": ["type": "string", "description": "A Studio's name or id to start the chat in (optional)."],
                      "agent": ["type": "string", "enum": ["claude", "codex"], "description": "Which agent answers (optional; the user's default otherwise)."],
                      "message": ["type": "string", "description": "A first message to send (optional)."]],
         required: []) { arguments in
        var body: [String: Any] = [:]
        if let agent = arguments["agent"] as? String { body["backend"] = agent }
        if let studio = arguments["studio"] as? String, !studio.isEmpty {
            let studios = try chatList().filter { $0["studioID"] != nil }
            guard let match = studios.first(where: { ($0["studioID"] as? String)?.lowercased() == studio.lowercased() })
                    ?? studios.first(where: { ($0["title"] as? String)?.localizedCaseInsensitiveContains(studio) == true }),
                  let studioID = match["studioID"] else { throw ToolError(message: "No Studio matches \u{201C}\(studio)\u{201D}.") }
            body["studio"] = studioID
        }
        guard let detail = try call("/v1/chats", method: "POST", body: body) as? [String: Any],
              let id = (detail["summary"] as? [String: Any])?["id"] as? String else { throw ToolError(message: "Couldn't start a chat.") }
        if let message = arguments["message"] as? String, !message.isEmpty {
            _ = try call("/v1/chats/\(id)/messages", method: "POST", body: ["text": message, "fromDot": true])
            return "Started chat \(id) and sent the message. Use wait_for_reply with chat \(id)."
        }
        return "Started chat \(id)."
    },
    Tool(name: "wait_for_reply",
         description: "Wait until a chat's agent finishes its reply (or stops to wait on the user), then return its latest reply. Waits up to timeout_seconds (default 300, at most 1800).",
         properties: ["chat": ["type": "string", "description": "The chat's title (or part of it) or id."],
                      "timeout_seconds": ["type": "integer", "description": "How long to wait at most."]],
         required: ["chat"]) { arguments in
        let id = try chatID(arguments)
        let limit = Double(min(max(arguments["timeout_seconds"] as? Int ?? 300, 5), 1800))
        let start = Date()
        Thread.sleep(forTimeInterval: 1.5)
        while true {
            guard let detail = try call("/v1/chats/\(id)") as? [String: Any], let summary = detail["summary"] as? [String: Any] else {
                throw ToolError(message: "Couldn't read that chat.")
            }
            let waiting = summary["isWaitingOnYou"] as? Bool == true
            if summary["isRunning"] as? Bool != true || waiting {
                let items = (detail["items"] as? [[String: Any]]) ?? []
                let reply = items.last { $0["kind"] as? String == "assistant" && $0["isCommentary"] as? Bool != true }?["text"] as? String
                return (waiting ? "The chat is waiting on the user (an approval or questions only they can answer).\n\n" : "Done.\n\n")
                    + "Latest reply:\n" + (reply ?? "(none)")
            }
            if Date().timeIntervalSince(start) > limit {
                return "Still working after \(Int(limit))s. Check back with wait_for_reply or read_chat."
            }
            Thread.sleep(forTimeInterval: 2)
        }
    },
    Tool(name: "stop_chat",
         description: "Stop a chat's agent in the middle of its reply.",
         properties: ["chat": ["type": "string", "description": "The chat's title (or part of it) or id."]],
         required: ["chat"]) { arguments in
        let id = try chatID(arguments)
        _ = try call("/v1/chats/\(id)/stop", method: "POST", body: [String: Any]())
        return "Stopped."
    },
    Tool(name: "computer_status",
         description: "Whether your own computer (the Linux machine with Chromium you browse through the browser_* tools) is running, stopped, starting, or not set up.",
         properties: [:], required: []) { _ in
        try describeComputer(call("/v1/computer"))
    },
    Tool(name: "start_computer",
         description: "Turn on your own computer (opening Docker on the Mac if needed) and wait until its browser is ready, up to about two minutes. Its browser_* tools join you from your next turn; finish this turn by telling the user it's on.",
         properties: [:], required: []) { _ in
        var status = try call("/v1/computer/start", method: "POST", body: [String: Any]())
        let start = Date()
        while ["starting", "setting_up", "checking", "stopped"].contains(computerState(status)), Date().timeIntervalSince(start) < 150 {
            Thread.sleep(forTimeInterval: 2)
            status = try call("/v1/computer")
        }
        return try describeComputer(status)
    },
    Tool(name: "stop_computer",
         description: "Turn off your own computer to free up the Mac. Its browser profile (sign-ins) is kept for next time.",
         properties: [:], required: []) { _ in
        _ = try call("/v1/computer/stop", method: "POST", body: [String: Any]())
        Thread.sleep(forTimeInterval: 4)
        return try describeComputer(call("/v1/computer"))
    },
    Tool(name: "list_computer_downloads",
         description: "List files your computer's browser has downloaded (newest first). They're in the computer's Downloads folder, the only folder it shares with the Mac.",
         properties: [:], required: []) { _ in
        guard let files = try call("/v1/computer/downloads") as? [[String: Any]], !files.isEmpty else { return "No downloads yet." }
        return files.map { "\($0["name"] as? String ?? "?") (\(($0["bytes"] as? Int ?? 0) / 1024) KB)" }.joined(separator: "\n")
    },
    Tool(name: "hand_off_download",
         description: "Copy one file your computer's browser downloaded into this chat's project folder on the Mac, where Mac-side tools (SKD Studio, design apps, scripts) can use it. Lands in handoff/ unless you give a folder (ending in /) or path inside the project. Never overwrites.",
         properties: ["file": ["type": "string", "description": "The downloaded file's name, from list_computer_downloads."],
                      "to": ["type": "string", "description": "Optional: a folder (ending in /) or file path inside the project, like wp-content/uploads/originals/."]],
         required: ["file"]) { arguments in
        guard let file = arguments["file"] as? String, !file.isEmpty else { throw ToolError(message: "Which file?") }
        guard let ownChat else { throw ToolError(message: "This tool server isn't attached to a chat.") }
        var body: [String: Any] = ["file": file, "chat": ownChat.uuidString]
        if let to = arguments["to"] as? String, !to.isEmpty { body["to"] = to }
        let result = try call("/v1/computer/handoff", method: "POST", body: body) as? [String: Any]
        return "Copied to \(result?["path"] as? String ?? "the project") on the Mac."
    },
    Tool(name: "list_previews",
         description: "Local previews (like SKD Studio sites) the user has let your computer's browser open, with their addresses. Open them with browser_navigate at exactly that address. If the one you need isn't listed, ask the user to turn it on in Chatterbox's Computer window.",
         properties: [:], required: []) { _ in
        guard let previews = try call("/v1/computer/previews") as? [[String: Any]], !previews.isEmpty else {
            return "No local previews are turned on. Ask the user to enable the one you need in Chatterbox's Computer window (Local previews)."
        }
        return previews.map { "\($0["url"] as? String ?? "") — \($0["title"] as? String ?? "")" }.joined(separator: "\n")
    },
    Tool(name: "show_computer",
         description: "Open your computer's screen in a window on the user's Mac, so they can watch or take over (for example to sign in to a site themselves).",
         properties: [:], required: []) { _ in
        _ = try call("/v1/computer/show", method: "POST", body: [String: Any]())
        return "The user's Mac is showing your computer's screen."
    },
]

/// A project chat gets only the computer's tools; the assistant gets all of them.
let computerOnly = ProcessInfo.processInfo.environment["CHATTERBOX_MCP_TOOLS"] == "computer"
let computerTools: Set<String> = ["computer_status", "start_computer", "stop_computer", "show_computer",
                                  "list_computer_downloads", "hand_off_download", "list_previews"]
let shownTools = computerOnly ? tools.filter { computerTools.contains($0.name) } : tools

// MARK: - The protocol

func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message), var line = String(data: data, encoding: .utf8) else { return }
    line += "\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}

func reply(_ id: Any, _ result: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": result]) }

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = message["method"] as? String else { continue }
    let id = message["id"]
    switch method {
    case "initialize":
        let asked = (message["params"] as? [String: Any])?["protocolVersion"] as? String
        reply(id ?? 0, ["protocolVersion": asked ?? "2025-06-18",
                        "capabilities": ["tools": [String: Any]()],
                        "serverInfo": ["name": "chatterbox", "version": "0.1.0"],
                        "instructions": "Tools for the user's Chatterbox chats: list, read, start, message, wait on, and stop them. Approvals and questions in a chat are only for the user."])
    case "tools/list":
        reply(id ?? 0, ["tools": shownTools.map { tool in
            ["name": tool.name, "description": tool.description,
             "inputSchema": ["type": "object", "properties": tool.properties, "required": tool.required]]
        }])
    case "tools/call":
        let params = message["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard let tool = shownTools.first(where: { $0.name == name }) else {
            reply(id ?? 0, ["content": [["type": "text", "text": "No tool named \(name)."]], "isError": true])
            continue
        }
        do {
            reply(id ?? 0, ["content": [["type": "text", "text": try tool.run(arguments)]]])
        } catch let error as ToolError {
            reply(id ?? 0, ["content": [["type": "text", "text": error.message]], "isError": true])
        } catch {
            reply(id ?? 0, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
        }
    case "ping":
        reply(id ?? 0, [:])
    default:
        // Notifications (no id) need no answer; unknown requests get a method-not-found error.
        if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method \(method)"]]) }
    }
}

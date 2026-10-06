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

/// Projects' own chats (not their worktrees or Sidechats).
func projectChats() throws -> [[String: Any]] {
    var result: [[String: Any]] = []
    for group in try chatList() where (group["kind"] as? String) == "projects" {
        let chats: [[String: Any]] = (group["chats"] as? [[String: Any]]) ?? []
        for chat in chats where chat["worktreeBranch"] == nil && chat["sidechatOf"] == nil { result.append(chat) }
    }
    return result
}

/// A project by its chat's id, its exact name, or part of its name.
func findProject(_ wanted: String, in projects: [[String: Any]]) -> [String: Any]? {
    func name(_ chat: [String: Any]) -> String { (chat["project"] as? String) ?? "" }
    if let byID = projects.first(where: { ($0["id"] as? String)?.lowercased() == wanted.lowercased() }) { return byID }
    if let exact = projects.first(where: { name($0).caseInsensitiveCompare(wanted) == .orderedSame }) { return exact }
    return projects.first { name($0).localizedCaseInsensitiveContains(wanted) }
}

func presetList() throws -> [[String: Any]] {
    (try call("/v1/presets") as? [[String: Any]]) ?? []
}

/// A preset by its nickname or title, ignoring case.
func resolvePreset(_ name: String) throws -> [String: Any] {
    let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let presets = try presetList()
    if let match = presets.first(where: { ($0["nickname"] as? String)?.caseInsensitiveCompare(wanted) == .orderedSame })
        ?? presets.first(where: { ($0["title"] as? String)?.caseInsensitiveCompare(wanted) == .orderedSame })
        ?? presets.first(where: { ($0["title"] as? String)?.localizedCaseInsensitiveContains(wanted) == true }) {
        return match
    }
    let names = presets.map { ($0["nickname"] as? String) ?? ($0["title"] as? String ?? "") }.joined(separator: ", ")
    throw ToolError(message: "No preset is called \u{201C}\(wanted)\u{201D}. Presets: \(names).")
}

/// The nicknames, as they're added to start_chat's description when the tools are listed.
func presetNicknames() -> String {
    guard let presets = try? presetList() else { return "" }
    let named = presets.compactMap { preset -> String? in
        guard let nickname = preset["nickname"] as? String else { return nil }
        return "\u{201C}\(nickname)\u{201D} (\(preset["summary"] as? String ?? ""))"
    }
    return named.isEmpty ? "" : " The user's preset nicknames: " + named.joined(separator: ", ") + "."
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

/// A message's text. "message" is the name start_chat and send_message both use; "text" was
/// send_message's old name, and models trip between the two, so either is read.
func messageText(_ arguments: [String: Any]) -> String? {
    for key in ["message", "text"] {
        if let value = arguments[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
    }
    return nil
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
            guard item["isPending"] as? Bool == true else {
                out.append("[answered questions: \(text)]")
                break
            }
            // Everything suggest_answer needs: the card's id, and each question's id and options.
            var lines = ["[WAITING FOR THE USER TO ANSWER] question card \(item["id"] as? String ?? "")"]
            for question in (item["questions"] as? [[String: Any]]) ?? [] {
                let options = ((question["options"] as? [[String: Any]]) ?? []).compactMap { option -> String? in
                    guard let label = option["label"] as? String else { return nil }
                    let detail = option["detail"] as? String ?? ""
                    return "  - \(label)" + (detail.isEmpty || detail == label ? "" : ": \(detail)")
                }
                var head = "- question id \u{201C}\(question["id"] as? String ?? "")\u{201D}: \(question["question"] as? String ?? "")"
                if question["multiSelect"] as? Bool == true { head += " (choose any)" }
                if question["isSecret"] as? Bool == true { head += " (secret: only the user can answer)" }
                lines.append(([head] + options).joined(separator: "\n"))
            }
            if let suggested = item["suggested"] as? [String: [String]] {
                lines.append("Already suggested: " + suggested.map { "\($0.key) \u{2192} \($0.value.joined(separator: ", "))" }.joined(separator: "; "))
            }
            out.append(lines.joined(separator: "\n"))
        case "image": out.append("[image\(text.isEmpty ? "" : ": " + text)]")
        default: break
        }
    }
    return out.joined(separator: "\n\n")
}

// MARK: - Tools

struct Tool {
    var name: String
    var description: String
    var properties: [String: [String: Any]]
    var required: [String]
    var run: ([String: Any]) throws -> String
}

let startChatProperties: [String: [String: Any]] = ["studio": ["type": "string", "description": "A Studio's name or id to start the chat in (optional)."],
                      "project": ["type": "string", "description": "A project's name (or its chat's id) to start a Sidechat of (optional; not with studio)."],
                      "preset": ["type": "string", "description": "A preset's nickname or title: its agent, model and effort (optional). See list_presets."],
                      "agent": ["type": "string", "enum": ["claude", "codex"], "description": "Which agent answers (optional; the preset's, or the user's default otherwise)."],
                      "message": ["type": "string", "description": "A first message to send (optional)."]]

func startChat(_ arguments: [String: Any]) throws -> String {
        var body: [String: Any] = [:]
        if let agent = arguments["agent"] as? String { body["backend"] = agent }
        if let name = arguments["preset"] as? String, !name.isEmpty {
            let preset = try resolvePreset(name)
            body["preset"] = preset["id"]
            if arguments["agent"] == nil { body["backend"] = preset["backend"] }
        }
        if let project = arguments["project"] as? String, !project.isEmpty {
            guard arguments["studio"] == nil else { throw ToolError(message: "Give a project or a Studio, not both.") }
            let wanted = project.trimmingCharacters(in: .whitespacesAndNewlines)
            let projects = try projectChats()
            guard let match = findProject(wanted, in: projects), let id = match["id"] else {
                let names = projects.compactMap { $0["project"] as? String }.prefix(30).joined(separator: ", ")
                throw ToolError(message: "No project matches \u{201C}\(wanted)\u{201D}. Projects: \(names).")
            }
            body["project"] = id
        }
        if let studio = arguments["studio"] as? String, !studio.isEmpty {
            let studios = try chatList().filter { $0["studioID"] != nil }
            guard let match = studios.first(where: { ($0["studioID"] as? String)?.lowercased() == studio.lowercased() })
                    ?? studios.first(where: { ($0["title"] as? String)?.localizedCaseInsensitiveContains(studio) == true }),
                  let studioID = match["studioID"] else { throw ToolError(message: "No Studio matches \u{201C}\(studio)\u{201D}.") }
            body["studio"] = studioID
        }
        guard let detail = try call("/v1/chats", method: "POST", body: body) as? [String: Any],
              let id = (detail["summary"] as? [String: Any])?["id"] as? String else { throw ToolError(message: "Couldn't start a chat.") }
        if let message = messageText(arguments) {
            _ = try call("/v1/chats/\(id)/messages", method: "POST", body: ["text": message, "fromDot": true])
            return "Started chat \(id) and sent the message. Use wait_for_reply with chat \(id)."
        }
        return "Started chat \(id)."
    }

let startChatTool: Tool = Tool(name: "start_chat",
         description: "Start a new chat, on its own, inside a Studio, or as a Sidechat of a project (a temporary thread in the project's folder with its own history, so the project's main chat isn't disturbed), optionally with a model preset and a first message. When the user says \u{201C}start that in <place> with <name>\u{201D}, <place> is a project or Studio and <name> is a preset's nickname. Put everything the new chat needs into the message: it can't see this conversation. Returns the new chat's id.",
         properties: startChatProperties,
         required: [], run: startChat)

let listPresetsTool: Tool = Tool(name: "list_presets",
         description: "The user's model presets: each one's nickname (what the user calls it), title, and the agent, model and effort it switches to. Use a nickname with start_chat's preset.",
         properties: [:], required: []) { _ in
        let presets = try presetList()
        guard !presets.isEmpty else { return "No presets." }
        return presets.map { preset in
            let nickname = (preset["nickname"] as? String).map { "\u{201C}\($0)\u{201D} \u{2014} " } ?? ""
            return "\(nickname)\(preset["title"] as? String ?? ""): \(preset["summary"] as? String ?? "")"
        }.joined(separator: "\n")
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
                      "message": ["type": "string", "description": "The message."],
                      "send_now": ["type": "boolean", "description": "Stop the agent's current reply and send this immediately."]],
         required: ["chat", "message"]) { arguments in
        let id = try chatID(arguments)
        guard let text = messageText(arguments) else { throw ToolError(message: "Nothing to send: put the message in \"message\".") }
        _ = try call("/v1/chats/\(id)/messages", method: "POST", body: ["text": text, "now": arguments["send_now"] as? Bool ?? false, "fromDot": true])
        return "Sent. Use wait_for_reply to get the answer, or carry on: if you don't, Chatterbox tells you when the chat finishes so you can report back to the user."
    },
    startChatTool,
    listPresetsTool,
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
    Tool(name: "suggest_answer",
         description: "Suggest answers for a question card waiting on the user in another chat. The card shows your pick and reason; the user sends it with one tap or chooses something else. This never sends an answer. Use read_chat first for the card id, question ids and option labels.",
         properties: ["chat": ["type": "string", "description": "The chat's title (or part of it) or id."],
                      "card": ["type": "string", "description": "The question card's id, from read_chat."],
                      "answers": ["type": "object", "description": "Question id → list of option labels (one for single-choice questions). A label that isn't an option is shown as typed text.",
                                  "additionalProperties": ["type": "array", "items": ["type": "string"]]],
                      "reason": ["type": "string", "description": "One short line on why, shown to the user."]],
         required: ["chat", "card", "answers", "reason"]) { arguments in
        let id = try chatID(arguments)
        guard let card = arguments["card"] as? String, UUID(uuidString: card) != nil else { throw ToolError(message: "Give the card's id from read_chat.") }
        guard let raw = arguments["answers"] as? [String: Any], !raw.isEmpty else { throw ToolError(message: "No answers to suggest.") }
        var answers: [String: [String]] = [:]
        for (question, value) in raw {
            if let list = value as? [String] { answers[question] = list } else if let one = value as? String { answers[question] = [one] }
        }
        _ = try call("/v1/chats/\(id)/suggestions/\(card)", method: "POST", body: ["answers": answers, "reason": arguments["reason"] as? String ?? ""])
        return "Suggested. It's on the card for the user to send or change; nothing was sent. Tell them it's there."
    },
    Tool(name: "record_decision",
         description: "Log a decision in your Decisions list (shown beside your chat): something the user decided, or that you decided on their behalf within what they've allowed.",
         properties: ["summary": ["type": "string", "description": "What was decided, in one line."],
                      "why": ["type": "string", "description": "Why (optional)."],
                      "chat": ["type": "string", "description": "The chat it's about, by title or id (optional)."]],
         required: ["summary"]) { arguments in
        guard let summary = arguments["summary"] as? String, !summary.isEmpty else { throw ToolError(message: "Nothing to record.") }
        var body: [String: Any] = ["summary": summary]
        if let why = arguments["why"] as? String { body["why"] = why }
        if arguments["chat"] as? String != nil { body["chat"] = try chatID(arguments) }
        _ = try call("/v1/decisions", method: "POST", body: body)
        return "Recorded."
    },
    Tool(name: "stop_chat",
         description: "Stop a chat's agent in the middle of its reply.",
         properties: ["chat": ["type": "string", "description": "The chat's title (or part of it) or id."]],
         required: ["chat"]) { arguments in
        let id = try chatID(arguments)
        _ = try call("/v1/chats/\(id)/stop", method: "POST", body: [String: Any]())
        return "Stopped."
    },
]

// Older project sessions must not gain Golem tools after VM retirement.
let shownTools = ProcessInfo.processInfo.environment["CHATTERBOX_MCP_TOOLS"] == "computer" ? [] : tools

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
        let nicknames = presetNicknames()
        reply(id ?? 0, ["tools": shownTools.map { tool in
            ["name": tool.name, "description": tool.name == "start_chat" ? tool.description + nicknames : tool.description,
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

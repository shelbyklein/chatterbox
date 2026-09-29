import Foundation

/// The Codex backend. Codex runs its own agent loop and keeps the history, so this
/// side only starts turns, steers and interrupts them, answers approval requests,
/// and maps Codex's item events onto the same transcript rows Claude uses.
extension ChatSession {
    private var server: CodexAppServer { .shared }

    // MARK: - Settings

    func setCodexFolder(_ path: String) {
        record.codex?.folder = path
        onChange?(self)
    }

    func setCodexModel(_ model: String?) {
        guard model != record.codex?.model else { return }
        record.codex?.model = model
        record.codex?.effort = nil
        noteSettingsChange()
        onChange?(self)
    }

    func setCodexEffort(_ effort: String?) {
        guard effort != record.codex?.effort else { return }
        record.codex?.effort = effort
        noteSettingsChange()
        onChange?(self)
    }

    // MARK: - Turns

    func codexSend(_ message: UserMessage) {
        if isRunning {
            // Codex supports steering natively: the text joins the running turn.
            let item = appendUserItem(message, steered: true)
            if let turn = codexTurnID {
                Task { await codexSteer(message, turn: turn, item: item) }
            } else {
                pendingSteering.append(message)
                pendingSteeringItems.append(item)
            }
            return
        }
        setTitleIfNeeded(message)
        appendUserItem(message)
        beginCodexTurn(message)
    }

    /// `items` are queued rows this turn delivers, e.g. messages that missed the last turn.
    private func beginCodexTurn(_ message: UserMessage, items: [UUID] = []) {
        isRunning = true
        codexTurnID = nil
        codexStopRequested = false
        codexTurnMessageItems = []
        onChange?(self)
        Task { await codexStartTurn(message, items: items) }
    }

    func codexInterrupt() {
        guard let thread = record.codex?.threadId, let turn = codexTurnID else {
            codexStopRequested = true
            return
        }
        Task { try? await server.request("turn/interrupt", ["threadId": .string(thread), "turnId": .string(turn)]) }
    }

    private func codexStartTurn(_ message: UserMessage, items: [UUID]) async {
        guard let settings = record.codex else { return }
        do {
            let thread = try await codexEnsureThread()
            var input: [JSON] = []
            if record.sentPersonality != record.personality {
                input.append(Self.textInput(Prompts.personalitySpec(record.personality)))
                record.sentPersonality = record.personality
            }
            if let shell = takeShellContext() { input.append(Self.textInput(shell)) }
            if let handoff = record.pendingHandoff {
                input.append(Self.textInput(handoff))
                record.pendingHandoff = nil
            }
            if (record.instructionsVersion ?? 1) < Prompts.instructionsVersion {
                input.append(Self.textInput(Prompts.instructionsUpdate))
                record.instructionsVersion = Prompts.instructionsVersion
            }
            let user = Prompts.userInstructions
            if user != (record.sentUserInstructions ?? "") {
                input.append(Self.textInput(Prompts.userInstructionsUpdate(user)))
                record.sentUserInstructions = user
            }
            input += inputs(for: message)

            var params: [String: JSON] = [
                "threadId": .string(thread),
                "input": .array(input),
                "cwd": .string(settings.folder),
                "approvalPolicy": approvalPolicy(settings),
                "approvalsReviewer": settings.modeID == "autoReview" ? "auto_review" : "user",
                "sandboxPolicy": sandboxPolicy(settings),
            ]
            if let model = settings.model { params["model"] = .string(model) }
            if let effort = settings.effort { params["effort"] = .string(effort) }

            let result = try await server.request("turn/start", .object(params))
            items.forEach(markPickedUp)
            if isRunning, codexTurnID == nil { codexTurnID = result["turn"]?["id"]?.string }
            codexTurnDidGetID()
        } catch {
            notice("Codex couldn't start: \(error.localizedDescription)")
            codexFinish(startQueued: false)
        }
    }

    private func codexEnsureThread() async throws -> String {
        guard let settings = record.codex else { throw CodexError(message: "This chat isn't set up for Codex.") }
        try await server.ensureStarted()

        if let existing = settings.threadId {
            codexRegisterHandler(existing)
            if server.loadedThreads.contains(existing) { return existing }
            do {
                _ = try await server.request("thread/resume", [
                    "threadId": .string(existing), "cwd": .string(settings.folder), "excludeTurns": true,
                ])
                server.markLoaded(existing)
                return existing
            } catch {
                notice("Couldn't reopen the earlier Codex session, so this continues in a new one.")
                record.codex?.threadId = nil
            }
        }

        var params: [String: JSON] = [
            "cwd": .string(settings.folder),
            "approvalPolicy": approvalPolicy(settings),
            "sandbox": .string(["readOnly": "read-only", "fullAccess": "danger-full-access"][settings.modeID] ?? "workspace-write"),
            "developerInstructions": .string(Prompts.fullInstructions(record.personality, backend: .codex, projectFolder: record.boundFolder,
                                                                         studioFolder: record.studioFolder)),
        ]
        if let model = settings.model { params["model"] = .string(model) }
        let result = try await server.request("thread/start", .object(params))
        guard let id = result["thread"]?["id"]?.string else { throw CodexError(message: "Codex didn't return a thread.") }
        record.codex?.threadId = id
        record.sentPersonality = record.personality
        record.sentUserInstructions = Prompts.userInstructions
        record.instructionsVersion = Prompts.instructionsVersion
        codexRegisterHandler(id)
        server.markLoaded(id)
        onChange?(self)
        return id
    }

    /// Routes the thread's events to this chat. After a relaunch, lines the saved transcript
    /// already reflects are skipped.
    func codexRegisterHandler(_ thread: String) {
        server.register(thread: thread) { [weak self] method, params, requestID in
            guard let self else { return }
            if let skipped = self.codexSkipProcess {
                if skipped == self.server.hostID, self.server.currentLineEnd <= self.codexSkipThrough { return }
                self.codexSkipProcess = nil
            }
            self.handleCodex(method: method, params: params, requestID: requestID)
            self.onStreamed?(self)
        }
    }

    private func codexSteer(_ message: UserMessage, turn: String, item: UUID) async {
        guard let thread = record.codex?.threadId else { return }
        do {
            _ = try await server.request("turn/steer", [
                "threadId": .string(thread), "input": .array(inputs(for: message)), "expectedTurnId": .string(turn),
            ])
            markPickedUp(item)
        } catch {
            // The turn most likely finished a moment ago; send the text as a new turn.
            if isRunning {
                pendingSteering.append(message)
                pendingSteeringItems.append(item)
            } else {
                beginCodexTurn(message, items: [item])
            }
        }
    }

    /// Images go to Codex as local images; other files are named by path so Codex can open them.
    /// A leading "/skill" becomes a skill input, which Codex loads before reading the text.
    private func inputs(for message: UserMessage) -> [JSON] {
        var input: [JSON] = message.attachments.filter { $0.kind == .image }.map {
            ["type": "localImage", "path": .string($0.path)]
        }
        let files = message.attachments.filter { $0.kind != .image }
        var text = message.text
        let skills = record.codex.map { server.skills[$0.folder] ?? [] } ?? []
        if let (skill, rest) = SlashCommand.leading(text, in: skills), let path = skill.codexSkillPath {
            input.append(["type": "skill", "name": .string(skill.name), "path": .string(path)])
            text = rest.isEmpty ? "Use the \(skill.name) skill." : rest
        }
        if !files.isEmpty {
            let list = files.map { "- \($0.name): \($0.path)" }.joined(separator: "\n")
            text += (text.isEmpty ? "" : "\n\n") + "Attached files (read them from these paths):\n" + list
        }
        if !text.isEmpty { input.append(Self.textInput(text)) }
        return input
    }

    private func codexTurnDidGetID() {
        guard isRunning, let turn = codexTurnID else { return }
        if codexStopRequested {
            codexInterrupt()
            return
        }
        let queued = zip(pendingSteering, pendingSteeringItems)
        pendingSteering.removeAll()
        pendingSteeringItems.removeAll()
        for (message, item) in queued { Task { await codexSteer(message, turn: turn, item: item) } }
    }

    private func codexFinish(startQueued: Bool) {
        record.items.removeAll {
            ($0.kind == .assistant || $0.kind == .thought) && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for index in record.items.indices {
            if record.items[index].kind == .tool, record.items[index].toolState == .running {
                record.items[index].toolState = .failed
            }
            if record.items[index].approvalState == .pending {
                record.items[index].approvalState = .expired
            }
        }
        isRunning = false
        codexTurnID = nil
        codexItems = [:]
        record.updatedAt = Date()
        let queued = UserMessage(text: pendingSteering.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                                 attachments: pendingSteering.flatMap(\.attachments))
        let queuedItems = pendingSteeringItems
        pendingSteering.removeAll()
        pendingSteeringItems.removeAll()
        if startQueued, !queued.text.isEmpty || !queued.attachments.isEmpty {
            onChange?(self)
            beginCodexTurn(queued, items: queuedItems)
        } else {
            queuedItems.forEach(markPickedUp)
            onChange?(self)
        }
    }

    // MARK: - Events

    private func handleCodex(method: String, params: JSON, requestID: JSON?) {
        if let requestID {
            handleCodexRequest(method: method, params: params, id: requestID)
            return
        }
        switch method {
        case "turn/started":
            if isRunning, codexTurnID == nil {
                codexTurnID = params["turn"]?["id"]?.string
                codexTurnDidGetID()
            }

        case "item/started":
            codexItemStarted(params["item"])

        case "item/agentMessage/delta":
            if let itemID = params["itemId"]?.string, let id = codexItems[itemID], let delta = params["delta"]?.string {
                updateItem(id) { $0.text += delta }
            }

        case "item/reasoning/summaryTextDelta":
            guard let itemID = params["itemId"]?.string, let delta = params["delta"]?.string else { break }
            let id = codexItems[itemID] ?? {
                let new = appendItem(DisplayItem(kind: .thought))
                codexItems[itemID] = new
                return new
            }()
            updateItem(id) { $0.text += delta }

        case "item/completed":
            codexItemCompleted(params["item"])

        case "turn/plan/updated":
            let steps = (params["plan"]?.array ?? []).compactMap { step -> PlanStep? in
                guard let text = step["step"]?.string else { return nil }
                let status = step["status"]?.string == "inProgress" ? "in_progress" : (step["status"]?.string ?? "pending")
                return PlanStep(step: text, status: status)
            }
            let turn = params["turnId"]?.string ?? ""
            if let id = codexPlanItems[turn] {
                updateItem(id) { $0.planSteps = steps }
            } else if !steps.isEmpty {
                codexPlanItems[turn] = appendItem(DisplayItem(kind: .plan, planSteps: steps))
            }

        case "serverRequest/resolved":
            if let requestID = params["requestId"],
               let index = record.items.lastIndex(where: { $0.requestID == requestID && $0.approvalState == .pending }) {
                record.items[index].approvalState = .expired
            }

        case "error":
            if params["willRetry"] != .bool(true), let message = params["error"]?["message"]?.string {
                notice("Codex: \(message)")
            }

        case "turn/completed":
            codexTurnCompleted(params["turn"])

        case "thread/tokenUsage/updated":
            codexUpdateContext(params)

        case "chatterbox/processExited":
            if isRunning {
                notice(params["message"]?.string ?? "Codex stopped unexpectedly.")
                codexFinish(startQueued: false)
            }

        default:
            break
        }
    }

    private func codexItemStarted(_ item: JSON?) {
        guard let item, let type = item["type"]?.string, let itemID = item["id"]?.string else { return }
        switch type {
        case "agentMessage":
            let phase: DisplayItem.Phase = item["phase"]?.string == "commentary" ? .commentary : .streaming
            let id = appendItem(DisplayItem(kind: .assistant, text: item["text"]?.string ?? "", phase: phase))
            codexItems[itemID] = id
            codexTurnMessageItems.append(id)
        case "reasoning":
            if codexItems[itemID] == nil { codexItems[itemID] = appendItem(DisplayItem(kind: .thought)) }
        default:
            if let label = Self.label(for: item) {
                codexItems[itemID] = appendItem(DisplayItem(kind: .tool, text: label))
            }
        }
    }

    private func codexItemCompleted(_ item: JSON?) {
        guard let item, let type = item["type"]?.string, let itemID = item["id"]?.string else { return }
        guard let id = codexItems[itemID] else {
            // A message can finish without a start event; show it anyway.
            if type == "agentMessage", let text = item["text"]?.string, !text.isEmpty {
                let phase: DisplayItem.Phase = item["phase"]?.string == "commentary" ? .commentary : .streaming
                let id = appendItem(DisplayItem(kind: .assistant, text: text, phase: phase))
                codexItems[itemID] = id
                codexTurnMessageItems.append(id)
            }
            if type == "imageGeneration", item["failure"].map({ $0 == .null }) ?? true { showGeneratedImage(item) }
            return
        }
        switch type {
        case "agentMessage":
            updateItem(id) {
                if let text = item["text"]?.string, !text.isEmpty { $0.text = text }
                switch item["phase"]?.string {
                case "commentary": $0.phase = .commentary
                case "final_answer": $0.phase = .final
                default: break
                }
            }
        case "reasoning":
            let summary = (item["summary"]?.array ?? []).compactMap(\.string).joined(separator: "\n\n")
            if !summary.isEmpty { updateItem(id) { $0.text = summary } }
        case "imageGeneration":
            let failed = item["failure"].map { $0 != .null } ?? false
            updateItem(id) { $0.toolState = failed ? .failed : .done }
            if !failed { showGeneratedImage(item) }
        default:
            let status = item["status"]?.string
            updateItem(id) {
                if let label = Self.label(for: item) { $0.text = label }
                $0.toolState = (status == nil || status == "completed") ? .done : .failed
            }
        }
    }

    /// Copies a generated image into the attachment store and shows it in the chat.
    /// Codex saves it to disk (`savedPath`) and also returns it inline (`result`, base64).
    private func showGeneratedImage(_ item: JSON) {
        var attachment: Attachment?
        if let path = item["savedPath"]?.string, FileManager.default.fileExists(atPath: path) {
            attachment = try? Attachments.importFile(URL(fileURLWithPath: path))
        }
        if attachment == nil, let base64 = item["result"]?.string,
           let data = Data(base64Encoded: base64.replacingOccurrences(of: #"^data:image/\w+;base64,"#, with: "", options: .regularExpression)) {
            attachment = try? Attachments.importImageData(data, name: "Generated image")
        }
        guard let attachment else { return }
        appendItem(DisplayItem(kind: .image, text: item["revisedPrompt"]?.string ?? "", attachments: [attachment]))
        onChange?(self)
    }

    private func codexTurnCompleted(_ turn: JSON?) {
        // Messages without an explicit phase: the last one is the answer, the rest narration.
        let unresolved = codexTurnMessageItems.filter { id in record.items.contains { $0.id == id && $0.phase == .streaming } }
        for (index, id) in unresolved.enumerated() {
            updateItem(id) { $0.phase = index == unresolved.count - 1 ? .final : .commentary }
        }
        switch turn?["status"]?.string {
        case "interrupted":
            notice(stoppingToSend ? "Stopped to take your message." : "Stopped.")
            // "Send Now": the queued message starts the next turn right away.
            let sendQueued = stoppingToSend
            stoppingToSend = false
            codexFinish(startQueued: sendQueued)
        case "failed":
            notice("Codex hit an error: \(turn?["error"]?["message"]?.string ?? "unknown error")")
            codexFinish(startQueued: false)
        default:
            codexFinish(startQueued: true)
        }
    }

    // MARK: - Approvals

    private func handleCodexRequest(method: String, params: JSON, id: JSON) {
        switch method {
        case "item/tool/requestUserInput":
            let questions = (params["questions"]?.array ?? []).enumerated().map { index, q in
                AgentQuestion(id: q["id"]?.string ?? "q\(index)", header: q["header"]?.string ?? "",
                              question: q["question"]?.string ?? "",
                              options: (q["options"]?.array ?? []).map { .init(label: $0["label"]?.string ?? "", detail: $0["description"]?.string ?? "") },
                              multiSelect: false, isSecret: q["isSecret"]?.bool ?? false)
            }
            appendItem(DisplayItem(kind: .questions, requestID: id, approvalState: .pending, questions: questions))
        case "item/commandExecution/requestApproval":
            let reason = params["reason"]?.string
            appendItem(DisplayItem(
                kind: .approval,
                text: reason ?? "Codex wants to run a command",
                detail: params["command"]?.string,
                requestID: id,
                approvalState: .pending
            ))
        case "item/fileChange/requestApproval":
            let files = params["itemId"]?.string.flatMap { codexItems[$0] }
                .flatMap { itemID in record.items.first { $0.id == itemID }?.text }
            appendItem(DisplayItem(
                kind: .approval,
                text: params["reason"]?.string ?? "Codex wants to change files",
                detail: files,
                requestID: id,
                approvalState: .pending
            ))
        default:
            server.respondError(to: id, message: "Chatterbox can't answer \(method) yet.")
        }
        onChange?(self)
    }

    /// Sends answers keyed by question id; skipping sends none.
    func codexAnswer(_ itemID: UUID, answers: [String: [String]]?) {
        guard let item = record.items.first(where: { $0.id == itemID }),
              item.approvalState == .pending, let requestID = item.requestID else { return }
        let wire = (answers ?? [:]).mapValues { JSON.object(["answers": .array($0.map(JSON.string))]) }
        server.respond(to: requestID, result: ["answers": .object(wire)])
        updateItem(itemID) {
            $0.answers = answers
            $0.approvalState = answers == nil ? .denied : .approved
        }
        onChange?(self)
    }

    func codexResolveApproval(_ itemID: UUID, _ decision: DisplayItem.ApprovalState) {
        guard let item = record.items.first(where: { $0.id == itemID }),
              item.approvalState == .pending, let requestID = item.requestID else { return }
        let wire: String
        switch decision {
        case .approved: wire = "accept"
        case .approvedForSession: wire = "acceptForSession"
        default: wire = "decline"
        }
        server.respond(to: requestID, result: ["decision": .string(wire)])
        updateItem(itemID) { $0.approvalState = decision }
        onChange?(self)
    }

    // MARK: - Helpers

    private func sandboxPolicy(_ settings: CodexSettings) -> JSON {
        switch settings.modeID {
        case "fullAccess":
            return ["type": "dangerFullAccess"]
        case "readOnly":
            return ["type": "readOnly", "networkAccess": false]
        default:
            return [
                "type": "workspaceWrite",
                "writableRoots": [.string(settings.folder)],
                "networkAccess": false,
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false,
            ]
        }
    }

    /// Full access never asks; every other mode asks (or lets the auto reviewer decide).
    private func approvalPolicy(_ settings: CodexSettings) -> JSON {
        settings.modeID == "fullAccess" ? "never" : "on-request"
    }

    private static func textInput(_ text: String) -> JSON {
        ["type": "text", "text": .string(text), "text_elements": []]
    }

    /// Status line for a Codex tool item, or nil for items that aren't shown.
    private static func label(for item: JSON) -> String? {
        switch item["type"]?.string {
        case "commandExecution":
            let command = item["command"]?.string ?? ""
            let short = command.count > 80 ? String(command.prefix(79)) + "\u{2026}" : command
            return "Running `\(short)`"
        case "fileChange":
            let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }
            let names = paths.map { ($0 as NSString).lastPathComponent }
            if names.isEmpty { return "Editing files" }
            return "Editing " + (names.count > 3 ? names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more" : names.joined(separator: ", "))
        case "mcpToolCall":
            return "Using \(item["tool"]?.string ?? "a tool") from \(item["server"]?.string ?? "an MCP server")"
        case "dynamicToolCall":
            return "Using \(item["tool"]?.string ?? "a tool")"
        case "webSearch":
            if let query = item["query"]?.string, !query.isEmpty { return "Searching the web for \u{201C}\(query)\u{201D}" }
            return "Searching the web"
        case "imageGeneration":
            return "Generating an image"
        case "contextCompaction":
            return "Summarizing earlier conversation to make room"
        case "collabAgentToolCall", "subAgentActivity":
            return "Working with a helper agent"
        default:
            return nil
        }
    }
}

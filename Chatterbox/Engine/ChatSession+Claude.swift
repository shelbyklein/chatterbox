import Foundation

/// The Claude backend: the user's own Claude Code (`claude` CLI) in stream-json mode, one
/// process per chat. Claude Code runs the agent loop, tools, and history; this side sends
/// messages, answers permission prompts, and maps its stream onto the transcript.
extension ChatSession {
    // MARK: - Sending

    func claudeSend(_ message: UserMessage) {
        let steered = isRunning
        if !steered { setTitleIfNeeded(message) }
        let earlierItems = record.items.count
        appendUserItem(message, steered: steered)

        do {
            let process = try claudeEnsureProcess(earlierItems: earlierItems)
            var content: [JSON] = []
            if let handoff = record.pendingHandoff {
                content.append(.text(handoff))
                record.pendingHandoff = nil
            }
            if record.sentPersonality != record.personality {
                content.append(.text(Prompts.personalitySpec(record.personality)))
                record.sentPersonality = record.personality
            }
            content += Attachments.claudeContent(for: message)
            process.sendUser(content)
            if !steered {
                isRunning = true
                claudeStopRequested = false
                claudePlanItem = nil
            }
        } catch {
            notice(error.localizedDescription)
        }
        onChange?(self)
    }

    func claudeInterrupt() {
        guard isRunning, let process = claudeProcess else { return }
        claudeStopRequested = true
        process.controlNow("interrupt")
    }

    /// Starts this chat's Claude Code process if it isn't running, resuming its session.
    private func claudeEnsureProcess(earlierItems: Int) throws -> ClaudeCodeProcess {
        if let process = claudeProcess, process.isRunning { return process }

        let resuming = record.claudeSessionID != nil
        // A new session knows nothing of this chat yet (older chats, or a changed folder).
        if !resuming, record.pendingHandoff == nil, record.claudeSeenThrough == nil, earlierItems > 0 {
            let transcript = Self.transcript(record.items[0..<earlierItems])
            if !transcript.isEmpty {
                record.pendingHandoff = Prompts.handoff(from: "", transcript: transcript, isWholeConversation: true)
            }
        }
        let process = ClaudeCodeProcess()
        process.onMessage = { [weak self] message in self?.handleClaude(message) }
        process.onExit = { [weak self] status, detail in self?.claudeProcessExited(status: status, detail: detail) }
        try process.start(ClaudeCodeProcess.Config(
            cwd: claudeWorkingFolder,
            model: record.model,
            effort: record.effort,
            permissionMode: claudePermissionMode,
            appendSystemPrompt: Prompts.agentInstructions(record.personality),
            resumeSessionID: record.claudeSessionID,
            extraDirectories: [Attachments.directory.path]
        ))
        // A fresh session gets the current tone in its system prompt.
        if !resuming { record.sentPersonality = record.personality }
        claudeProcess = process
        return process
    }

    private var claudeWorkingFolder: String {
        record.projectFolder ?? UserDefaults.standard.string(forKey: "codexFolder") ?? NSHomeDirectory()
    }

    private var claudePermissionMode: String { record.claudeModeID }

    // MARK: - Live settings

    func claudeApplyModel() {
        guard let process = claudeProcess, process.isRunning else { return }
        process.controlNow("set_model", ["model": .string(record.model)])
    }

    func claudeApplyEffort() {
        guard let process = claudeProcess, process.isRunning else { return }
        let effort: JSON = record.effort.isEmpty ? .null : .string(record.effort)
        process.controlNow("apply_flag_settings", ["settings": ["effortLevel": effort]])
    }

    func claudeApplyPermissionMode() {
        guard let process = claudeProcess, process.isRunning else { return }
        process.controlNow("set_permission_mode", ["mode": .string(claudePermissionMode)])
    }

    /// Claude Code keeps sessions per folder, so a new folder means a new session,
    /// caught up on the conversation so far.
    func claudeWorkingFolderChanged() {
        guard record.claudeSessionID != nil || claudeProcess != nil else { return }
        claudeProcess?.terminate()
        claudeProcess = nil
        record.claudeSessionID = nil
        record.claudeSeenThrough = nil
        if isRunning { isRunning = false }
    }

    // MARK: - Stream

    private func handleClaude(_ message: JSON) {
        // Sub-agents report through their parent's tool call; only show the main thread.
        if case .string = message["parent_tool_use_id"] ?? .null { return }

        switch message["type"]?.string {
        case "system":
            if message["subtype"]?.string == "init", let id = message["session_id"]?.string, id != record.claudeSessionID {
                record.claudeSessionID = id
                onChange?(self)
            }

        case "stream_event":
            if let event = message["event"] { handleClaudeEvent(event) }

        case "assistant":
            // Complete blocks: tool inputs are only final here.
            for block in message["message"]?["content"]?.array ?? [] where block["type"]?.string == "tool_use" {
                guard let useID = block["id"]?.string, let name = block["name"]?.string else { continue }
                claudeToolCalls[useID] = (name, block["input"] ?? [:])
                if name == Tools.todoTool {
                    showPlan(Tools.planSteps(block["input"]))
                } else if let item = claudeToolItems[useID] {
                    updateItem(item) { $0.text = Tools.label(name: name, input: block["input"]) }
                }
            }

        case "user":
            for block in message["message"]?["content"]?.array ?? [] where block["type"]?.string == "tool_result" {
                guard let useID = block["tool_use_id"]?.string, let item = claudeToolItems[useID] else { continue }
                let failed = block["is_error"]?.bool == true
                updateItem(item) { $0.toolState = failed ? .failed : .done }
                if !failed { previewWrittenFile(useID) }
            }

        case "control_request":
            if message["request"]?["subtype"]?.string == "can_use_tool", let id = message["request_id"]?.string {
                showClaudeApproval(id: id, request: message["request"] ?? [:])
            }

        case "rate_limit_event":
            let info = message["rate_limit_info"]
            if let status = info?["status"]?.string, status != "allowed" {
                let reset = info?["resetsAt"]?.int.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                let when = reset.map { " It resets \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
                notice(status == "rejected" ? "You've hit your Claude usage limit.\(when)" : "You're close to your Claude usage limit.\(when)")
            }

        case "result":
            finishClaudeTurn(message)

        default:
            break
        }
    }

    private func handleClaudeEvent(_ event: JSON) {
        let index = event["index"]?.int ?? -1
        switch event["type"]?.string {
        case "message_start":
            claudeRender = ResponseRender()
            // Claude Code may start a new turn on its own, e.g. for a message queued during the last one.
            if !isRunning { isRunning = true }

        case "content_block_start":
            let block = event["content_block"] ?? [:]
            switch block["type"]?.string {
            case "text":
                let id = appendItem(DisplayItem(kind: .assistant, text: block["text"]?.string ?? "", phase: .streaming))
                claudeRender.itemForIndex[index] = id
                claudeRender.textItems.append(id)
            case "thinking":
                claudeRender.itemForIndex[index] = appendItem(DisplayItem(kind: .thought))
            case "tool_use", "server_tool_use":
                // Anything said before a tool call was narration, not the answer.
                markClaudeTextAsCommentary()
                let name = block["name"]?.string ?? ""
                guard name != Tools.todoTool else { break }
                let id = appendItem(DisplayItem(kind: .tool, text: Tools.label(name: name, input: nil)))
                claudeRender.itemForIndex[index] = id
                if let useID = block["id"]?.string { claudeToolItems[useID] = id }
            default:
                if let type = block["type"]?.string, type.hasSuffix("_tool_result"),
                   let useID = block["tool_use_id"]?.string, let item = claudeToolItems[useID] {
                    updateItem(item) { $0.toolState = .done }
                }
            }

        case "content_block_delta":
            guard let id = claudeRender.itemForIndex[index], let delta = event["delta"] else { break }
            switch delta["type"]?.string {
            case "text_delta": updateItem(id) { $0.text += delta["text"]?.string ?? "" }
            case "thinking_delta": updateItem(id) { $0.text += delta["thinking"]?.string ?? "" }
            default: break
            }

        default:
            break
        }
    }

    private func finishClaudeTurn(_ result: JSON) {
        for id in claudeRender.textItems {
            updateItem(id) { if $0.phase == .streaming { $0.phase = .final } }
        }
        record.items.removeAll {
            ($0.kind == .assistant || $0.kind == .thought) && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let isError = result["is_error"]?.bool == true || result["subtype"]?.string != "success"
        if claudeStopRequested {
            notice("Stopped.")
        } else if isError {
            let errors = (result["errors"]?.array ?? []).compactMap(\.string).joined(separator: " ")
            let detail = result["result"]?.string ?? (errors.isEmpty ? result["subtype"]?.string ?? "" : errors)
            notice("Claude Code reported a problem: \(detail)")
        }
        if isError || claudeStopRequested { markRunningToolsFailed() }
        expirePendingApprovals()
        claudeStopRequested = false
        claudeRender = ResponseRender()
        isRunning = false
        record.updatedAt = Date()
        onChange?(self)
    }

    private func claudeProcessExited(status: Int32, detail: String) {
        claudeProcess = nil
        let lower = detail.lowercased()
        if lower.contains("no conversation found") || lower.contains("session") && lower.contains("not found") {
            // The saved session is gone; the next message starts a new one, caught up on the chat.
            record.claudeSessionID = nil
            record.claudeSeenThrough = nil
            notice("Couldn't reopen the earlier Claude Code session. Send your message again to continue in a new one.")
        } else if isRunning || status != 0 {
            notice("Claude Code stopped unexpectedly (exit \(status))\(detail.isEmpty ? "." : ": \(detail)")")
        }
        markRunningToolsFailed()
        expirePendingApprovals()
        isRunning = false
        onChange?(self)
    }

    /// Files Claude writes that can be looked at (a web page, an SVG, an image) appear in the
    /// reply as a live preview, the way Codex's generated images do.
    private func previewWrittenFile(_ useID: String) {
        guard let call = claudeToolCalls.removeValue(forKey: useID),
              ["Write", "Edit", "MultiEdit"].contains(call.name),
              let path = call.input["file_path"]?.string else { return }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard ["html", "htm", "svg", "png", "jpg", "jpeg", "gif", "webp"].contains(ext),
              FileManager.default.fileExists(atPath: path) else { return }
        // An edit to a file already previewed this turn refreshes that preview instead of adding another.
        if let existing = record.items.lastIndex(where: { $0.kind == .image && $0.attachments?.first?.path == path }),
           record.items[existing...].allSatisfy({ $0.kind != .user }) {
            record.items[existing].text = "Updated \(url.lastPathComponent)"
            record.items[existing].attachments = [Attachments.reference(url)]
            return
        }
        appendItem(DisplayItem(kind: .image, text: url.lastPathComponent, attachments: [Attachments.reference(url)]))
    }

    private func markClaudeTextAsCommentary() {
        for id in claudeRender.textItems {
            updateItem(id) { if $0.phase == .streaming { $0.phase = .commentary } }
        }
    }

    private func showPlan(_ steps: [PlanStep]?) {
        guard let steps else { return }
        if let item = claudePlanItem {
            updateItem(item) { $0.planSteps = steps }
        } else {
            claudePlanItem = appendItem(DisplayItem(kind: .plan, planSteps: steps))
        }
    }

    // MARK: - Permission prompts

    /// The card keeps the whole request, so answering it never depends on in-memory state.
    private func showClaudeApproval(id: String, request: JSON) {
        let tool = request["tool_name"]?.string ?? "a tool"
        let input = request["input"] ?? [:]
        let payload: JSON = ["id": .string(id), "tool": .string(tool), "input": input,
                             "suggestions": request["permission_suggestions"] ?? .null]
        if tool == "ExitPlanMode" {
            appendItem(DisplayItem(kind: .approval, text: "Claude has a plan. Start building?",
                                   detail: input["plan"]?.string, requestID: payload, approvalState: .pending,
                                   approvalStyle: .plan))
        } else {
            let (title, detail) = Tools.approval(name: tool, input: input, description: request["description"]?.string)
            appendItem(DisplayItem(kind: .approval, text: title, detail: detail, requestID: payload, approvalState: .pending))
        }
        onChange?(self)
    }

    func claudeResolveApproval(_ itemID: UUID, _ decision: DisplayItem.ApprovalState) {
        guard let item = record.items.first(where: { $0.id == itemID }), item.approvalState == .pending,
              let payload = item.requestID, let id = payload["id"]?.string else { return }
        guard let process = claudeProcess, process.isRunning else {
            updateItem(itemID) { $0.approvalState = .expired }
            notice("That request is no longer active, because Claude Code restarted. Ask again to continue.")
            onChange?(self)
            return
        }
        let tool = payload["tool"]?.string ?? ""
        let input = payload["input"] ?? [:]
        switch decision {
        case .approved, .approvedForSession:
            var response: [String: JSON] = ["behavior": "allow", "updatedInput": input]
            if tool == "ExitPlanMode" {
                // Leaving plan mode: "Start Building" asks before edits, the other accepts them.
                let next = decision == .approvedForSession ? "acceptEdits" : "default"
                response["updatedPermissions"] = [["type": "setMode", "mode": .string(next), "destination": "session"]]
                record.claudeMode = next
            } else if decision == .approvedForSession {
                // Claude Code's own suggestion (e.g. "allow edits this session"), or a rule for this tool.
                if let suggestions = payload["suggestions"], !(suggestions.array ?? []).isEmpty {
                    response["updatedPermissions"] = suggestions
                } else {
                    response["updatedPermissions"] = [["type": "addRules", "rules": [["toolName": .string(tool)]],
                                                       "behavior": "allow", "destination": "session"]]
                }
            }
            process.respond(to: id, .object(response))
        default:
            let message = tool == "ExitPlanMode" ? "The user wants to keep planning. Ask what to change." : "The user declined this."
            process.respond(to: id, ["behavior": "deny", "message": .string(message)])
        }
        updateItem(itemID) { $0.approvalState = decision }
        onChange?(self)
    }
}

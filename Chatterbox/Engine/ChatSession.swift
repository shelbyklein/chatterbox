import Foundation
import Observation

/// Runs one conversation: the agent loop plus the mechanics that make it feel conversational.
///
/// - Commentary vs. final: text Claude writes before a tool call is shown as a dim inline note;
///   only the text that ends a turn is shown as the reply.
/// - Steering: messages sent while a turn is running are folded into that turn at the next
///   model call instead of waiting for it to finish.
/// - Interrupt: stopping keeps what was said and tells the model it was cut off.
/// - Personality: sent as a tagged block only when it changes, so the system prompt stays frozen.
/// - Compaction: near the context limit, history is replaced by a summary.
@MainActor
@Observable
final class ChatSession: Identifiable {
    var record: ConversationRecord
    var isRunning = false

    @ObservationIgnored var onChange: ((ChatSession) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var pendingSteering: [String] = []

    // Codex backend state (see ChatSession+Codex.swift).
    @ObservationIgnored var codexTurnID: String?
    @ObservationIgnored var codexItems: [String: UUID] = [:]
    @ObservationIgnored var codexPlanItems: [String: UUID] = [:]
    @ObservationIgnored var codexTurnMessageItems: [UUID] = []
    @ObservationIgnored var codexStopRequested = false
    @ObservationIgnored private var render = ResponseRender()
    @ObservationIgnored private var toolItemForUseID: [String: UUID] = [:]

    private let compactThreshold = 300_000
    private let maxRounds = 40

    nonisolated let id: UUID
    var items: [DisplayItem] { record.items }
    var title: String { record.title }

    init(record: ConversationRecord) {
        self.id = record.id
        self.record = record
    }

    // MARK: - Public API

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if record.backend == .codex {
            codexSend(text)
            return
        }
        if isRunning {
            pendingSteering.append(text)
            record.items.append(DisplayItem(kind: .user, text: text, steered: true))
            return
        }
        guard let key = Keychain.readAPIKey() else {
            notice("Add your Anthropic API key in Settings (\u{2318},) to start chatting.")
            return
        }
        setTitleIfNeeded(text)
        record.items.append(DisplayItem(kind: .user, text: text))
        isRunning = true
        onChange?(self)
        task = Task { await self.runTurn(userText: text, client: AnthropicClient(apiKey: key)) }
    }

    func interrupt() {
        if record.backend == .codex {
            codexInterrupt()
        } else {
            task?.cancel()
        }
    }

    func setTitleIfNeeded(_ text: String) {
        guard record.title == "New chat" else { return }
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        record.title = firstLine.count > 48 ? String(firstLine.prefix(47)) + "\u{2026}" : firstLine
    }

    /// Only before the first message: histories can't move between backends.
    func setBackend(_ backend: Backend) {
        guard record.items.isEmpty, backend != record.backend else { return }
        if backend == .codex {
            let defaults = UserDefaults.standard
            record.codex = CodexSettings(
                folder: defaults.string(forKey: "codexFolder") ?? NSHomeDirectory(),
                canEdit: defaults.object(forKey: "codexCanEdit") as? Bool ?? false
            )
            record.codex?.model = defaults.string(forKey: "codexDefaultModel").flatMap { $0.isEmpty ? nil : $0 }
            record.codex?.effort = defaults.string(forKey: "codexDefaultEffort").flatMap { $0.isEmpty ? nil : $0 }
        } else {
            record.codex = nil
        }
        onChange?(self)
    }

    func setPersonality(_ personality: Personality) {
        record.personality = personality
        onChange?(self)
    }

    func setWebAccess(_ on: Bool) {
        record.webAccess = on
        onChange?(self)
    }

    func setModel(_ model: String) {
        record.model = model
        record.effort = ClaudeModels.shared.info(model).coerce(effort: record.effort)
        onChange?(self)
    }

    func setEffort(_ effort: String) {
        record.effort = effort
        onChange?(self)
    }

    // MARK: - Turn loop

    private func runTurn(userText: String, client: AnthropicClient) async {
        var planItemID: UUID?
        do {
            if record.lastInputTokens > min(compactThreshold, modelInfo.maxInputTokens * 7 / 10) {
                try await compact(client)
            }
            appendUser(openingBlocks() + [.text(userText)])

            for _ in 0..<maxRounds {
                let msg = try await streamResponse(client)
                record.lastInputTokens = msg.inputTokens
                let endsTurn = ["end_turn", "stop_sequence", "max_tokens", "refusal"].contains(msg.stopReason ?? "end_turn")
                finalizePhases(isFinal: endsTurn && pendingSteering.isEmpty)

                switch msg.stopReason {
                case "tool_use":
                    appendAssistant(msg.content)
                    appendUser(runClientTools(msg, planItemID: &planItemID) + steeringBlocks() + personalityBlocksIfChanged())
                    continue

                case "pause_turn":
                    // The server paused its own tool loop; re-sending resumes it.
                    appendAssistant(msg.content)
                    continue

                case "refusal":
                    appendAssistant([.text("[This reply was declined by Claude's safety system.]")])
                    notice("Claude declined to answer that. Try rephrasing.")
                    return

                case "max_tokens":
                    appendAssistant(msg.content.filter { $0["type"]?.string != "tool_use" })
                    notice("The reply hit the length limit.")
                    return

                default:
                    appendAssistant(msg.content)
                    if pendingSteering.isEmpty { return }
                    // The user steered while the final reply was streaming, so keep going.
                    appendUser(steeringBlocks() + personalityBlocksIfChanged())
                }
            }
            notice("Paused after a lot of steps. Say \u{201C}continue\u{201D} to keep going.")
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                handleInterrupt()
            } else {
                markRunningToolsFailed()
                notice("Something went wrong: \(error.localizedDescription)")
            }
        }
        finishTurn()
    }

    private func finishTurn() {
        // Steering that never reached the model rides along with the next message.
        record.carryover += steeringBlocks()
        isRunning = false
        task = nil
        record.updatedAt = Date()
        onChange?(self)
    }

    private func handleInterrupt() {
        let partial = render.partialText.keys.sorted().compactMap { render.partialText[$0] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !partial.isEmpty {
            appendAssistant(partial.map { JSON.text($0) })
        }
        record.carryover.append(.text("<turn_aborted>The user stopped your previous response partway through. Don't pick it back up unless they ask.</turn_aborted>"))
        finalizePhases(isFinal: true)
        markRunningToolsFailed()
        notice("Stopped.")
    }

    // MARK: - Streaming

    private func streamResponse(_ client: AnthropicClient) async throws -> StreamedMessage {
        var attempt = 0
        while true {
            render = ResponseRender()
            do {
                return try await client.stream(body: requestBody(messages: record.apiMessages), betas: betas) { [weak self] event in
                    self?.handle(event)
                }
            } catch let error as APIError where error.isRetryable && attempt < 2 && render.itemForIndex.isEmpty {
                attempt += 1
                try await Task.sleep(for: .seconds(2 * attempt))
            }
        }
    }

    private var modelInfo: ClaudeModelInfo { ClaudeModels.shared.info(record.model) }

    private var betas: [String] {
        modelInfo.supportsDefaultFallbacks ? ["server-side-fallback-2026-07-01"] : []
    }

    private func requestBody(messages: [JSON]) -> JSON {
        let info = modelInfo
        let maxTokens = min(64_000, info.maxOutputTokens)
        var body: [String: JSON] = [
            "model": .string(record.model),
            "max_tokens": .number(Double(maxTokens)),
            "stream": true,
            "system": .string(Prompts.system),
            "messages": .array(messages),
            "tools": .array(Tools.definitions(webAccess: record.webAccess, basicWebTools: info.usesBasicWebTools)),
            "cache_control": ["type": "ephemeral"],
        ]
        // Adaptive where supported; older models (e.g. Haiku 4.5) take a fixed thinking budget.
        if info.adaptiveThinking {
            body["thinking"] = ["type": "adaptive", "display": "summarized"]
        } else if info.manualThinking {
            body["thinking"] = ["type": "enabled", "budget_tokens": .number(Double(min(16_000, maxTokens / 2)))]
        }
        let effort = info.coerce(effort: record.effort)
        if !effort.isEmpty {
            body["output_config"] = ["effort": .string(effort)]
        }
        if info.supportsDefaultFallbacks {
            body["fallbacks"] = "default"
        }
        return .object(body)
    }

    private func handle(_ event: StreamEvent) {
        switch event {
        case .blockStart(let index, let block):
            let type = block["type"]?.string ?? ""
            switch type {
            case "text":
                let id = appendItem(DisplayItem(kind: .assistant, text: block["text"]?.string ?? "", phase: .streaming))
                render.itemForIndex[index] = id
                render.textItems.append(id)
            case "thinking":
                render.itemForIndex[index] = appendItem(DisplayItem(kind: .thought))
            case "tool_use", "server_tool_use":
                // Anything Claude said before a tool call was narration, not the answer.
                markStreamingTextAsCommentary()
                let name = block["name"]?.string ?? ""
                guard name != "update_plan" else { break }
                let id = appendItem(DisplayItem(kind: .tool, text: Tools.label(name: name, input: nil)))
                render.itemForIndex[index] = id
                if let useID = block["id"]?.string { toolItemForUseID[useID] = id }
            case "fallback":
                let model = block["to"]?["model"]?.string ?? "another model"
                notice("Switched to \(model) for this reply.")
            default:
                if type.hasSuffix("_tool_result"), let useID = block["tool_use_id"]?.string,
                   let id = toolItemForUseID[useID] {
                    let content = block["content"]
                    let failed = content?["error_code"] != nil || content?["type"]?.string?.hasSuffix("error") == true
                    updateItem(id) { $0.toolState = failed ? .failed : .done }
                }
            }

        case .textDelta(let index, let text):
            render.partialText[index, default: ""] += text
            if let id = render.itemForIndex[index] { updateItem(id) { $0.text += text } }

        case .thinkingDelta(let index, let text):
            if let id = render.itemForIndex[index] { updateItem(id) { $0.text += text } }

        case .blockStop(let index, let block):
            let type = block["type"]?.string
            if type == "tool_use" || type == "server_tool_use", let id = render.itemForIndex[index],
               let name = block["name"]?.string {
                updateItem(id) { $0.text = Tools.label(name: name, input: block["input"]) }
            }
        }
    }

    // MARK: - Tools

    private func runClientTools(_ msg: StreamedMessage, planItemID: inout UUID?) -> [JSON] {
        var results: [JSON] = []
        for block in msg.content where block["type"]?.string == "tool_use" {
            guard let useID = block["id"]?.string, let name = block["name"]?.string else { continue }
            let itemID = toolItemForUseID[useID]

            if msg.invalidToolInputs.contains(useID) {
                results.append(toolResult(useID, "INVALID_JSON: the tool input was not valid JSON. Please call the tool again.", isError: true))
                if let itemID { updateItem(itemID) { $0.toolState = .failed } }
                continue
            }

            switch Tools.run(name: name, input: block["input"] ?? [:]) {
            case .text(let output):
                results.append(toolResult(useID, output))
                if let itemID { updateItem(itemID) { $0.toolState = .done } }
            case .plan(let steps, let output):
                if let planItemID {
                    updateItem(planItemID) { $0.planSteps = steps }
                } else {
                    planItemID = appendItem(DisplayItem(kind: .plan, planSteps: steps))
                }
                results.append(toolResult(useID, output))
            case .error(let message):
                results.append(toolResult(useID, message, isError: true))
                if let itemID { updateItem(itemID) { $0.toolState = .failed } }
            }
        }
        return results
    }

    private func toolResult(_ useID: String, _ content: String, isError: Bool = false) -> JSON {
        var block: [String: JSON] = ["type": "tool_result", "tool_use_id": .string(useID), "content": .string(content)]
        if isError { block["is_error"] = true }
        return .object(block)
    }

    // MARK: - Context blocks

    /// Summary, carryover notes, and personality that should precede the user's next message.
    private func openingBlocks() -> [JSON] {
        var blocks: [JSON] = []
        if let summary = record.pendingSummary {
            blocks.append(.text("<conversation_summary>\nEarlier parts of this conversation were summarized to save space. Continue naturally from here without repeating finished work.\n\n\(summary)\n</conversation_summary>"))
            record.pendingSummary = nil
        }
        blocks += record.carryover
        record.carryover = []
        blocks += personalityBlocksIfChanged()
        return blocks
    }

    private func personalityBlocksIfChanged() -> [JSON] {
        guard record.sentPersonality != record.personality else { return [] }
        record.sentPersonality = record.personality
        return [.text(Prompts.personalitySpec(record.personality))]
    }

    private func steeringBlocks() -> [JSON] {
        let texts = pendingSteering
        pendingSteering.removeAll()
        return texts.map {
            .text("<user_steering>\n\($0)\n</user_steering>\nThe user sent this while you were working. Take it into account now, and briefly acknowledge it.")
        }
    }

    // MARK: - Compaction

    private func compact(_ client: AnthropicClient) async throws {
        let itemID = appendItem(DisplayItem(kind: .tool, text: "Summarizing earlier conversation to make room"))
        let instruction = Prompts.compaction + "\n\nWrite the summary now as plain text. Do not call any tools."
        var messages = record.apiMessages
        Self.appendUser(record.carryover + [.text(instruction)], to: &messages)

        do {
            let msg = try await client.stream(body: requestBody(messages: messages), betas: betas) { _ in }
            let summary = msg.content.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined(separator: "\n")
            guard !summary.isEmpty else { throw APIError(status: 0, message: "empty summary") }

            let recent = record.items.filter { $0.kind == .user }.dropLast().suffix(3).map { "> " + $0.text.replacingOccurrences(of: "\n", with: "\n> ") }
            record.pendingSummary = summary + (recent.isEmpty ? "" : "\n\nThe user's most recent messages, verbatim:\n\n" + recent.joined(separator: "\n\n"))
            record.apiMessages = []
            record.carryover = []
            record.sentPersonality = nil
            record.lastInputTokens = 0
            updateItem(itemID) { $0.toolState = .done; $0.text = "Summarized earlier conversation to make room" }
        } catch let error as APIError {
            // Not fatal: the context window is far larger than the threshold.
            updateItem(itemID) { $0.toolState = .failed; $0.text = "Couldn't summarize earlier conversation (\(error.message))" }
        }
    }

    // MARK: - History

    private func appendUser(_ content: [JSON]) {
        Self.appendUser(content, to: &record.apiMessages)
    }

    /// Merges into a trailing user message so the history always alternates roles,
    /// even after an error or interrupt left a user message unanswered.
    private static func appendUser(_ content: [JSON], to messages: inout [JSON]) {
        guard !content.isEmpty else { return }
        if let last = messages.last, last["role"]?.string == "user", let existing = last["content"]?.array {
            messages[messages.count - 1] = .message("user", existing + content)
        } else {
            messages.append(.message("user", content))
        }
    }

    private func appendAssistant(_ content: [JSON]) {
        var blocks = Self.sanitizeForReplay(content)
        if blocks.isEmpty { blocks = [.text("(no response)")] }
        record.apiMessages.append(.message("assistant", blocks))
    }

    /// Applies the replay rules for responses that switched models partway through,
    /// and drops empty text blocks, which the API rejects.
    static func sanitizeForReplay(_ content: [JSON]) -> [JSON] {
        let type = { (block: JSON) in block["type"]?.string ?? "" }
        var blocks = content
        if let boundary = blocks.lastIndex(where: { type($0) == "fallback" }) {
            let resultIDs = Set(blocks.compactMap { type($0).hasSuffix("_tool_result") ? $0["tool_use_id"]?.string : nil })
            blocks = blocks.enumerated().compactMap { index, block in
                guard index < boundary else { return block }
                switch type(block) {
                case "text", "fallback": return block
                case "server_tool_use": return resultIDs.contains(block["id"]?.string ?? "") ? block : nil
                case let t where t.hasSuffix("_tool_result"): return block
                default: return nil
                }
            }
        }
        return blocks.filter { type($0) != "text" || !($0["text"]?.string ?? "").isEmpty }
    }

    // MARK: - Display items

    @discardableResult
    func appendItem(_ item: DisplayItem) -> UUID {
        record.items.append(item)
        return item.id
    }

    func updateItem(_ id: UUID, _ change: (inout DisplayItem) -> Void) {
        guard let index = record.items.lastIndex(where: { $0.id == id }) else { return }
        change(&record.items[index])
    }

    func notice(_ text: String) {
        record.items.append(DisplayItem(kind: .notice, text: text))
    }

    private func markStreamingTextAsCommentary() {
        for id in render.textItems {
            updateItem(id) { if $0.phase == .streaming { $0.phase = .commentary } }
        }
    }

    private func finalizePhases(isFinal: Bool) {
        for id in render.textItems {
            updateItem(id) { if $0.phase == .streaming { $0.phase = isFinal ? .final : .commentary } }
        }
        record.items.removeAll {
            ($0.kind == .assistant || $0.kind == .thought) && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func markRunningToolsFailed() {
        for index in record.items.indices where record.items[index].kind == .tool && record.items[index].toolState == .running {
            record.items[index].toolState = .failed
        }
    }
}

/// Per-response bookkeeping that maps streamed block indexes to transcript rows.
private struct ResponseRender {
    var itemForIndex: [Int: UUID] = [:]
    var textItems: [UUID] = []
    var partialText: [Int: String] = [:]
}

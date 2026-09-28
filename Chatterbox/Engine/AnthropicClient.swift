import Foundation

struct APIError: LocalizedError {
    var status: Int
    var type: String?
    var message: String

    var errorDescription: String? { message }

    /// 408/409/429/5xx and overload errors are worth retrying.
    var isRetryable: Bool {
        status == 408 || status == 409 || status == 429 || status >= 500 || type == "overloaded_error"
    }
}

/// Live events from one streamed response, keyed by content-block index.
enum StreamEvent {
    case blockStart(index: Int, block: JSON)
    case textDelta(index: Int, text: String)
    case thinkingDelta(index: Int, text: String)
    case blockStop(index: Int, block: JSON)
}

struct StreamedMessage {
    var content: [JSON]
    var stopReason: String?
    var usage: [String: JSON] = [:]
    var model: String?
    /// Tool-use blocks whose streamed input could not be parsed as JSON.
    var invalidToolInputs: Set<String> = []

    /// Tokens the request consumed as input, including cached tokens.
    var inputTokens: Int {
        ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .compactMap { usage[$0]?.int }.reduce(0, +)
    }
}

/// Minimal client for POST /v1/messages over raw HTTP with server-sent events.
struct AnthropicClient {
    var apiKey: String
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func stream(body: JSON, betas: [String], onEvent: @MainActor (StreamEvent) -> Void) async throws -> StreamedMessage {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try body.encoded()

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            throw Self.apiError(status: status, data: raw)
        }

        var result = StreamedMessage(content: [])
        var blocks: [Int: [String: JSON]] = [:]
        var partialJSON: [Int: String] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSON.parse(payload), let type = event["type"]?.string else { continue }

            switch type {
            case "message_start":
                result.model = event["message"]?["model"]?.string
                if let usage = event["message"]?["usage"]?.object { result.usage.merge(usage) { _, new in new } }

            case "content_block_start":
                guard let index = event["index"]?.int, let block = event["content_block"]?.object else { break }
                blocks[index] = block
                await onEvent(.blockStart(index: index, block: .object(block)))

            case "content_block_delta":
                guard let index = event["index"]?.int, let delta = event["delta"] else { break }
                switch delta["type"]?.string {
                case "text_delta":
                    let text = delta["text"]?.string ?? ""
                    let existing = blocks[index]?["text"]?.string ?? ""
                    blocks[index]?["text"] = .string(existing + text)
                    await onEvent(.textDelta(index: index, text: text))
                case "thinking_delta":
                    let text = delta["thinking"]?.string ?? ""
                    let existing = blocks[index]?["thinking"]?.string ?? ""
                    blocks[index]?["thinking"] = .string(existing + text)
                    await onEvent(.thinkingDelta(index: index, text: text))
                case "signature_delta":
                    blocks[index]?["signature"] = delta["signature"]
                case "input_json_delta":
                    partialJSON[index, default: ""] += delta["partial_json"]?.string ?? ""
                case "citations_delta":
                    if let citation = delta["citation"] {
                        let existing = blocks[index]?["citations"]?.array ?? []
                        blocks[index]?["citations"] = .array(existing + [citation])
                    }
                default:
                    break
                }

            case "content_block_stop":
                guard let index = event["index"]?.int, var block = blocks[index] else { break }
                if let raw = partialJSON[index] {
                    if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                        block["input"] = .object([:])
                    } else if let input = try? JSON.parse(raw) {
                        block["input"] = input
                    } else if let id = block["id"]?.string {
                        // With eager input streaming the API doesn't validate input; flag it.
                        block["input"] = .object([:])
                        result.invalidToolInputs.insert(id)
                    }
                }
                blocks[index] = block
                await onEvent(.blockStop(index: index, block: .object(block)))

            case "message_delta":
                if let reason = event["delta"]?["stop_reason"]?.string { result.stopReason = reason }
                if let usage = event["usage"]?.object { result.usage.merge(usage) { _, new in new } }

            case "error":
                let err = event["error"]
                throw APIError(status: err?["type"]?.string == "overloaded_error" ? 529 : 500,
                               type: err?["type"]?.string,
                               message: err?["message"]?.string ?? "The stream ended with an error.")

            default:
                break
            }
        }

        result.content = blocks.keys.sorted().compactMap { blocks[$0].map(JSON.object) }
        return result
    }

    private static func apiError(status: Int, data: Data) -> APIError {
        let json = try? JSON.parse(data)
        let message = json?["error"]?["message"]?.string
            ?? String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
            ?? "HTTP \(status)"
        return APIError(status: status, type: json?["error"]?["type"]?.string, message: message)
    }
}

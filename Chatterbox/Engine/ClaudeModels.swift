import Foundation
import Observation

/// The Claude models this API key can use, loaded from GET /v1/models with each model's
/// effort levels and thinking modes, so the pickers never offer something the API rejects.
@MainActor
@Observable
final class ClaudeModels {
    static let shared = ClaudeModels()

    private(set) var models: [ClaudeModelInfo] = []
    private(set) var errorMessage: String?
    @ObservationIgnored private var loading = false

    /// Capabilities for `id`, falling back to conservative guesses if it isn't listed.
    func info(_ id: String) -> ClaudeModelInfo {
        models.first { $0.id == id } ?? .fallback(id)
    }

    func refresh(force: Bool = false) async {
        guard !loading, force || models.isEmpty, let key = Keychain.readAPIKey() else { return }
        loading = true
        defer { loading = false }
        do {
            models = try await AnthropicClient(apiKey: key).listModels()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension AnthropicClient {
    func listModels() async throws -> [ClaudeModelInfo] {
        var result: [ClaudeModelInfo] = []
        var after: String?
        repeat {
            var components = URLComponents(string: "https://api.anthropic.com/v1/models")!
            components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                + (after.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
            var request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = try JSON.parse(data)
            guard status == 200 else {
                throw APIError(status: status, type: json["error"]?["type"]?.string,
                               message: json["error"]?["message"]?.string ?? "HTTP \(status)")
            }
            for m in json["data"]?.array ?? [] {
                guard let id = m["id"]?.string else { continue }
                let caps = m["capabilities"]
                let fallback = ClaudeModelInfo.fallback(id)
                let effort = caps?["effort"]
                // Every level the API marks supported, known ones in order, new ones after.
                let levels = (effort?.object ?? [:]).filter { $0.value["supported"]?.bool == true }.map(\.key)
                let order = ClaudeModelInfo.effortOrder
                let efforts = effort?["supported"]?.bool == true
                    ? order.filter(levels.contains) + levels.filter { !order.contains($0) }.sorted()
                    : []
                let thinking = caps?["thinking"]?["types"]
                result.append(ClaudeModelInfo(
                    id: id,
                    displayName: m["display_name"]?.string ?? id,
                    efforts: caps == nil ? fallback.efforts : efforts,
                    adaptiveThinking: thinking?["adaptive"]?["supported"]?.bool ?? fallback.adaptiveThinking,
                    manualThinking: thinking?["enabled"]?["supported"]?.bool ?? fallback.manualThinking,
                    maxInputTokens: m["max_input_tokens"]?.int ?? fallback.maxInputTokens,
                    maxOutputTokens: m["max_tokens"]?.int ?? fallback.maxOutputTokens
                ))
            }
            after = json["has_more"]?.bool == true ? json["last_id"]?.string : nil
        } while after != nil
        return result
    }
}

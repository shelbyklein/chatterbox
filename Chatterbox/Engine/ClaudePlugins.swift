import Foundation
import Observation

/// Claude Code's plugins, through its own `claude plugin` commands: the catalogs
/// (marketplaces) it knows, every plugin they offer, and what's installed. Chatterbox only
/// runs those commands, so what you do here is the same as doing it in a terminal, and new
/// Claude chats pick it up.
@MainActor
@Observable
final class ClaudePlugins {
    static let shared = ClaudePlugins()

    struct Plugin: Identifiable, Hashable {
        /// "name@marketplace".
        var id: String
        var name: String
        var description: String
        var marketplace: String
        var version: String?
        var installCount: Int?
        /// Where its files come from (a repository or folder), when the catalog says.
        var source: String?
        var installed: Installed?
    }

    struct Installed: Hashable {
        var scope: String
        var enabled: Bool
        var version: String?
    }

    struct Marketplace: Identifiable, Hashable {
        var name: String
        /// "owner/repo", a URL, or a folder.
        var location: String
        var id: String { name }
    }

    /// Catalogs worth knowing about, offered with one click.
    static let suggested: [(source: String, name: String, about: String)] = [
        ("anthropics/claude-plugins-community", "Community",
         "Anthropic's community plugin directory as a GitHub catalog (thousands of third-party plugins). Claude Code's built-in Anthropic Directory already lists most of them."),
    ]

    private(set) var plugins: [Plugin] = []
    private(set) var marketplaces: [Marketplace] = []
    private(set) var isLoading = false
    /// Why the last command didn't work, in the CLI's words.
    var problem: String?
    /// Plugins and catalogs a command is running for right now.
    private(set) var busy: Set<String> = []
    @ObservationIgnored private var loaded = Date.distantPast

    var installedCount: Int { plugins.filter { $0.installed != nil }.count }

    func refreshIfStale() async {
        guard Date().timeIntervalSince(loaded) > 120, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let pluginList = Self.json(["plugin", "list", "--available", "--json"])
        async let catalogList = Self.json(["plugin", "marketplace", "list", "--json"])
        do {
            let (list, catalogs) = try await (pluginList, catalogList)
            plugins = Self.parsePlugins(list)
            marketplaces = Self.parseMarketplaces(catalogs)
            loaded = Date()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// What a plugin contains and its projected token cost, as the CLI words it.
    func details(_ plugin: Plugin) async -> String {
        (try? await Self.run(["plugin", "details", plugin.id]).output) ?? "Couldn't read this plugin's details."
    }

    func install(_ plugin: Plugin) async { await perform(plugin.id, ["plugin", "install", plugin.id, "--scope", "user"]) }
    func uninstall(_ plugin: Plugin) async { await perform(plugin.id, ["plugin", "uninstall", plugin.id]) }
    func update(_ plugin: Plugin) async { await perform(plugin.id, ["plugin", "update", plugin.id]) }
    func setEnabled(_ plugin: Plugin, _ on: Bool) async { await perform(plugin.id, ["plugin", on ? "enable" : "disable", plugin.id]) }

    func addMarketplace(_ source: String) async {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        await perform(source, ["plugin", "marketplace", "add", source])
    }

    func removeMarketplace(_ marketplace: Marketplace) async {
        await perform(marketplace.name, ["plugin", "marketplace", "remove", marketplace.name])
    }

    func updateMarketplaces() async { await perform("marketplaces", ["plugin", "marketplace", "update"]) }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    func hasMarketplace(_ source: String) -> Bool {
        marketplaces.contains { $0.location.caseInsensitiveCompare(source) == .orderedSame }
    }

    private func perform(_ key: String, _ arguments: [String]) async {
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            let result = try await Self.run(arguments)
            if result.status != 0 {
                problem = (result.error.isEmpty ? result.output : result.error).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                problem = nil
            }
        } catch {
            problem = error.localizedDescription
        }
        await refresh()
    }

    // MARK: - Reading the CLI

    private static func parsePlugins(_ object: Any) -> [Plugin] {
        let root = object as? [String: Any] ?? [:]
        var installed: [String: Installed] = [:]
        for entry in root["installed"] as? [[String: Any]] ?? [] {
            guard let id = entry["id"] as? String else { continue }
            installed[id] = Installed(scope: entry["scope"] as? String ?? "user", enabled: entry["enabled"] as? Bool ?? false,
                                      version: entry["version"] as? String)
        }
        var plugins: [Plugin] = []
        var seen: Set<String> = []
        for entry in root["available"] as? [[String: Any]] ?? [] {
            guard let id = entry["pluginId"] as? String, seen.insert(id).inserted else { continue }
            plugins.append(Plugin(id: id, name: entry["name"] as? String ?? id, description: entry["description"] as? String ?? "",
                                  marketplace: entry["marketplaceName"] as? String ?? "", version: entry["version"] as? String,
                                  installCount: entry["installCount"] as? Int, source: Self.source(entry["source"]),
                                  installed: installed[id]))
        }
        // Installed plugins the catalogs no longer list (or list elsewhere) still show.
        for (id, state) in installed where !seen.contains(id) {
            let parts = id.split(separator: "@", maxSplits: 1).map(String.init)
            plugins.append(Plugin(id: id, name: parts.first ?? id, description: "", marketplace: parts.count > 1 ? parts[1] : "",
                                  version: state.version, installed: state))
        }
        return plugins.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func source(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let source = value as? [String: Any] else { return nil }
        if let url = source["url"] as? String {
            let path = (source["path"] as? String).map { " (\($0))" } ?? ""
            return url.replacingOccurrences(of: ".git", with: "") + path
        }
        if let repo = source["repo"] as? String { return "https://github.com/" + repo }
        return source["path"] as? String
    }

    private static func parseMarketplaces(_ object: Any) -> [Marketplace] {
        (object as? [[String: Any]] ?? []).compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let location = entry["repo"] as? String ?? entry["url"] as? String ?? entry["path"] as? String ?? entry["source"] as? String ?? ""
            return Marketplace(name: name, location: location)
        }
    }

    struct CLIError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private static func json(_ arguments: [String]) async throws -> Any {
        let result = try await run(arguments)
        guard result.status == 0, let object = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) else {
            throw CLIError(message: (result.error.isEmpty ? "Claude Code couldn't list plugins." : result.error)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return object
    }

    /// Runs `claude` with these arguments off the main thread, with no input.
    private static func run(_ arguments: [String]) async throws -> (output: String, error: String, status: Int32) {
        guard let claude = ClaudeCodeProcess.locateBinary() else {
            throw CLIError(message: "Claude Code isn't installed, or Chatterbox can't find it (Settings → General).")
        }
        let environment = BinaryLocator.environment
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: claude)
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            // Read both pipes while it runs, so a large listing can't fill one and stall it.
            async let output = out.fileHandleForReading.readToEnd()
            async let error = err.fileHandleForReading.readToEnd()
            let (outData, errData) = try await (output, error)
            process.waitUntilExit()
            return (String(decoding: outData ?? Data(), as: UTF8.self), String(decoding: errData ?? Data(), as: UTF8.self),
                    process.terminationStatus)
        }.value
    }
}

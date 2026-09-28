import Foundation

struct ClaudeCodeError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Finds command-line tools the way a terminal would, since apps launched from Finder
/// get a minimal PATH.
enum BinaryLocator {
    static func find(_ name: String, customPathKey: String) -> String? {
        let fm = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: customPathKey)?.trimmingCharacters(in: .whitespaces),
           !custom.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? custom : nil
        }
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
                          "\(home)/.npm-global/bin/\(name)", "\(home)/.bun/bin/\(name)", "\(home)/.cargo/bin/\(name)",
                          "\(home)/.claude/local/\(name)"]
        if let found = candidates.first(where: fm.isExecutableFile(atPath:)) { return found }

        // Fall back to asking the user's shell, which knows their PATH.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lic", "command -v \(name)"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = Pipe()
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return fm.isExecutableFile(atPath: path) ? path : nil
    }

    /// The app's environment with the usual tool folders added to PATH.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPath = ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extraPath + [env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }
}

/// One `claude` (Claude Code) child process in stream-json mode, owned by one chat.
/// It uses the user's own Claude Code install, settings, and subscription sign-in.
@MainActor
final class ClaudeCodeProcess {
    struct Config {
        var cwd: String
        var model: String
        var effort: String
        var permissionMode: String
        var appendSystemPrompt: String
        var resumeSessionID: String?
        var extraDirectories: [String] = []
    }

    /// Every message the CLI writes, except replies to our own control requests.
    var onMessage: ((JSON) -> Void)?
    /// Called once if the process ends; the text is the last thing it printed to stderr.
    var onExit: ((_ status: Int32, _ detail: String) -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()
    private var stderrTail: [String] = []
    private var pending: [String: CheckedContinuation<JSON, Error>] = [:]

    var isRunning: Bool { process?.isRunning == true }

    static func locateBinary() -> String? { BinaryLocator.find("claude", customPathKey: "claudePath") }

    static func arguments(_ config: Config) -> [String] {
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--include-partial-messages", "--permission-prompt-tool", "stdio",
                    "--model", config.model, "--permission-mode", config.permissionMode,
                    // Only makes "Bypass permissions" selectable later; the mode above still applies.
                    "--allow-dangerously-skip-permissions",
                    "--append-system-prompt", config.appendSystemPrompt,
                    // The chat window has its own ways to ask; this tool would stall the turn.
                    "--disallowed-tools", "AskUserQuestion"]
        if !config.effort.isEmpty { args += ["--effort", config.effort] }
        if let id = config.resumeSessionID { args += ["--resume", id] }
        for dir in config.extraDirectories { args += ["--add-dir", dir] }
        return args
    }

    func start(_ config: Config) throws {
        guard let binary = Self.locateBinary() else {
            throw ClaudeCodeError(message: "Couldn't find the `claude` command. Install Claude Code, or set its path in Settings.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.arguments(config)
        process.currentDirectoryURL = URL(fileURLWithPath: config.cwd)
        process.environment = BinaryLocator.environment

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(data) } }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stderrTail = Array((self.stderrTail + text.split(separator: "\n").map(String.init)).suffix(20))
                }
            }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handleExit(proc) } }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
    }

    func send(_ message: JSON) {
        guard let stdinHandle, var data = try? message.encoded() else { return }
        data.append(0x0A)
        try? stdinHandle.write(contentsOf: data)
    }

    func sendUser(_ content: [JSON]) {
        send(["type": "user", "message": ["role": "user", "content": .array(content)], "parent_tool_use_id": .null, "session_id": ""])
    }

    /// Sends a control request (interrupt, set_model, …) and waits for its reply.
    @discardableResult
    func control(_ subtype: String, _ fields: [String: JSON] = [:]) async throws -> JSON {
        guard isRunning else { throw ClaudeCodeError(message: "Claude Code isn't running.") }
        let id = UUID().uuidString
        var request = fields
        request["subtype"] = .string(subtype)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            send(["type": "control_request", "request_id": .string(id), "request": .object(request)])
        }
    }

    /// Sends a control request right away without waiting for the reply, so it stays in order
    /// with messages sent after it (a model change must land before the next message).
    func controlNow(_ subtype: String, _ fields: [String: JSON] = [:]) {
        guard isRunning else { return }
        var request = fields
        request["subtype"] = .string(subtype)
        send(["type": "control_request", "request_id": .string(UUID().uuidString), "request": .object(request)])
    }

    /// Answers a control request that came from the CLI, such as a permission prompt.
    func respond(to requestID: String, _ response: JSON) {
        send(["type": "control_response", "response": ["subtype": "success", "request_id": .string(requestID), "response": response]])
    }

    func terminate() {
        onExit = nil
        try? stdinHandle?.close()
        process?.terminate()
        process = nil
        stdinHandle = nil
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, let message = try? JSON.parse(line) else { continue }
            if message["type"]?.string == "control_response" {
                guard let id = message["response"]?["request_id"]?.string, let continuation = pending.removeValue(forKey: id) else { continue }
                if message["response"]?["subtype"]?.string == "error" {
                    continuation.resume(throwing: ClaudeCodeError(message: message["response"]?["error"]?.string ?? "Claude Code refused the request."))
                } else {
                    continuation.resume(returning: message["response"]?["response"] ?? .null)
                }
                continue
            }
            onMessage?(message)
        }
    }

    private func handleExit(_ proc: Process) {
        guard proc === process else { return }
        process = nil
        stdinHandle = nil
        let error = ClaudeCodeError(message: "Claude Code stopped.")
        for (_, continuation) in pending { continuation.resume(throwing: error) }
        pending = [:]
        let detail = stderrTail.suffix(3).joined(separator: " ")
        onExit?(proc.terminationStatus, detail)
    }
}

/// What a short-lived `claude` process reports at startup: the models this account can use
/// and who is signed in. Starting up doesn't call the model, so it costs nothing.
struct ClaudeCodeInfo {
    var models: [ClaudeCodeModel]
    var accountEmail: String?
    var plan: String?

    @MainActor
    static func probe() async throws -> ClaudeCodeInfo {
        let process = ClaudeCodeProcess()
        let config = ClaudeCodeProcess.Config(cwd: NSHomeDirectory(), model: "default", effort: "", permissionMode: "default", appendSystemPrompt: "")
        try process.start(config)
        defer { process.terminate() }
        let response = try await withThrowingTaskGroup(of: JSON.self) { group in
            group.addTask { @MainActor in try await process.control("initialize") }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw ClaudeCodeError(message: "Claude Code didn't respond.")
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        let models = (response["models"]?.array ?? []).compactMap { m -> ClaudeCodeModel? in
            guard let value = m["value"]?.string else { return nil }
            return ClaudeCodeModel(
                value: value,
                resolvedModel: m["resolvedModel"]?.string ?? value,
                displayName: m["displayName"]?.string ?? value,
                detail: m["description"]?.string ?? "",
                efforts: m["supportsEffort"]?.bool == true ? (m["supportedEffortLevels"]?.array ?? []).compactMap(\.string) : []
            )
        }
        return ClaudeCodeInfo(models: models, accountEmail: response["account"]?["email"]?.string,
                              plan: response["account"]?["subscriptionType"]?.string)
    }
}

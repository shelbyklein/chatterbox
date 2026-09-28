import Foundation
import Observation

struct CodexError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct CodexModelInfo: Identifiable, Hashable {
    var id: String { model }
    var model: String
    var displayName: String
    var defaultEffort: String
    var efforts: [String]
    /// Hidden from Codex's own default picker, but still usable.
    var hidden: Bool
}

/// One shared `codex app-server` child process, spoken to with JSON-RPC over stdio.
/// It uses the user's own Codex install, config, and ChatGPT sign-in.
@MainActor
@Observable
final class CodexAppServer {
    static let shared = CodexAppServer()

    private(set) var models: [CodexModelInfo] = []
    private(set) var statusMessage: String?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdinHandle: FileHandle?
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var pending: [Int: CheckedContinuation<JSON, Error>] = [:]
    @ObservationIgnored private var threadHandlers: [String: (_ method: String, _ params: JSON, _ requestID: JSON?) -> Void] = [:]
    @ObservationIgnored private var startTask: Task<Void, Error>?
    @ObservationIgnored private var stdoutBuffer = Data()
    @ObservationIgnored private var stderrTail: [String] = []
    /// Threads loaded into the current process. A fresh process must resume a thread before using it.
    @ObservationIgnored private(set) var loadedThreads: Set<String> = []

    // MARK: - Lifecycle

    func ensureStarted() async throws {
        if process?.isRunning == true, startTask == nil { return }
        if let startTask { return try await startTask.value }
        let task = Task { try await self.launch() }
        startTask = task
        defer { startTask = nil }
        try await task.value
    }

    private func launch() async throws {
        guard let binary = Self.locateBinary() else {
            throw CodexError(message: "Couldn't find the `codex` command. Install the Codex CLI, or set its path in Settings.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        let extraPath = ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extraPath + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self.consume(stdout: data) } }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.stderrTail = Array((self.stderrTail + text.split(separator: "\n").map(String.init)).suffix(20))
                }
            }
        }
        process.terminationHandler = { proc in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.handleExit(proc) } }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        loadedThreads = []

        _ = try await rawRequest("initialize", [
            "clientInfo": ["name": "chatterbox", "title": "Chatterbox", "version": "0.1.0"],
            "capabilities": .null,
        ])
        write(["method": "initialized"])
        statusMessage = nil
        Task { try? await self.refreshModels() }
    }

    private func handleExit(_ proc: Process) {
        guard proc === process else { return }
        let detail = stderrTail.last.map { ": \($0)" } ?? ""
        let error = CodexError(message: "Codex stopped unexpectedly (exit \(proc.terminationStatus))\(detail)")
        process = nil
        stdinHandle = nil
        loadedThreads = []
        stdoutBuffer = Data()
        for (_, continuation) in pending { continuation.resume(throwing: error) }
        pending = [:]
        for (_, handler) in threadHandlers { handler("chatterbox/processExited", ["message": .string(error.message)], nil) }
        statusMessage = error.message
    }

    static func locateBinary() -> String? {
        let fm = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: "codexPath")?.trimmingCharacters(in: .whitespaces),
           !custom.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? custom : nil
        }
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          "\(home)/.npm-global/bin/codex", "\(home)/.bun/bin/codex", "\(home)/.cargo/bin/codex"]
        if let found = candidates.first(where: fm.isExecutableFile(atPath:)) { return found }

        // Fall back to asking the user's shell, which knows their PATH.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lic", "command -v codex"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = Pipe()
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return fm.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: - Messaging

    func request(_ method: String, _ params: JSON) async throws -> JSON {
        try await ensureStarted()
        return try await rawRequest(method, params)
    }

    private func rawRequest(_ method: String, _ params: JSON) async throws -> JSON {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            write(["id": .number(Double(id)), "method": .string(method), "params": params])
        }
    }

    func respond(to requestID: JSON, result: JSON) {
        write(["id": requestID, "result": result])
    }

    func respondError(to requestID: JSON, message: String) {
        write(["id": requestID, "error": ["code": -32601, "message": .string(message)]])
    }

    func register(thread: String, handler: @escaping (_ method: String, _ params: JSON, _ requestID: JSON?) -> Void) {
        threadHandlers[thread] = handler
    }

    func markLoaded(_ thread: String) {
        loadedThreads.insert(thread)
    }

    func refreshModels() async throws {
        var all: [CodexModelInfo] = []
        var cursor: String?
        repeat {
            var params: [String: JSON] = ["includeHidden": true]
            if let cursor { params["cursor"] = .string(cursor) }
            let result = try await request("model/list", .object(params))
            all += (result["data"]?.array ?? []).compactMap { m in
                guard let model = m["model"]?.string else { return nil }
                return CodexModelInfo(
                    model: model,
                    displayName: m["displayName"]?.string ?? model,
                    defaultEffort: m["defaultReasoningEffort"]?.string ?? "medium",
                    efforts: (m["supportedReasoningEfforts"]?.array ?? []).compactMap { $0["reasoningEffort"]?.string },
                    hidden: m["hidden"]?.bool ?? false
                )
            }
            cursor = result["nextCursor"]?.string
        } while cursor != nil
        models = all
    }

    private func write(_ message: JSON) {
        guard let stdinHandle, var data = try? message.encoded() else { return }
        data.append(0x0A)
        try? stdinHandle.write(contentsOf: data)
    }

    private func consume(stdout data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newline)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            guard !line.isEmpty, let message = try? JSON.parse(line) else { continue }
            dispatch(message)
        }
    }

    private func dispatch(_ message: JSON) {
        let method = message["method"]?.string
        let id = message["id"]

        // Response to one of our requests.
        if method == nil, let id = id?.int {
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if let error = message["error"] {
                continuation.resume(throwing: CodexError(message: error["message"]?.string ?? "Codex returned an error."))
            } else {
                continuation.resume(returning: message["result"] ?? .null)
            }
            return
        }
        guard let method else { return }
        let params = message["params"] ?? .null

        // Notification or server request aimed at a thread.
        if let thread = params["threadId"]?.string, let handler = threadHandlers[thread] {
            handler(method, params, id)
            return
        }
        // Server requests we can't route must still be answered so Codex doesn't hang.
        if let id {
            respondError(to: id, message: "Chatterbox doesn't support \(method) yet.")
        }
    }
}

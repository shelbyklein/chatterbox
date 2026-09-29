import Foundation

/// One agent process the host runs for the app, and the log of everything it printed.
///
/// Stdout is appended to `logs/<id>.jsonl` line by line. Offsets are logical byte positions
/// in that stream: when the log's head is trimmed, `base` says where the file now starts, so
/// an offset the app saved stays valid.
final class Child {
    struct Meta: Codable {
        var id: String
        var kind: String?
        var base: Int
        var running: Bool
        var status: Int32?
        var stderr: String?
    }

    let id: String
    /// "claude" or "codex": lets the host tell when the agent is busy or waiting on you.
    let kind: String?
    private let queue: DispatchQueue
    private let logURL: URL
    private let metaURL: URL

    private(set) var pid: pid_t = 0
    private(set) var base = 0
    private(set) var end = 0
    /// nil while running.
    private(set) var status: Int32?
    private(set) var stderrText = ""
    private var acked = 0

    private var stdin: OutputBuffer?
    private var stdinFD: Int32 = -1
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private var partial = Data()
    private var stderrTail: [String] = []
    private var logHandle: FileHandle?
    private var exitCode: Int32?
    private var stdoutOpen = false
    private var exitDeadline: DispatchWorkItem?

    /// Clients attached live to this child's output.
    var subscribers: Set<ObjectIdentifier> = []
    /// Remove the log once the process ends (it was killed on purpose).
    var forgetOnExit = false
    /// Claude: a message was sent and its `result` hasn't come yet.
    private(set) var claudeBusy = false
    /// Codex: turns in progress, by thread.
    private(set) var codexTurns: Set<String> = []
    /// When the child last became idle with no one attached, for closing it later.
    var detachedIdleSince: Date?
    var stdinClosed: Bool { stdinFD < 0 }

    /// New output lines, with their end offsets, for the host to fan out.
    var onLines: (([(start: Int, end: Int, line: Data)]) -> Void)?
    var onExit: (() -> Void)?

    var isRunning: Bool { status == nil }
    var isBusy: Bool { claudeBusy || !codexTurns.isEmpty }

    init(id: String, kind: String?, queue: DispatchQueue, directory: URL) {
        self.id = id
        self.kind = kind
        self.queue = queue
        let name = Child.fileName(id)
        logURL = directory.appendingPathComponent("\(name).jsonl")
        metaURL = directory.appendingPathComponent("\(name).meta.json")
    }

    static func fileName(_ id: String) -> String {
        String(id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character($0) : "_" })
    }

    /// A child from an earlier host run: only its log is left.
    static func restored(from metaURL: URL, queue: DispatchQueue) -> Child? {
        guard let data = try? Data(contentsOf: metaURL), let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
        let child = Child(id: meta.id, kind: meta.kind, queue: queue, directory: metaURL.deletingLastPathComponent())
        child.base = meta.base
        let size = (try? FileManager.default.attributesOfItem(atPath: child.logURL.path)[.size] as? Int) ?? 0
        child.end = meta.base + size
        child.acked = meta.base
        if meta.running {
            child.status = -1
            child.stderrText = "Chatterbox's background host stopped before this finished."
        } else {
            child.status = meta.status ?? -1
            child.stderrText = meta.stderr ?? ""
        }
        child.writeMeta()
        return child
    }

    // MARK: - Running

    func spawn(executable: String, arguments: [String], cwd: String?, environment: [String: String]) throws {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try FileHandle(forWritingTo: logURL)

        var inPipe: [Int32] = [0, 0], outPipe: [Int32] = [0, 0], errPipe: [Int32] = [0, 0]
        guard pipe(&inPipe) == 0, pipe(&outPipe) == 0, pipe(&errPipe) == 0 else { throw HostError("Couldn't create pipes.") }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        if let cwd { posix_spawn_file_actions_addchdir_np(&actions, cwd) }

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        // Only stdio is inherited, so a child never holds another child's pipes open. The host
        // ignores SIGPIPE and SIGHUP; the agents get the usual defaults back.
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        sigaddset(&defaults, SIGHUP)
        posix_spawnattr_setsigdefault(&attrs, &defaults)
        // Spawning happens on a dispatch thread, which blocks signals; a child inherits that
        // mask unless told otherwise. Codex then never saw SIGCHLD, so it never learned its
        // commands had finished. Children start with nothing blocked.
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        posix_spawnattr_setsigmask(&attrs, &unblocked)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attrs, argv, envp)
        close(inPipe[0]); close(outPipe[1]); close(errPipe[1])
        guard result == 0 else {
            close(inPipe[1]); close(outPipe[0]); close(errPipe[0])
            throw HostError("Couldn't start \(executable): \(String(cString: strerror(result)))")
        }
        self.pid = pid
        stdinFD = inPipe[1]
        stdin = OutputBuffer(fd: inPipe[1], queue: queue)
        stdin?.onFailure = { [weak self] in self?.closeStdin() }
        stdoutOpen = true
        stdoutSource = readSource(outPipe[0]) { [weak self] data in self?.consumeStdout(data) }
        stderrSource = readSource(errPipe[0]) { [weak self] data in self?.consumeStderr(data) }
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        exitSource.setEventHandler { [weak self] in self?.reap() }
        exitSource.resume()
        self.exitSource = exitSource
        writeMeta()
    }

    /// A child that never started still gets a log entry, so the app hears why.
    func failedToStart(_ message: String) {
        status = -1
        stderrText = message
        writeMeta()
    }

    func write(_ data: Data) {
        guard isRunning, let stdin else { return }
        if kind == "claude", (try? JSON.parse(data))?["type"]?.string == "user" { claudeBusy = true }
        var line = data
        line.append(0x0A)
        stdin.write(line)
    }

    /// Lets the agent finish on its own: both CLIs exit when stdin ends.
    func closeStdin() {
        guard stdinFD >= 0 else { return }
        stdin?.cancel()
        stdin = nil
        close(stdinFD)
        stdinFD = -1
    }

    func kill() {
        guard isRunning, pid > 0 else { return }
        closeStdin()
        Darwin.kill(pid, SIGTERM)
        let pid = self.pid
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.isRunning == true { Darwin.kill(pid, SIGKILL) }
        }
    }

    private func readSource(_ fd: Int32, _ handler: @escaping (Data?) -> Void) -> DispatchSourceRead {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        var buffer = [UInt8](repeating: 0, count: 65536)
        source.setEventHandler {
            var chunk = Data()
            while true {
                let n = read(fd, &buffer, buffer.count)
                if n > 0 { chunk.append(buffer, count: n); continue }
                if n < 0, errno == EAGAIN || errno == EINTR { break }
                // End of stream (or an error, treated the same).
                if !chunk.isEmpty { handler(chunk) }
                handler(nil)
                source.cancel()
                return
            }
            if !chunk.isEmpty { handler(chunk) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    // MARK: - Output

    private func consumeStdout(_ data: Data?) {
        guard let data else {
            // A last line without a newline still counts.
            if !partial.isEmpty { appendLines(partial + Data([0x0A])) }
            partial = Data()
            stdoutOpen = false
            finishIfDone()
            return
        }
        var chunk = partial
        chunk.append(data)
        guard let lastNewline = chunk.lastIndex(of: 0x0A) else {
            partial = chunk
            return
        }
        partial = chunk.subdata(in: chunk.index(after: lastNewline)..<chunk.endIndex)
        appendLines(chunk.subdata(in: chunk.startIndex..<chunk.index(after: lastNewline)))
    }

    /// `bytes` is one or more whole lines, each ending in a newline.
    private func appendLines(_ bytes: Data) {
        try? logHandle?.write(contentsOf: bytes)
        var lines: [(start: Int, end: Int, line: Data)] = []
        var cursor = bytes.startIndex
        var offset = end
        while let newline = bytes[cursor...].firstIndex(of: 0x0A) {
            let line = bytes.subdata(in: cursor..<newline)
            let length = newline - cursor + 1
            lines.append((offset, offset + length, line))
            offset += length
            cursor = bytes.index(after: newline)
            inspect(line)
        }
        end = offset
        onLines?(lines)
    }

    private func consumeStderr(_ data: Data?) {
        guard let data else { return }
        let text = String(decoding: data, as: UTF8.self)
        stderrTail = Array((stderrTail + text.split(separator: "\n").map(String.init)).suffix(20))
    }

    /// Keeps track of whether the agent is working, and reports requests that wait on you.
    private func inspect(_ line: Data) {
        switch kind {
        case "claude":
            if line.range(of: Data("\"result\"".utf8)) != nil, let message = try? JSON.parse(line), message["type"]?.string == "result" {
                if (message["queued_turn_count"]?.int ?? 0) == 0 { claudeBusy = false }
            }
            if line.range(of: Data("can_use_tool".utf8)) != nil, let message = try? JSON.parse(line),
               message["type"]?.string == "control_request", message["request"]?["subtype"]?.string == "can_use_tool" {
                onWaitingForUser?(Child.claudeRequestSummary(message["request"] ?? .null))
            }
        case "codex":
            guard line.range(of: Data("\"method\"".utf8)) != nil, let message = try? JSON.parse(line),
                  let method = message["method"]?.string else { return }
            let thread = message["params"]?["threadId"]?.string ?? ""
            switch method {
            case "turn/started": codexTurns.insert(thread)
            case "turn/completed": codexTurns.remove(thread)
            case "item/commandExecution/requestApproval":
                onWaitingForUser?("Codex wants to run " + (message["params"]?["command"]?.string.map { "`\($0)`" } ?? "a command"))
            case "item/fileChange/requestApproval":
                onWaitingForUser?("Codex wants to change files")
            case "item/tool/requestUserInput":
                onWaitingForUser?("Codex has a question for you")
            default: break
            }
        default:
            break
        }
    }

    /// A request is waiting on you; the text says what for.
    var onWaitingForUser: ((String) -> Void)?

    private static func claudeRequestSummary(_ request: JSON) -> String {
        switch request["tool_name"]?.string {
        case "AskUserQuestion": return "Claude has a question for you"
        case "ExitPlanMode": return "Claude has a plan ready"
        case let tool?: return "Claude wants to use \(tool)"
        case nil: return "Claude is waiting for you"
        }
    }

    // MARK: - Exit

    private func reap() {
        var raw: Int32 = 0
        guard waitpid(pid, &raw, WNOHANG) == pid else { return }
        exitSource?.cancel()
        exitSource = nil
        // Exit code, or the signal number when a signal ended it (as Foundation's Process reports).
        exitCode = raw & 0x7f == 0 ? (raw >> 8) & 0xff : raw & 0x7f
        // Output still in the pipe comes first; a grandchild holding the pipe open can't stall us.
        let deadline = DispatchWorkItem { [weak self] in
            self?.stdoutOpen = false
            self?.finishIfDone()
        }
        exitDeadline = deadline
        queue.asyncAfter(deadline: .now() + 2, execute: deadline)
        finishIfDone()
    }

    private func finishIfDone() {
        guard let exitCode, !stdoutOpen, status == nil else { return }
        exitDeadline?.cancel()
        if !partial.isEmpty {
            appendLines(partial + Data([0x0A]))
            partial = Data()
        }
        stdoutSource?.cancel()
        stderrSource?.cancel()
        closeStdin()
        try? logHandle?.close()
        logHandle = nil
        status = exitCode
        stderrText = stderrTail.suffix(3).joined(separator: " ")
        claudeBusy = false
        codexTurns = []
        writeMeta()
        onExit?()
    }

    // MARK: - Log

    /// Every line from `offset` on that's still in the log.
    func lines(from offset: Int) -> [(start: Int, end: Int, line: Data)] {
        let from = max(offset, base)
        guard from < end, let handle = try? FileHandle(forReadingFrom: logURL) else { return [] }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(from - base))
        guard let data = try? handle.readToEnd() else { return [] }
        var lines: [(start: Int, end: Int, line: Data)] = []
        var cursor = data.startIndex
        var position = from
        while let newline = data[cursor...].firstIndex(of: 0x0A) {
            let length = newline - cursor + 1
            lines.append((position, position + length, data.subdata(in: cursor..<newline)))
            position += length
            cursor = data.index(after: newline)
        }
        return lines
    }

    /// The app has saved everything up to `offset`. A log past `limit` drops what's acknowledged.
    func acknowledge(_ offset: Int, limit: Int) {
        acked = max(acked, min(offset, end))
        guard end - base > limit, acked > base else { return }
        compact(to: acked)
    }

    private func compact(to newBase: Int) {
        guard newBase > base, newBase <= end else { return }
        let keep = lines(from: newBase)
        let tmp = logURL.appendingPathExtension("tmp")
        var data = Data()
        for line in keep {
            data.append(line.line)
            data.append(0x0A)
        }
        guard (try? data.write(to: tmp)) != nil else { return }
        try? logHandle?.close()
        _ = try? FileManager.default.replaceItemAt(logURL, withItemAt: tmp)
        if isRunning {
            logHandle = try? FileHandle(forWritingTo: logURL)
            _ = try? logHandle?.seekToEnd()
        }
        base = keep.first?.start ?? end
        writeMeta()
    }

    func removeFiles() {
        try? logHandle?.close()
        logHandle = nil
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    private func writeMeta() {
        let meta = Meta(id: id, kind: kind, base: base, running: isRunning, status: status, stderr: isRunning ? nil : stderrText)
        try? JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
    }
}

struct HostError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

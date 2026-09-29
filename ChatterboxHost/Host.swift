import Foundation

/// Keeps agent processes alive for Chatterbox, like tmux for JSON streams. The app connects
/// over a Unix socket, starts processes here instead of as its own children, and reads their
/// output back from a log, so a reply keeps going (and is caught up on) after the app quits.
///
/// Everything runs on one serial queue; no state is shared across threads.
final class Host {
    private let queue = DispatchQueue(label: "chatterbox.host")
    private let directory: URL
    private let logs: URL
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var children: [String: Child] = [:]
    private var idleSince: Date?
    private var lastNotice: [String: Date] = [:]

    /// With no processes and no app connected for this long, the host exits.
    private let idleTimeout = Host.seconds("CHATTERBOX_HOST_IDLE_SECONDS", default: 60)
    /// An agent with nothing to do and no app attached is let go after this long.
    private let detachedIdleTimeout = Host.seconds("CHATTERBOX_HOST_DETACHED_IDLE_SECONDS", default: 30)
    /// Logs are trimmed to what the app has saved once they pass this size.
    private let logLimit = Int(Host.seconds("CHATTERBOX_HOST_LOG_LIMIT", default: Double(32 << 20)))
    private let notificationsEnabled = ProcessInfo.processInfo.environment["CHATTERBOX_HOST_NOTIFY"] != "0"

    init(directory: URL) {
        self.directory = directory
        self.logs = directory.appendingPathComponent("logs", isDirectory: true)
    }

    static func seconds(_ key: String, default value: Double) -> Double {
        ProcessInfo.processInfo.environment[key].flatMap(Double.init) ?? value
    }

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)

        // One host per folder: the lock is held for the host's lifetime.
        let lockFD = open(directory.appendingPathComponent("host.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            log("another host is running; exiting")
            exit(0)
        }

        queue.sync {
            for file in (try? fm.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)) ?? []
            where file.lastPathComponent.hasSuffix(".meta.json") {
                if let child = Child.restored(from: file, queue: queue) { children[child.id] = child }
            }
        }

        guard let fd = UnixSocket.listen(at: directory.appendingPathComponent(HostPaths.socketName)) else {
            log("couldn't listen on \(directory.path)/\(HostPaths.socketName): \(String(cString: strerror(errno)))")
            exit(1)
        }
        listenFD = fd
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.resume()
        acceptSource = source

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        idleTimer = timer
        log("listening in \(directory.path) (pid \(getpid()))")
    }

    private var idleTimer: DispatchSourceTimer?

    // MARK: - Clients

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            // Only the same user may drive the host.
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let client = Client(fd: fd, queue: queue)
            client.onFrame = { [weak self, weak client] header in
                guard let self, let client else { return }
                self.handle(header, from: client)
            }
            client.onClose = { [weak self, weak client] in
                guard let self, let client else { return }
                self.disconnect(client)
            }
            clients[ObjectIdentifier(client)] = client
            client.start()
        }
    }

    private func disconnect(_ client: Client) {
        let key = ObjectIdentifier(client)
        for child in children.values { child.subscribers.remove(key) }
        clients.removeValue(forKey: key)
        client.close()
    }

    private func handle(_ request: JSON, from client: Client) {
        let id = request["id"]?.string ?? ""
        switch request["op"]?.string {
        case "spawn":
            spawn(request, from: client)
        case "attach":
            attach(client, to: id, from: request["from"]?.int ?? 0)
        case "detach":
            children[id]?.subscribers.remove(ObjectIdentifier(client))
        case "write":
            if let text = request["data"]?.string { children[id]?.write(Data(text.utf8)) }
        case "kill":
            guard let child = children[id] else { return }
            if request["forget"]?.bool == true { child.forgetOnExit = true }
            if child.isRunning { child.kill() } else if child.forgetOnExit { forget(child) }
        case "forget":
            if let child = children[id], !child.isRunning { forget(child) }
        case "ack":
            children[id]?.acknowledge(request["offset"]?.int ?? 0, limit: logLimit)
        case "list":
            let processes: [JSON] = children.values.sorted { $0.id < $1.id }.map { child in
                var entry: [String: JSON] = ["id": .string(child.id), "running": .bool(child.isRunning),
                                             "end": .number(Double(child.end)), "busy": .bool(child.isBusy)]
                if let status = child.status { entry["status"] = .number(Double(status)) }
                return .object(entry)
            }
            client.send(["op": "list", "req": request["req"] ?? .null, "processes": .array(processes)])
        default:
            client.send(["op": "error", "message": .string("Unknown request.")])
        }
    }

    private func spawn(_ request: JSON, from client: Client) {
        guard let id = request["id"]?.string, !id.isEmpty, let executable = request["executable"]?.string else {
            client.send(["op": "error", "message": "spawn needs an id and an executable."])
            return
        }
        if let existing = children[id], existing.isRunning {
            client.send(["op": "spawned", "id": .string(id), "existed": true])
            return
        }
        children[id]?.removeFiles()
        let child = Child(id: id, kind: request["protocol"]?.string, queue: queue, directory: logs)
        wire(child)
        children[id] = child
        var env = (request["env"]?.object ?? [:]).compactMapValues(\.string)
        if env.isEmpty { env = ProcessInfo.processInfo.environment }
        let extraPath = ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if env["PATH"] == nil { env["PATH"] = extraPath.joined(separator: ":") }
        do {
            try child.spawn(executable: executable, arguments: (request["args"]?.array ?? []).compactMap(\.string),
                            cwd: request["cwd"]?.string, environment: env)
            log("spawned \(id) (pid \(child.pid))")
            client.send(["op": "spawned", "id": .string(id), "existed": false])
        } catch {
            child.failedToStart(error.localizedDescription)
            log("couldn't spawn \(id): \(error.localizedDescription)")
            client.send(["op": "spawned", "id": .string(id), "existed": false, "error": .string(error.localizedDescription)])
        }
    }

    private func wire(_ child: Child) {
        child.onLines = { [weak self, weak child] lines in
            guard let self, let child else { return }
            for key in child.subscribers {
                guard let client = self.clients[key] else { continue }
                for line in lines { client.sendLine(id: child.id, start: line.start, end: line.end, line.line) }
            }
        }
        child.onExit = { [weak self, weak child] in
            guard let self, let child else { return }
            self.log("\(child.id) exited (\(child.status ?? -1))")
            for key in child.subscribers { self.clients[key]?.sendExit(child) }
            child.subscribers = []
            if child.forgetOnExit { self.forget(child) }
        }
        child.onWaitingForUser = { [weak self, weak child] summary in
            guard let self, let child, child.subscribers.isEmpty else { return }
            self.notify(summary, key: child.id)
        }
    }

    private func attach(_ client: Client, to id: String, from offset: Int) {
        guard let child = children[id] else {
            client.send(["op": "exit", "id": .string(id), "status": -1, "unknown": true,
                         "stderr": "That process is gone."])
            return
        }
        // Catch-up and going live happen in one step on the queue, so nothing is missed or repeated.
        for line in child.lines(from: offset) { client.sendLine(id: id, start: line.start, end: line.end, line.line) }
        if child.isRunning {
            child.subscribers.insert(ObjectIdentifier(client))
            child.detachedIdleSince = nil
        } else {
            client.sendExit(child)
        }
    }

    private func forget(_ child: Child) {
        child.removeFiles()
        if children[child.id] === child { children.removeValue(forKey: child.id) }
    }

    // MARK: - Lifetime

    private func tick() {
        let now = Date()
        // An agent that's done and has no app watching is told to finish (stdin closes).
        for child in children.values where child.isRunning && child.kind != nil && !child.stdinClosed {
            guard child.subscribers.isEmpty, !child.isBusy else {
                child.detachedIdleSince = nil
                continue
            }
            let since = child.detachedIdleSince ?? now
            child.detachedIdleSince = since
            if now.timeIntervalSince(since) >= detachedIdleTimeout {
                log("\(child.id) is idle with no app attached; closing its input")
                child.closeStdin()
                // Codex's app-server may keep running after stdin ends.
                if child.kind == "codex" {
                    queue.asyncAfter(deadline: .now() + 5) { if child.isRunning { child.kill() } }
                }
            }
        }

        let active = !clients.isEmpty || children.values.contains { $0.isRunning }
        if active {
            idleSince = nil
            return
        }
        let since = idleSince ?? now
        idleSince = since
        if now.timeIntervalSince(since) >= idleTimeout {
            log("idle; exiting")
            unlink(directory.appendingPathComponent(HostPaths.socketName).path)
            exit(0)
        }
    }

    // MARK: - Notifications

    /// Tells you an agent is waiting while Chatterbox is closed. A command-line tool has no
    /// notification identity of its own, so this goes through `osascript`.
    private func notify(_ text: String, key: String) {
        let now = Date()
        if let last = lastNotice[key], now.timeIntervalSince(last) < 20 { return }
        lastNotice[key] = now
        log("notify: \(text)")
        guard notificationsEnabled else { return }
        let escaped = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let script = "display notification \"\(escaped(text)). Open Chatterbox to answer.\" with title \"Chatterbox\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

/// One connected app (or test harness).
final class Client {
    private let fd: Int32
    private let out: OutputBuffer
    private var reader = HostFrameReader()
    private var source: DispatchSourceRead?
    private var closed = false
    var onFrame: ((JSON) -> Void)?
    var onClose: (() -> Void)?

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        out = OutputBuffer(fd: fd, queue: queue)
        out.onFailure = { [weak self] in self?.onClose?() }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        self.source = source
    }

    func start() { source?.resume() }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        var chunk = Data()
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { chunk.append(buffer, count: n); continue }
            if n < 0, errno == EAGAIN || errno == EINTR { break }
            if !chunk.isEmpty { deliver(chunk) }
            onClose?()
            return
        }
        deliver(chunk)
    }

    private func deliver(_ chunk: Data) {
        for frame in reader.feed(chunk) {
            guard !closed else { return }
            onFrame?(frame.header)
        }
    }

    func send(_ header: JSON) {
        out.write(HostWire.frame(header))
    }

    func sendLine(id: String, start: Int, end: Int, _ line: Data) {
        out.write(HostWire.frame(["op": "line", "id": .string(id), "offset": .number(Double(start)), "end": .number(Double(end))], raw: line))
    }

    func sendExit(_ child: Child) {
        send(["op": "exit", "id": .string(child.id), "status": .number(Double(child.status ?? -1)),
              "stderr": .string(child.stderrText)])
    }

    func close() {
        guard !closed else { return }
        closed = true
        out.cancel()
        source?.cancel()
        source = nil
        Darwin.close(fd)
    }
}

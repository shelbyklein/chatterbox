import Foundation
import Darwin

// The service's main thread while a very long session streams (scripts/test-service-responsiveness.sh).
// Seeds 423 ordinary sessions and one of BENCH_ROWS rows, saves a few secrets so redaction is on,
// then streams into the long session the way a reply does while a background thread asks what
// the phone and the Mac ask: GET /v1/chats, GET /v1/chats/<long>, and the socket's list.
// Prints each save's main-thread time, the main thread's worst stall, and each request's latency.

let env = ProcessInfo.processInfo.environment
let rows = Int(env["BENCH_ROWS"] ?? "") ?? 20_000
let seconds = Double(env["BENCH_SECONDS"] ?? "") ?? 8
let label = env["BENCH_LABEL"] ?? "run"
let others = 423
let port = env["CHATTERBOX_COMPANION_PORT"] ?? "19661"

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
func ms(_ s: Double) -> String { String(format: "%.1f ms", s * 1000) }
func stats(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "none" }
    let sorted = values.sorted()
    func at(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
    return "n=\(sorted.count) median \(ms(at(0.5))) p95 \(ms(at(0.95))) max \(ms(sorted.last!))"
}
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL \(message)"); exit(1) }
    print("PASS \(message)")
}

// Varied prose with some non-ASCII, like real replies.
let words = ["the", "service", "keeps", "answering", "while", "a", "long", "reply", "streams", "—", "café", "naïve",
             "résumé", "📎", "build", "folder", "Swift", "function", "returns", "request", "phone", "Mac", "quickly"]
var generator = SystemRandomNumberGenerator()
func prose(_ count: Int) -> String {
    (0..<count).map { _ in words.randomElement(using: &generator)! }.joined(separator: " ")
}

func seed() throws {
    let folder = RuntimePaths.data.appendingPathComponent("Conversations")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    func record(_ index: Int, rows: Int) -> ConversationRecord {
        var r = ConversationRecord(model: "default", effort: "", personality: .neutral)
        r.title = "Fixture session \(index)"
        if index % 3 == 0 { r.projectFolder = "/tmp/bench-project-\(index)" }
        r.updatedAt = Date().addingTimeInterval(-Double(index) * 60)
        for row in 0..<rows {
            switch row % 5 {
            case 0: r.items.append(DisplayItem(kind: .user, text: prose(20)))
            case 1: r.items.append(DisplayItem(kind: .tool, text: "Ran `ls -la` " + prose(10), toolState: .done, detail: prose(40)))
            case 2: r.items.append(DisplayItem(kind: .thought, text: prose(30)))
            default: r.items.append(DisplayItem(kind: .assistant, text: prose(Int.random(in: 20...300))))
            }
        }
        return r
    }
    for index in 1...others {
        try encoder.encode(record(index, rows: Int.random(in: 20...200))).write(to: folder.appendingPathComponent("\(UUID().uuidString).json"))
    }
    var long = record(0, rows: rows)
    long.title = "The long session"
    long.updatedAt = Date()
    try encoder.encode(long).write(to: folder.appendingPathComponent("\(long.id.uuidString).json"))
}

/// One request on the daemon socket (a fresh connection each time, as `work list` makes).
func socketRequest(_ path: String, _ operation: String, _ body: [String: Any]) -> Double? {
    let start = now()
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, path, 103) } }
    let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard connected == 0 else { return nil }
    var timeout = timeval(tv_sec: 30, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var buffer = Data()
    func send(_ id: String, _ operation: String, _ body: [String: Any]) -> Bool {
        var line = try! JSONSerialization.data(withJSONObject: ["version": 1, "id": id, "operation": operation, "body": body])
        line.append(10)
        guard line.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == line.count else { return false }
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        var scanned = 0
        while true {
            while let newline = buffer[(buffer.startIndex + scanned)...].firstIndex(of: 10) {
                let reply = buffer.subdata(in: buffer.startIndex..<newline); buffer.removeSubrange(buffer.startIndex...newline)
                scanned = 0
                // Only the reply's head: its id and error come before the result.
                let head = String(decoding: reply.prefix(200), as: UTF8.self)
                if head.contains("\"id\":\"\(id)\"") { return !head.contains("\"error\"") }
                if !head.hasPrefix("{\"id\""), let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any], object["id"] as? String == id {
                    return object["error"] == nil
                }
            }
            scanned = buffer.count
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return false }
            buffer.append(contentsOf: chunk.prefix(n))
        }
    }
    guard send("hello-\(UUID())", "hello", ["role": "agent"]), send(UUID().uuidString, operation, body) else { return nil }
    return now() - start
}

func http(_ path: String, token: String) -> Double? {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.setValue(token, forHTTPHeaderField: Companion.tokenHeader)
    request.timeoutInterval = 30
    let done = DispatchSemaphore(value: 0)
    var ok = false
    let start = now()
    URLSession.shared.dataTask(with: request) { _, response, _ in
        ok = (response as? HTTPURLResponse)?.statusCode == 200; done.signal()
    }.resume()
    done.wait()
    return ok ? now() - start : nil
}

@MainActor func run() async throws {
    let seedStart = now()
    try seed()
    let entry = SecretEntry(name: "Bench key", variable: "BENCH_KEY")
    try SecretVault.shared.save(entry, value: "bench-secret-value-0123456789")
    try SecretVault.shared.save(SecretEntry(name: "Bench token", variable: "BENCH_TOKEN"), value: "another-bench-token-abcdef")
    try SecretVault.shared.save(SecretEntry(name: "Bench password", variable: "BENCH_PASSWORD"), value: "hunter2-but-longer")
    let runtime = try ConversationRuntime()
    await runtime.resume()
    let server = RuntimeServer(runtime: runtime)
    try server.start()
    let model = DaemonContext(runtime)
    CompanionServer.shared.model = model
    CompanionServer.shared.start()
    for _ in 0..<100 where !CompanionServer.shared.isRunning { try await Task.sleep(for: .milliseconds(30)) }
    check(CompanionServer.shared.isRunning, "isolated phone server is listening")
    let token = CompanionServer.shared.issueToken(name: "Benchmark")
    let long = runtime.sessions.first { $0.title == "The long session" }!
    let socket = RuntimePaths.data.appendingPathComponent("daemon.sock").path
    print("[\(label)] seeded \(runtime.sessions.count) sessions, the long one \(long.items.count) rows, in \(ms(now() - seedStart))")

    // The first save scrubs everything once; what matters is the streaming saves after it.
    var takes: [Double] = [], totals: [Double] = []
    var warm = false
    runtime.onFlushTimed = { take, total in if warm { takes.append(take); totals.append(total) } }
    long.record.items.append(DisplayItem(kind: .assistant, text: "Starting", phase: .streaming))
    long.onStreamed?(long)
    try runtime.flush()
    runtime.waitForSaves()
    warm = true

    if env["BENCH_PROFILE"] == "1" {
        let fresh = runtime.sessions.map { ChatSession(record: $0.record) }
        var t = now(); for f in fresh { _ = f.latestThumbnailURL() }; print("cold thumbnails \(ms(now() - t))")
        t = now(); for f in fresh { _ = f.pendingRequests }; print("cold pending \(ms(now() - t))")
        t = now(); for f in fresh { _ = f.items.filter { $0.kind == .user || $0.kind == .assistant }.count }; print("cold count \(ms(now() - t))")
        t = now(); for f in fresh { _ = (f.items.last { $0.kind == .assistant && $0.phase == .final }).flatMap { ChatSession.firstSentence(of: String($0.text.prefix(4000)), limit: 320) } }; print("cold firstSentence \(ms(now() - t))")
        t = now(); for f in fresh { _ = f.record.navigationMetadata() }; print("cold metadata \(ms(now() - t))")
        t = now(); for f in fresh { _ = CompanionMapper.summary(f) }; print("cold phone summary \(ms(now() - t))")
        t = now(); for f in fresh { _ = CompanionMapper.summary(f) }; print("warm phone summary \(ms(now() - t))")
        t = now(); let projects = model.sidebarProjects; for p in projects { _ = model.sidechats(of: p); _ = model.worktrees(of: p) }; print("project children \(ms(now() - t))")
        t = now(); for c in model.sidebarChats { _ = model.sidechats(of: c) }; print("chat children \(ms(now() - t))")
        t = now(); var n = 0; for s in model.sessions { n += s.record.turnCompletions?.count ?? 0 }; print("activity \(ms(now() - t))")
    }
    // Where a list request's main-thread time goes.
    if env["BENCH_PROFILE"] == "1" {
        for pass in 1...3 {
            var t = now(); let snaps = runtime.snapshots(summaryOnly: true); let a = now() - t
            t = now(); let json = try JSON.value(snaps); let b = now() - t
            t = now(); let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; _ = try e.encode(RuntimeReply(id: "x", result: json)); let c = now() - t
            t = now(); let list = CompanionMapper.chatList(model); let d = now() - t
            t = now(); _ = try Companion.encoder.encode(list); let f = now() - t
            print("[\(label)] profile \(pass): snapshots \(ms(a)), JSON.value \(ms(b)), reply encode \(ms(c)), chatList \(ms(d)), chatList encode \(ms(f))")
        }
    }
    // Idle request costs, for reference.
    let idle = await Task.detached { () -> (Double?, Double?, Double?) in
        (http("/v1/chats", token: token), http("/v1/chats/\(long.id.uuidString)", token: token),
         socketRequest(socket, "list", ["summaryOnly": true]))
    }.value
    print("[\(label)] idle: /v1/chats \(idle.0.map(ms) ?? "failed"), /v1/chats/<long> \(idle.1.map(ms) ?? "failed"), socket list \(idle.2.map(ms) ?? "failed")")

    // A probe off the main thread: how late does work queued on main start?
    final class Box: @unchecked Sendable { var stalls: [Double] = []; var phone: [Double] = []; var detail: [Double] = []; var list: [Double] = []; var failed = 0; var stop = false; let lock = NSLock() }
    let box = Box()
    let probe = Thread {
        while !box.lock.withLock({ box.stop }) {
            let sent = now(), arrived = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { arrived.signal() }
            arrived.wait()
            let late = now() - sent
            box.lock.withLock { box.stalls.append(late) }
            usleep(5_000)
        }
    }
    probe.start()
    let requests = Thread {
        while !box.lock.withLock({ box.stop }) {
            let a = http("/v1/chats", token: token)
            let b = http("/v1/chats/\(long.id.uuidString)", token: token)
            let c = socketRequest(socket, "list", ["summaryOnly": true])
            box.lock.withLock {
                if let a { box.phone.append(a) } else { box.failed += 1 }
                if let b { box.detail.append(b) } else { box.failed += 1 }
                if let c { box.list.append(c) } else { box.failed += 1 }
            }
            usleep(50_000)
        }
    }
    requests.start()

    // Stream: a chunk every 20 ms into the last row, a new row now and then, a secret once.
    let end = Date().addingTimeInterval(seconds)
    var chunks = 0
    while Date() < end {
        let last = long.record.items.count - 1
        if chunks % 150 == 149 {
            long.record.items[last].phase = .final
            long.record.items.append(DisplayItem(kind: .tool, text: "Ran a step", toolState: .done))
            long.record.items.append(DisplayItem(kind: .assistant, text: "", phase: .streaming))
        } else {
            long.record.items[last].text += " " + prose(8) + (chunks == 3 ? " leaked bench-secret-value-0123456789 here" : "")
        }
        chunks += 1
        long.onStreamed?(long)
        try await Task.sleep(for: .milliseconds(20))
    }
    box.lock.withLock { box.stop = true }
    try await Task.sleep(for: .milliseconds(300))
    try runtime.flush()
    runtime.waitForSaves()

    print("[\(label)] streamed \(chunks) chunks for \(Int(seconds)) s into \(long.items.count) rows")
    print("[\(label)] save, main thread (scrub + copy): \(stats(takes))")
    print("[\(label)] save, main thread (all):          \(stats(totals))")
    box.lock.withLock {
        print("[\(label)] main-thread stall (probe):        \(stats(box.stalls))")
        print("[\(label)] GET /v1/chats while streaming:    \(stats(box.phone))")
        print("[\(label)] GET /v1/chats/<long>:             \(stats(box.detail))")
        print("[\(label)] socket list (summaryOnly):        \(stats(box.list))")
        print("[\(label)] failed requests: \(box.failed)")
    }

    // Secrets never reach the saved file or the live transcript.
    let saved = try String(contentsOf: RuntimePaths.data.appendingPathComponent("Conversations/\(long.id.uuidString).json"), encoding: .utf8)
    check(!saved.contains("bench-secret-value-0123456789") && saved.contains("••••(BENCH_KEY)"), "streamed secret masked in the saved file")
    check(!long.items.contains { $0.text.contains("bench-secret-value-0123456789") }, "streamed secret masked in the live transcript")
    // A secret added later is masked in rows already scrubbed.
    long.record.items[5].text += " late-added-secret-value"
    long.onChange?(long)
    try runtime.flush()
    try SecretVault.shared.save(SecretEntry(name: "Late", variable: "LATE_KEY"), value: "late-added-secret-value")
    long.onChange?(long)
    try runtime.flush()
    runtime.waitForSaves()
    let resaved = try String(contentsOf: RuntimePaths.data.appendingPathComponent("Conversations/\(long.id.uuidString).json"), encoding: .utf8)
    check(!resaved.contains("late-added-secret-value") && resaved.contains("••••(LATE_KEY)"), "a newly saved secret is masked in rows scrubbed before it")
    if env["BENCH_ENFORCE"] == "1" {
        let sortedTakes = takes.sorted(), median = sortedTakes.isEmpty ? 0 : sortedTakes[sortedTakes.count / 2]
        check(median < 0.005, "median save holds the main thread under 5 ms (\(ms(median)))")
        let worst = box.lock.withLock { (box.phone + box.detail + box.list).max() ?? 0 }
        check(worst < 1, "every phone and socket request answered under 1 s while streaming (\(ms(worst)))")
        check(box.lock.withLock { box.failed } == 0, "no request failed")
    }
    server.stop()
    exit(0)
}

Task { @MainActor in
    do { try await run() } catch { print("FAIL \(error)"); exit(1) }
}
RunLoop.main.run()

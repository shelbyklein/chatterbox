import AppKit
import Darwin

// Changes made on the Mac can't be lost when the background service is slow, unreachable or
// restarting (scripts/test-mac-outbox.sh, plans/mac-outbox.md). The Mac app (AppModel, in daemon
// mode) talks to a real service through a proxy that drops, delays or refuses its requests; the
// service is also killed and restarted mid-change, and the app relaunched with changes pending.
//
//   seed       writes the sessions
//   (none)     the faults, ending with the service killed and changes made while it's down
//   relaunch   a new app process and service: those changes reach the service

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
signal(SIGPIPE, SIG_IGN)
let projectID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
let chatID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
let doomedID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
let shelvedID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
let environment = ProcessInfo.processInfo.environment
let socketURL = RuntimePaths.data.appendingPathComponent("daemon.sock")
let realURL = RuntimePaths.data.appendingPathComponent("daemon-real.sock")
let outboxFile = RuntimePaths.data.appendingPathComponent("mac-outbox.json")

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeFailure("FAIL \(message)") }
    print("PASS \(message)")
}
@MainActor func wait(_ label: String, seconds: Double = 20, _ predicate: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !(await predicate()) {
        guard Date() < deadline else { throw RuntimeFailure("FAIL timed out: \(label)") }
        try await Task.sleep(for: .milliseconds(50))
    }
    print("PASS \(label)")
}
/// True the whole time: a change that must hold while updates keep coming.
@MainActor func holds(_ label: String, for seconds: Double, _ predicate: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        guard predicate() else { throw RuntimeFailure("FAIL \(label)") }
        try await Task.sleep(for: .milliseconds(40))
    }
    print("PASS \(label)")
}

@MainActor func seed() throws {
    let folder = RuntimePaths.data.appendingPathComponent("Conversations")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    func write(_ id: UUID, _ title: String, age: Double, _ change: (inout ConversationRecord) -> Void = { _ in }) throws {
        var record = ConversationRecord(model: "default", effort: "", personality: .neutral)
        record.id = id; record.title = title; record.updatedAt = Date().addingTimeInterval(-age)
        record.items = [DisplayItem(kind: .user, text: "Hello"), DisplayItem(kind: .assistant, text: "Hi", phase: .final)]
        change(&record)
        try encoder.encode(record).write(to: folder.appendingPathComponent("\(id.uuidString).json"))
    }
    try write(projectID, "Outbox project", age: 0) { $0.projectFolder = RuntimePaths.data.appendingPathComponent("project").path }
    try write(chatID, "Loose chat", age: 60)
    try write(doomedID, "Doomed chat", age: 120)
    try write(shelvedID, "Shelved chat", age: 180)
    AppPreferences.defaults.set(chatID.uuidString, forKey: "macLastOpenSession")
}

// MARK: The service, and a proxy in front of it

/// Starts the service; its socket is moved to daemon-real.sock for the proxy (and "the phone").
@MainActor func startService(_ name: String, behindProxy: Bool) async throws -> Process {
    let before = (try? FileManager.default.attributesOfItem(atPath: socketURL.path)[.systemFileNumber] as? Int) ?? nil
    let process = Process()
    process.executableURL = URL(fileURLWithPath: environment["OUTBOX_DAEMON"]!)
    let log = URL(fileURLWithPath: environment["OUTBOX_LOGS"]!).appendingPathComponent("\(name).log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    process.standardOutput = handle; process.standardError = handle
    try process.run()
    // Its own socket: a new file at daemon.sock (the proxy's, if any, is replaced).
    try await wait("the service (\(name)) is listening") {
        guard let node = (try? FileManager.default.attributesOfItem(atPath: socketURL.path)[.systemFileNumber]) as? Int else { return false }
        return node != before
    }
    if behindProxy {
        guard rename(socketURL.path, realURL.path) == 0 else { throw RuntimeFailure("FAIL couldn't move the service's socket") }
    }
    return process
}

/// Between the Mac app and the service: passes requests on, except those it's told to drop
/// (never answered, as if lost), delay (answered late, after later ones) or, while down, all of
/// them (connections are closed and refused, as when the service is gone).
final class Proxy: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [(Int32, Int32)] = []
    private var isDown = false
    private var drops: [String: Int] = [:]
    private var delays: [String: (count: Int, seconds: Double)] = [:]
    private var log: [String] = []

    func listen() {
        guard let fd = UnixSocket.listen(at: socketURL) else { fatalError("proxy can't listen") }
        Thread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; return }
                if down { close(client); continue }
                guard let server = UnixSocket.connect(to: realURL) else { close(client); continue }
                lock.withLock { connections.append((client, server)) }
                let writes = NSLock()
                Thread { self.pipe(from: server, to: client, writes: nil) }.start()
                Thread { self.pipe(from: client, to: server, writes: writes) }.start()
            }
        }.start()
    }
    var down: Bool {
        get { lock.withLock { isDown } }
        set {
            lock.withLock {
                isDown = newValue
                if newValue { for (a, b) in connections { shutdown(a, SHUT_RDWR); shutdown(b, SHUT_RDWR) }; connections = [] }
            }
        }
    }
    func drop(_ operation: String, count: Int = 1) { lock.withLock { drops[operation] = count } }
    func delay(_ operation: String, seconds: Double) { lock.withLock { delays[operation] = (1, seconds) } }
    func sent(_ operation: String) -> Int { lock.withLock { log.filter { $0 == operation }.count } }

    /// Raw bytes back to the app; requests line by line to the service, with the faults.
    private func pipe(from source: Int32, to target: Int32, writes: NSLock?) {
        var buffer = [UInt8](), chunk = [UInt8](repeating: 0, count: 65536)
        func send(_ bytes: [UInt8]) {
            writes?.lock(); defer { writes?.unlock() }
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBytes { write(target, $0.baseAddress, $0.count) }
                if n <= 0 { return }; offset += n
            }
        }
        while true {
            let n = read(source, &chunk, chunk.count)
            if n <= 0 { break }
            guard writes != nil else { send(Array(chunk[..<n])); continue }
            buffer.append(contentsOf: chunk[..<n])
            while let newline = buffer.firstIndex(of: 10) {
                let line = Array(buffer[...newline]); buffer.removeSubrange(...newline)
                let operation = ((try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any])?["operation"] as? String ?? ""
                enum Fate { case pass, drop, delay(Double) }
                let fate: Fate = lock.withLock {
                    log.append(operation)
                    if let left = drops[operation], left > 0 { drops[operation] = left - 1; return .drop }
                    if let delay = delays[operation], delay.count > 0 { delays[operation]!.count -= 1; return .delay(delay.seconds) }
                    return .pass
                }
                switch fate {
                case .pass: send(line)
                case .drop: print("  proxy: dropped \(operation)")
                case .delay(let seconds):
                    print("  proxy: holding \(operation) for \(seconds) s")
                    DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { send(line) }
                }
            }
        }
        shutdown(source, SHUT_RDWR); shutdown(target, SHUT_RDWR)
    }
}

// MARK: What the service has

/// A connection straight to the service, as the phone's changes and the checks need.
@MainActor enum Direct { static let client = RuntimeClient(socketName: "daemon-real.sock") }
@MainActor var direct: RuntimeClient { Direct.client }
@MainActor func onService(_ id: UUID, via client: RuntimeClient? = nil) async -> ConversationRecord? {
    try? await (client ?? direct).request("get", body: ["chatID": .string(id.uuidString), "limit": 40], timeout: .seconds(3)).decode(RuntimeChatState.self).record
}
@MainActor func serviceList(via client: RuntimeClient? = nil) async -> Set<UUID>? {
    (try? await (client ?? direct).request("list", body: ["summaryOnly": true], timeout: .seconds(5)).decode([RuntimeChatState].self)).map { Set($0.map(\.record.id)) }
}
/// As the service tells the app something changed: the app asks for the session again.
@MainActor func serviceUpdate(_ id: UUID) {
    RuntimeClient.shared.onEvent?(RuntimeEvent(sequence: 0, chatID: id, revision: 0, kind: "chat.changed"))
}
@MainActor func configureOutbox() {
    let outbox = RuntimeOutbox.shared
    outbox.requestTimeout = .seconds(2); outbox.slowAfter = 2; outbox.tick = .milliseconds(150)
}

// MARK: The faults

@MainActor func run() async throws {
    UserDefaults.standard.setVolatileDomain(["notifyNeeds": false, "notifyReplies": false, "companionEnabled": false], forName: UserDefaults.argumentDomain)
    var service = try await startService("service", behindProxy: true)
    let proxy = Proxy(); proxy.listen()
    direct.start(role: "ui")
    configureOutbox()
    let outbox = RuntimeOutbox.shared
    let model = AppModel()
    try await wait("the session list loads through the proxy") { model.sessions.count == 4 && model.sessionLoadStatus == nil && direct.connected }
    let project = model.sessions.first { $0.id == projectID }!
    let chat = model.sessions.first { $0.id == chatID }!
    try check(model.selectedID == chatID, "the loose chat is open (its updates carry its transcript)")

    // 0. Nothing in the way: a change goes through, and nothing new shows.
    project.toggleTag("Plain")
    try await holds("an ordinary change shows no Saving…", for: 1.5) { outbox.status(projectID) == nil }
    try await wait("…and the service has it") { await onService(projectID)?.tags == ["Plain"] }
    try check(proxy.sent("metadata") == 1, "one metadata request for one change")
    try await wait("the change is settled once the service's update came", seconds: 5) { outbox.isEmpty }

    // 1. The send is lost: updates from the service (with the old tags) keep coming meanwhile,
    //    for the open session (full transcript) and in a full list refresh.
    proxy.drop("metadata", count: 2)
    chat.toggleTag("Alpha")
    try check(chat.tags == ["Alpha"], "a tag shows at once")
    try check(outbox.status(chatID) == nil, "no Saving… at first")
    let churn = Timer(timeInterval: 0.1, repeats: true) { _ in MainActor.assumeIsolated { serviceUpdate(chatID) } }
    RunLoop.main.add(churn, forMode: .common)
    try await holds("the service's old copy doesn't take the tag away while it's pending", for: 1.0) { chat.tags == ["Alpha"] }
    let notYet = await onService(chatID)
    try check(notYet != nil && notYet?.tags == nil, "the service really doesn't have it yet (the send was lost)")
    RuntimeClient.shared.onEvent?(RuntimeEvent(sequence: 0, revision: 0, kind: "runtime.resync"))
    try await wait("Saving… shows once it's been pending a while", seconds: 6) { outbox.status(chatID) != nil }
    try check(chat.tags == ["Alpha"], "…and a full list refresh doesn't take it away either")
    try await wait("the retry gets it to the service") { await onService(chatID)?.tags == ["Alpha"] }
    try await wait("Saving… goes once it's confirmed", seconds: 5) { outbox.status(chatID) == nil }
    try await holds("the tag stays after the service's updates", for: 1.0) { chat.tags == ["Alpha"] }
    churn.invalidate()
    try check(proxy.sent("metadata") == 4, "sent again after each lost send, no more (\(proxy.sent("metadata")))")

    // 2. The send is slow (it lands after later requests), and the phone renames the session
    //    meanwhile: only the changed field goes, so the phone's name stays.
    proxy.delay("metadata", seconds: 3)
    project.toggleTag("Beta")
    try await Task.sleep(for: .milliseconds(300))
    let renamed = try await direct.request("rename", body: ["chatID": .string(projectID.uuidString), "title": "Named on the phone"])
    try check(renamed["ok"]?.bool == true, "the phone renames the session")
    for _ in 0..<10 { serviceUpdate(projectID); try await Task.sleep(for: .milliseconds(100)) }
    try check(project.tags == ["Plain", "Beta"], "a snapshot without the slow change doesn't revert it")
    try await wait("the Mac shows the phone's name", seconds: 5) { project.title == "Named on the phone" }
    try await wait("the slow change lands") { await onService(projectID)?.tags == ["Plain", "Beta"] }
    try await Task.sleep(for: .seconds(3.5))
    let afterSlow = await onService(projectID)
    try check(afterSlow?.title == "Named on the phone" && afterSlow?.tags == ["Plain", "Beta"], "the late send didn't clobber the phone's name (service: \(afterSlow?.title ?? "?"))")
    try check(project.title == "Named on the phone" && project.tags == ["Plain", "Beta"], "the Mac shows both")

    // 3. The service can't be reached for a while: a rename, the Brief, a setting, archiving,
    //    a delete and a new session, all made then, reach it once it's back.
    proxy.down = true
    try await wait("the app sees the service gone", seconds: 5) { !RuntimeClient.shared.connected }
    chat.setTitle("Renamed while away")
    chat.setBrief("A brief written while away")
    chat.setPersonality(.friendly)
    try check(chat.title == "Renamed while away" && chat.record.brief == "A brief written while away" && chat.record.personality == .friendly, "the changes show on the Mac at once")
    model.archive(model.sessions.first { $0.id == shelvedID }!)
    model.delete(model.sessions.first { $0.id == doomedID }!)
    // (Opening another session lets the loose chat's Brief go from memory, as it always does.)
    let fresh = model.newChat()
    fresh.setTitle("Made while away")
    try await wait("Not saved yet shows on the session", seconds: 8) {
        if case .retrying = outbox.status(chatID) { return true } else { return false }
    }
    try check(FileManager.default.fileExists(atPath: outboxFile.path), "pending changes are saved for a relaunch")
    try await Task.sleep(for: .seconds(2))
    proxy.down = false
    try await wait("the app is back with the service", seconds: 30) { RuntimeClient.shared.connected }
    try await wait("the rename, Brief and setting reach the service", seconds: 20) {
        let record = await onService(chatID)
        return record?.title == "Renamed while away" && record?.brief == "A brief written while away" && record?.personality == .friendly
    }
    try await wait("the archive reaches the service") { await onService(shelvedID)?.archivedAt != nil }
    try await wait("the new session reaches the service, named") { await onService(fresh.id)?.title == "Made while away" }
    try await wait("the delete reaches the service") { await serviceList().map { !$0.contains(doomedID) } ?? false }
    try await wait("everything is settled", seconds: 10) { outbox.isEmpty && outbox.status(chatID) == nil }
    try await Task.sleep(for: .seconds(1))
    try check(chat.title == "Renamed while away" && chat.record.personality == .friendly, "the Mac still shows them")
    try check(model.sessions.contains { $0.id == fresh.id } && !model.sessions.contains { $0.id == doomedID }, "the new session stayed and the deleted one stayed gone")
    try check(model.sessions.first { $0.id == shelvedID }?.record.archivedAt != nil, "the archived session stayed archived")
    try check(!FileManager.default.fileExists(atPath: outboxFile.path), "nothing left pending on disk")

    // 4. The service dies with a change on its way (never applied) and starts again.
    proxy.drop("metadata")
    project.toggleTag("Gamma")
    try await Task.sleep(for: .milliseconds(300))
    kill(service.processIdentifier, SIGKILL); service.waitUntilExit()
    try await wait("the app sees the service gone", seconds: 5) { !RuntimeClient.shared.connected }
    try check(project.tags == ["Plain", "Beta", "Gamma"], "the change still shows while the service is gone")
    service = try await startService("service-restarted", behindProxy: true)
    proxy.listen()
    try await wait("the app reconnects to the restarted service", seconds: 40) { RuntimeClient.shared.connected }
    try await wait("the change reaches the restarted service", seconds: 20) { await onService(projectID)?.tags == ["Plain", "Beta", "Gamma"] }
    try await wait("…and is settled", seconds: 10) { outbox.isEmpty }
    try check(project.tags == ["Plain", "Beta", "Gamma"], "the Mac still shows it")

    // 5. The service goes away again; changes made now wait on disk, and this app quits.
    kill(service.processIdentifier, SIGKILL); service.waitUntilExit()
    try await wait("the app sees the service gone", seconds: 5) { !RuntimeClient.shared.connected }
    project.toggleTag("Persisted")
    chat.setTitle("Named before quitting")
    try await wait("the pending changes are on disk", seconds: 5) {
        guard let saved = try? String(contentsOf: outboxFile, encoding: .utf8) else { return false }
        return saved.contains("Persisted") && saved.contains("Named before quitting")
    }
    RuntimeClient.shared.stop(); direct.stop()
}

/// A new app process (and service): what was pending reaches the service.
@MainActor func relaunch() async throws {
    UserDefaults.standard.setVolatileDomain(["notifyNeeds": false, "notifyReplies": false, "companionEnabled": false], forName: UserDefaults.argumentDomain)
    configureOutbox()
    let service = try await startService("service-relaunched", behindProxy: false)
    let model = AppModel()
    try check(!RuntimeOutbox.shared.isEmpty, "the relaunched app found the pending changes")
    try await wait("the session list loads", seconds: 30) { model.sessions.count == 4 && model.sessionLoadStatus == nil }
    try await wait("the pending tag reaches the service", seconds: 20) { await onService(projectID, via: .shared)?.tags == ["Plain", "Beta", "Gamma", "Persisted"] }
    try await wait("…and the pending name", seconds: 20) { await onService(chatID, via: .shared)?.title == "Named before quitting" }
    try await wait("…and they're settled", seconds: 10) { RuntimeOutbox.shared.isEmpty }
    let project = model.sessions.first { $0.id == projectID }!, chat = model.sessions.first { $0.id == chatID }!
    try check(project.tags == ["Plain", "Beta", "Gamma", "Persisted"] && chat.title == "Named before quitting", "the relaunched Mac shows them")
    try await wait("nothing left pending on disk", seconds: 3) { !FileManager.default.fileExists(atPath: outboxFile.path) }
    RuntimeClient.shared.stop()
    service.terminate(); service.waitUntilExit()
}

Task { @MainActor in
    do {
        if CommandLine.arguments.contains("seed") { try seed() }
        else if CommandLine.arguments.contains("relaunch") { try await relaunch() }
        else { try await run() }
        exit(0)
    } catch { print(error.localizedDescription); exit(1) }
}
app.run()

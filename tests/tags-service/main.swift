import Foundation
import Darwin

// Tags in the service (scripts/test-tags-service.sh): the Mac's "metadata" op on the socket
// sets a session's tags, and they show at once in the socket's list (summaryOnly, cached
// encoded by revision), in the phone's GET /v1/chats (summaries cached by revision) even
// when both were just asked for, and in the saved file. Then the same for removing them.

let port = ProcessInfo.processInfo.environment["CHATTERBOX_COMPANION_PORT"] ?? "19662"
let projectID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
let sideID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!

func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL \(message)"); exit(1) }
    print("PASS \(message)")
}

/// A line-delimited JSON connection to the service's socket, as the Mac app has.
final class SocketClient: @unchecked Sendable {
    let fd: Int32
    var buffer = Data()
    init?(_ path: String) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, path, 103) } }
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard fd >= 0, connected == 0 else { return nil }
        var timeout = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    /// The reply's result; nil (and the error printed) when it failed.
    func call(_ operation: String, _ body: [String: Any]) -> Any? {
        let id = UUID().uuidString
        var line = try! JSONSerialization.data(withJSONObject: ["version": 1, "id": id, "operation": operation, "body": body])
        line.append(10)
        guard line.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == line.count else { return nil }
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            while let newline = buffer.firstIndex(of: 10) {
                let reply = buffer.subdata(in: buffer.startIndex..<newline); buffer.removeSubrange(buffer.startIndex...newline)
                guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any], object["id"] as? String == id else { continue }
                if let error = object["error"] { print("  \(operation) failed: \(error)"); return nil }
                return object["result"] ?? NSNull()
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk.prefix(n))
        }
    }
}

func phoneChats(token: String) -> [[String: Any]] {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chats")!)
    request.setValue(token, forHTTPHeaderField: Companion.tokenHeader)
    let done = DispatchSemaphore(value: 0)
    var data: Data?
    URLSession.shared.dataTask(with: request) { body, _, _ in data = body; done.signal() }.resume()
    done.wait()
    guard let data, let list = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let groups = list["groups"] as? [[String: Any]] else { return [] }
    return groups.flatMap { ($0["chats"] as? [[String: Any]]) ?? [] }
}
func tags(_ chats: [[String: Any]], _ id: UUID) -> [String]? {
    chats.first { ($0["id"] as? String) == id.uuidString }?["tags"] as? [String]
}
func listTags(_ list: Any?, _ id: UUID) -> [String]? {
    ((list as? [[String: Any]])?.first { (($0["record"] as? [String: Any])?["id"] as? String) == id.uuidString }?["record"] as? [String: Any])?["tags"] as? [String]
}

@MainActor func run() async throws {
    let folder = RuntimePaths.data.appendingPathComponent("Conversations")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    var project = ConversationRecord(model: "default", effort: "", personality: .neutral)
    project.id = projectID; project.title = "Tagged project"
    project.projectFolder = RuntimePaths.data.appendingPathComponent("project").path
    project.items = [DisplayItem(kind: .user, text: "Hello"), DisplayItem(kind: .assistant, text: "Hi", phase: .final)]
    try encoder.encode(project).write(to: folder.appendingPathComponent("\(projectID.uuidString).json"))
    var side = ConversationRecord(model: "default", effort: "", personality: .neutral)
    side.id = sideID; side.title = "A work thread"; side.sidechatOf = projectID; side.sidechatProjectFolder = project.projectFolder
    side.items = [DisplayItem(kind: .user, text: "Side")]
    try encoder.encode(side).write(to: folder.appendingPathComponent("\(sideID.uuidString).json"))

    let runtime = try ConversationRuntime()
    await runtime.resume()
    let server = RuntimeServer(runtime: runtime)
    try server.start()
    let model = DaemonContext(runtime)
    CompanionServer.shared.model = model
    CompanionServer.shared.start()
    for _ in 0..<100 where !CompanionServer.shared.isRunning { try await Task.sleep(for: .milliseconds(30)) }
    check(CompanionServer.shared.isRunning, "isolated phone server is listening")
    let token = CompanionServer.shared.issueToken(name: "Tags test")
    let path = RuntimePaths.data.appendingPathComponent("daemon.sock").path

    // Off the main thread, which the service answers on.
    let results = await Task.detached { () -> [String: [String]?] in
        guard let mac = SocketClient(path), mac.call("hello", ["role": "ui"]) != nil else { return ["connect": nil] }
        var seen: [String: [String]?] = [:]
        // Warm both caches: the phone's summaries and the socket's encoded list.
        seen["phone before"] = tags(phoneChats(token: token), projectID)
        seen["list before"] = listTags(mac.call("list", ["summaryOnly": true]), projectID)
        func setTags(_ id: UUID, _ value: [String]?) -> Bool {
            guard var record = (mac.call("get", ["chatID": id.uuidString, "summaryOnly": true]) as? [String: Any])?["record"] as? [String: Any] else { return false }
            record["tags"] = value ?? NSNull()
            return mac.call("metadata", ["record": record]) != nil
        }
        seen["set"] = setTags(projectID, ["alpha"]) && setTags(sideID, ["beta"]) ? ["ok"] : nil
        let phone = phoneChats(token: token)
        seen["phone after"] = tags(phone, projectID)
        seen["phone side after"] = tags(phone, sideID)
        let list = mac.call("list", ["summaryOnly": true])
        seen["list after"] = listTags(list, projectID)
        seen["list side after"] = listTags(list, sideID)
        seen["removed"] = setTags(projectID, nil) ? ["ok"] : nil
        seen["phone removed"] = tags(phoneChats(token: token), projectID)
        seen["list removed"] = listTags(mac.call("list", ["summaryOnly": true]), projectID)
        return seen
    }.value
    check(results["connect"] == nil, "connected to the socket as the Mac app")
    check(results["phone before"]! == nil && results["list before"]! == nil, "no tags to begin with (phone and socket lists warmed)")
    check(results["set"]! != nil, "the metadata op accepts the tags")
    check(results["phone after"]! == ["alpha"], "the phone's list shows the tag at once")
    check(results["phone side after"]! == ["beta"], "…and a work thread's tag")
    check(results["list after"]! == ["alpha"] && results["list side after"]! == ["beta"], "the socket's list shows the tags at once")
    check(results["removed"]! != nil && results["phone removed"]! == nil && results["list removed"]! == nil, "removing a tag shows at once too")
    // Put back for the saved-file check.
    runtime.session(projectID)!.record.tags = ["alpha"]; runtime.session(projectID)!.onChange?(runtime.session(projectID)!)
    try await Task.sleep(for: .milliseconds(300))
    try runtime.flush(); runtime.waitForSaves()
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let saved = try decoder.decode(ConversationRecord.self, from: Data(contentsOf: folder.appendingPathComponent("\(sideID.uuidString).json")))
    check(saved.tags == ["beta"], "the service saved the work thread's tag")
    server.stop()
    exit(0)
}

Task { @MainActor in
    do { try await run() } catch { print("FAIL \(error)"); exit(1) }
}
RunLoop.main.run()

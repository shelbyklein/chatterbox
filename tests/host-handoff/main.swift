import Foundation
import Darwin
// Handing off to a newer host build: the client asks the running host if it's the build it
// would start; an older one is moved aside and finishes what it runs, new work goes to a
// new host, and the old one exits once its processes are done.
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeFailure(message) }
    print("PASS \(message)")
}
func wait(_ what: String, seconds: Double = 10, _ done: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { if await done() { return }; try await Task.sleep(for: .milliseconds(100)) }
    throw RuntimeFailure("timed out: \(what)")
}
func pids(_ binary: String) -> [String] {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-f", "^" + binary + "$"]
    let out = Pipe(); p.standardOutput = out; try? p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
}
@MainActor func test() async throws {
    let env = ProcessInfo.processInfo.environment
    let old = env["OLD_HOST"]!, current = env["CHATTERBOX_HOST_BINARY"]!
    let client = HostClient.shared
    // The older build, already running with a process the app started before the install.
    try await wait("the old host listens") { FileManager.default.fileExists(atPath: HostPaths.socket.path) }
    try check(pids(old).count == 1 && pids(current).isEmpty, "only the old host is running")

    try client.connect()
    try check(pids(current).count == 1, "the client started the current host")
    let aside = (try FileManager.default.contentsOfDirectory(atPath: HostPaths.directory.path)).filter { $0.hasPrefix("host-draining-") }
    try check(aside.count == 1, "the old host's socket was moved aside (\(aside))")
    let processes = try await client.list()
    try check(processes.contains { $0.id == "before-install" && $0.running }, "the old host's process is still listed")
    try check(client.isOnDrainingHost("before-install"), "and known to be on the draining host")

    try client.spawn(id: "after-install", executable: "/bin/sleep", arguments: ["30"], cwd: nil, environment: [:], kind: nil)
    try await wait("the new process starts") { (try? await client.list())?.contains { $0.id == "after-install" && $0.running } == true }
    try check(!client.isOnDrainingHost("after-install"), "new work goes to the current host")

    // Reachable through the client: output, then stopping it.
    var attached = false
    try client.attach(id: "before-install", from: 0, onLine: { _, _ in }, onExit: { _, _ in })
    attached = true
    client.kill(id: "before-install")
    try await wait("the old process ends") { (try? await client.list())?.contains { $0.id == "before-install" && $0.running } != true }
    try check(attached, "the old host's process is still reachable (attach, kill)")
    try await wait("the old host exits", seconds: 15) { pids(old).isEmpty }
    try check(pids(old).isEmpty && pids(current).count == 1, "the old host exited once its processes were done")
    try await wait("the current host still answers") { FileManager.default.fileExists(atPath: HostPaths.socket.path) }
    let after = (try? await client.list()) ?? []
    try check(after.contains { $0.id == "after-install" }, "and the current host carries on")
    // An app with the older host (an older install sharing the folder, say) mustn't take it back.
    let probe = UnixSocket.connect(to: HostPaths.socket)!
    var hello = try JSON.object(["op": "hello", "binary": .string(old)]).encoded(); hello.append(0x0A)
    _ = hello.withUnsafeBytes { Darwin.write(probe, $0.baseAddress!, $0.count) }
    var buffer = [UInt8](repeating: 0, count: 512)
    let n = read(probe, &buffer, buffer.count)
    close(probe)
    let reply = n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self) : ""
    try check(reply.contains("\"current\":true"), "an older build asking leaves the newer host in place (\(reply.trimmingCharacters(in: .newlines)))")
    client.kill(id: "after-install")
    print("PASS host handoff")
}
Task { @MainActor in do { try await test(); exit(0) } catch { print("FAIL \(error.localizedDescription)"); exit(1) } }
RunLoop.main.run()

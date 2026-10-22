import Foundation
import Darwin

// Chats on Shelby-PC, against a stand-in ssh that runs the real worker
// (deploy/pc-worker/chatterbox-worker.js) on this Mac with the fake provider.

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeFailure(message) }
    print("PASS \(message)")
}
@MainActor func wait(_ message: String, seconds: Double = 10, until predicate: () -> Bool) async throws {
    let until = Date().addingTimeInterval(seconds)
    while !predicate() { if Date() > until { throw RuntimeFailure("Timed out: \(message)") }; try await Task.sleep(for: .milliseconds(20)) }
}
struct Launch { var pid: Int32; var cwd: String; var argv: [String]; var chat: String?; var base: String? }
func launches() -> [Launch] {
    let file = ProcessInfo.processInfo.environment["FAKE_PROVIDER_LAUNCHES"]!
    return ((try? String(contentsOfFile: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { line in
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        return Launch(pid: Int32(o["pid"] as? Int ?? 0), cwd: o["cwd"] as? String ?? "", argv: o["argv"] as? [String] ?? [],
                      chat: o["chat"] as? String, base: o["base"] as? String)
    }
}
func lines(_ name: String) -> [[String: Any]] {
    let file = RuntimePaths.data.appendingPathComponent(name)
    return ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
}
func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

@MainActor func test() async throws {
    let env = ProcessInfo.processInfo.environment
    let testDir = env["PC_TEST_DIR"]!
    UserDefaults.standard.setVolatileDomain([
        "claudePath": env["FAKE_PROVIDER"]!, "codexPath": env["FAKE_PROVIDER"]!,
        "easyCLIProxyEnabled": false, "remoteControlClaudeChats": false,
        "pcWorkspaceRoot": testDir + "/workspaces", "pcAttachmentsRoot": testDir + "/attachments",
    ], forName: UserDefaults.argumentDomain)

    // Names and paths.
    let id = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
    try check(RemoteMachine.workspaceFolder(title: "Install  ComfyUI!", id: id) == "install-comfyui-abcdef12", "workspace folder from title and id")
    var windows = RemoteMachine.pc
    windows.workspaceRoot = #"D:\Chatterbox\workspaces"#
    let mirror = windows.mirror(of: #"d:\chatterbox\workspaces\job-1\out\page.html"#)?.path ?? ""
    try check(mirror.hasSuffix("/Chatterbox/PC/job-1/out/page.html"), "PC path maps into the Mac mirror")
    try check(windows.mirror(of: #"D:\Chatterbox\workspaces\..\..\Windows\x.png"#)?.path.contains("..") == false, "mirror ignores parent references")
    try check(windows.mirror(of: #"C:\Windows\x.png"#) == nil, "paths outside workspaces aren't mirrored")
    try check(RemoteLaunch.scpPath(#"D:\Chatterbox\a b.txt"#) == "/D:/Chatterbox/a b.txt", "scp path for a Windows drive")
    try check(ChatSession.openModelEffort("xhigh") == "high" && ChatSession.openModelEffort(nil) == "medium"
              && ChatSession.openModelEffort("low") == "low", "open model effort limited to what Ollama accepts")

    let runtime = try ConversationRuntime(root: RuntimePaths.data)
    await runtime.resume()

    // Claude on the PC: launched through the worker, in its PC workspace, chat id via the header.
    var claudeRecord = ConversationRecord(model: "default", effort: "", personality: .neutral)
    claudeRecord.title = "PC Claude"
    claudeRecord.activeBackend = .claude
    claudeRecord.projectFolder = RuntimePaths.data.path
    claudeRecord.runOn = "pc"
    let claude = try runtime.insert(claudeRecord)
    claude.send("hello")
    try await wait("PC Claude reply") { !claude.isRunning && claude.items.contains { $0.kind == .assistant } }
    let claudeLaunch = launches().last { $0.chat == claude.id.uuidString && !$0.argv.contains("app-server") }
    let folder = claude.record.remoteFolder ?? "?"
    try check(claudeLaunch?.cwd.hasSuffix("workspaces\\" + folder) == true, "PC Claude runs in its workspace (\(claudeLaunch?.cwd ?? "none"))")
    let sshArgs = (try? String(contentsOfFile: testDir + "/ssh-args.log", encoding: .utf8)) ?? ""
    try check(sshArgs.contains("BatchMode=yes") && !sshArgs.contains(claude.id.uuidString), "variables travel in the header, not the ssh command line")
    let system = (try? String(contentsOf: RuntimePaths.data.appendingPathComponent("claude-system.jsonl"), encoding: .utf8)) ?? ""
    try check(system.contains("Where you're running"), "PC Claude is told it runs on the PC")

    // Codex on the PC and on the Mac at the same time, each on its own app-server.
    func codexRecord(_ title: String, pc: Bool) -> ConversationRecord {
        var r = ConversationRecord(model: "default", effort: "", personality: .neutral)
        r.title = title
        r.activeBackend = .codex
        r.projectFolder = RuntimePaths.data.path
        r.codex = CodexSettings(effort: "xhigh", folder: RuntimePaths.data.path, canEdit: true, mode: "fullAccess")
        r.runOn = pc ? "pc" : nil
        return r
    }
    let pcCodex = try runtime.insert(codexRecord("PC Codex", pc: true))
    let macCodex = try runtime.insert(codexRecord("Mac Codex", pc: false))
    pcCodex.send("hello pc")
    macCodex.send("hello mac")
    try await wait("both Codex replies") {
        [pcCodex, macCodex].allSatisfy { s in !s.isRunning && s.items.contains { $0.kind == .assistant } }
    }
    try check(CodexAppServer.pc.isRunning && CodexAppServer.shared.isRunning && CodexAppServer.pc.hostID != CodexAppServer.shared.hostID,
              "Mac and PC Codex chats run on separate app-servers")
    let turns = lines("codex-turns.jsonl")
    let pcFolder = pcCodex.record.remoteFolder ?? "?"
    try check(turns.contains { ($0["cwd"] as? String)?.hasSuffix("workspaces\\" + pcFolder) == true }, "PC Codex turn uses the PC workspace")
    try check(turns.contains { ($0["cwd"] as? String) == RuntimePaths.data.path }, "Mac Codex turn keeps its folder")
    let scripts = (try? String(contentsOf: URL(fileURLWithPath: testDir + "/powershell.log"), encoding: .utf8)) ?? ""
    try check(scripts.contains("New-Item -ItemType Directory") && scripts.contains("workspaces\\\(pcFolder)'"),
              "PC Codex workspace is created before its thread starts")

    // Open model on the PC: Codex turns name it with an accepted effort.
    pcCodex.setOpenModel("qwen3.5:9b")
    pcCodex.send("open model")
    try await wait("PC Codex open-model reply") { !pcCodex.isRunning && pcCodex.items.filter { $0.kind == .assistant }.count >= 2 }
    let last = lines("codex-turns.jsonl").last ?? [:]
    try check(last["model"] as? String == "qwen3.5:9b" && last["effort"] as? String == "high", "Codex open-model turn: model and effort (\(last))")
    try check(pcCodex.codexConnection.key.hasPrefix("open:pc:") && (pcCodex.codexConnection.config["model_provider"] == .string("chatterbox-pc")),
              "Codex open model uses the chatterbox-pc provider")

    // Open model for Claude on the PC: relaunched against Ollama on the PC, with no extra tool servers.
    claude.setOpenModel("qwen3.5:9b")
    try await wait("Claude restarts for the open model") { claude.claudeProcess == nil }
    claude.send("open model")
    try await wait("PC Claude open-model reply") { !claude.isRunning && claude.items.filter { $0.kind == .assistant }.count >= 2 }
    let openLaunch = launches().last { $0.chat == claude.id.uuidString && !$0.argv.contains("app-server") }
    try check(openLaunch?.base == "http://127.0.0.1:11434" && openLaunch?.argv.contains("qwen3.5:9b") == true
              && openLaunch?.argv.contains("--strict-mcp-config") == true, "Claude open model launch on the PC")

    // Stopping a PC chat ends its provider on the "PC" too.
    let pid = openLaunch?.pid ?? 0
    try check(alive(pid), "PC Claude provider running before stop")
    claude.claudeProcess?.terminate()
    try await wait("PC provider ends after stop", seconds: 8) { !alive(pid) }
    try check(true, "PC provider ended after stop")

    // Moving a chat back to the Mac starts a fresh session there, caught up on the chat.
    pcCodex.setRunOn(nil)
    try check(pcCodex.record.codex?.threadId == nil && pcCodex.record.pendingHandoff?.isEmpty == false && pcCodex.record.runOn == nil,
              "switching machine starts a new thread with a handoff")

    // An unreachable PC fails fast with a clear message.
    let started = Date()
    do {
        _ = try await RemoteLaunch.process("/usr/bin/ssh", RemoteLaunch.sshOptions(connectTimeout: 5) + ["chatterbox-unreachable.invalid", "echo"])
        throw RuntimeFailure("unreachable host answered")
    } catch let error as RemoteLaunch.RemoteError {
        try check(error.status == 255 && (error.errorDescription ?? "").contains("isn't reachable") && Date().timeIntervalSince(started) < 15,
                  "unreachable PC reported within 15 s: \(error.errorDescription ?? "")")
    }

    // A Mac chat on a PC model says the PC is unreachable instead of waiting on Claude.
    var macOpen = ConversationRecord(model: "default", effort: "", personality: .pragmatic)
    macOpen.title = "Mac open model"
    macOpen.openModel = "qwen3.5:9b"
    let macClaude = try runtime.insert(macOpen)
    let sent = Date()
    macClaude.send("hello")
    try await wait("unreachable notice for a Mac open-model chat", seconds: 20) {
        macClaude.items.contains { $0.kind == .notice && $0.text.contains("isn't reachable") }
    }
    try check(Date().timeIntervalSince(sent) < 15 && macClaude.claudeProcess == nil && !macClaude.isRunning,
              "Mac open-model chat reports an unreachable PC within 15 s without starting Claude")

    for s in runtime.sessions { s.shutdown() }
    for codex in CodexAppServer.all { codex.terminate() }
    HostClient.shared.disconnect()
    print("PASS PC worker: Claude, Codex, open models, stop, unreachable")
}
Task { @MainActor in do { try await test(); exit(0) } catch { print("FAIL \(error.localizedDescription)"); exit(1) } }
RunLoop.main.run()

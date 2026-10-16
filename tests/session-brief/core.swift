import Foundation
import Darwin
// Issue #45 through the conversation engine, with the fixture providers: a session's Brief
// reaches both agents (at start, once on change, after a switch), handoffs list the tools
// used, and a switch notes an MCP server the incoming agent lacks.

func check(_ condition: @autoclosure () -> Bool, _ message:String) throws {
    guard condition() else {throw RuntimeFailure(message)}
    print("PASS \(message)")
}
@MainActor func wait(_ message:String, until predicate: () -> Bool) async throws {
    let until=Date().addingTimeInterval(10)
    while !predicate() { if Date()>until { throw RuntimeFailure("Timed out: \(message)") };try await Task.sleep(for:.milliseconds(20)) }
}
func lines(_ name:String) -> [String] {
    let url=RuntimePaths.data.appendingPathComponent(name)
    return ((try? String(contentsOf:url,encoding:.utf8)) ?? "").split(separator:"\n").compactMap { line in
        guard let value=try? JSONSerialization.jsonObject(with:Data(line.utf8),options:.fragmentsAllowed) else { return nil }
        if let text=value as? String { return text }
        return (value as? [String:Any])?["instructions"] as? String
    }
}
@MainActor func test() async throws {
    let root=RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/chatterbox-session-brief."))
    UserDefaults.standard.setVolatileDomain([
        "claudePath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,"codexPath":ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!,
        "easyCLIProxyEnabled":false,"remoteControlClaudeChats":false
    ], forName:UserDefaults.argumentDomain)

    // Tool keys and the tools-used line.
    try check(Tools.key(claudeName:"mcp__indesign__set_text")=="mcp:indesign/set_text" && Tools.key(claudeName:"Bash")=="Bash","Claude tool names become keys")
    var rows:[DisplayItem]=[]
    for (tool,n) in [("mcp:indesign/set_text",32),("mcp:indesign/place_image",14),("Bash",3)] { for _ in 0..<n { var r=DisplayItem(kind:.tool,text:"x");r.tool=tool;rows.append(r) } }
    rows.append(DisplayItem(kind:.tool,text:"an older row, no tool"))
    let line=ChatSession.toolsUsed(rows[...])
    try check(line=="indesign MCP (set_text \u{00D7}32, place_image \u{00D7}14), Bash \u{00D7}3","tools used: \(line ?? "nil")")
    try check(ChatSession.toolsUsed([DisplayItem(kind:.user,text:"hi")][...])==nil,"no tools, no line")

    let runtime=try ConversationRuntime(root:root)
    await runtime.resume()
    var r=ConversationRecord(model:"default",effort:"",personality:.neutral)
    r.activeBackend = .claude
    r.brief="Lay out the brochure in InDesign through the indesign MCP. Files: ~/Brochure.indd"
    let s=try runtime.insert(r)

    // At start: in Claude's system prompt, not sent again as an update.
    s.send("Start, mcp")
    try await wait("first reply") { !s.isRunning && s.items.contains { $0.kind == .assistant } }
    try check(lines("claude-system.jsonl").last?.contains("<session_brief>") == true && lines("claude-system.jsonl").last?.contains("Brochure.indd") == true,"Claude starts with the Brief")
    try check(lines("claude-input.jsonl").last?.contains("session_brief") == false,"and isn't sent it again with the message")
    try check(s.items.contains { $0.kind == .tool && $0.tool == "mcp:indesign/set_text" },"Claude's MCP tool row records its tool")

    // Unchanged: nothing. Changed: once.
    s.send("Carry on")
    try await wait("second reply") { !s.isRunning && lines("claude-input.jsonl").count>=2 }
    try check(lines("claude-input.jsonl").last?.contains("session_brief") == false,"an unchanged Brief sends nothing")
    s.setBrief("Use the indesign MCP only. Keep the 2027 colors.")
    s.send("Next")
    try await wait("third") { lines("claude-input.jsonl").count>=3 }
    try check(lines("claude-input.jsonl").last?.contains("Keep the 2027 colors") == true,"an edited Brief goes once")
    try await wait("third done") { !s.isRunning }
    s.send("And again")
    try await wait("fourth") { lines("claude-input.jsonl").count>=4 }
    try check(lines("claude-input.jsonl").last?.contains("session_brief") == false,"and not again")
    try await wait("fourth done") { !s.isRunning }

    // Switch to Codex: the handoff names the tools, the Brief comes along, and the missing
    // MCP server is noted (Codex's config here has none).
    s.setBackend(.codex)
    try check(s.record.pendingHandoff?.contains("Tools used: indesign MCP (set_text)") == true,"the handoff names the tools used")
    try check(s.items.suffix(3).contains { $0.kind == .notice && $0.text.contains("Codex doesn't have the \u{201C}indesign\u{201D} MCP server") },"a switch notes the missing MCP server")
    s.send("Your turn")
    try await wait("codex reply") { lines("codex-input.jsonl").count>=1 }
    let codexStart=lines("codex-system.jsonl").last ?? ""
    let codexFirst=lines("codex-input.jsonl").last ?? ""
    try check(codexStart.contains("Keep the 2027 colors") || codexFirst.contains("Keep the 2027 colors"),"Codex gets the Brief after the switch")
    try check(codexFirst.contains("Tools used: indesign MCP"),"and the handoff with the tools")
    try check(!(codexStart.contains("Keep the 2027 colors") && codexFirst.contains("Keep the 2027 colors")),"but only once")
    try await wait("codex done") { !s.isRunning }

    // Cleared: one note to ignore it.
    s.setBrief("")
    s.send("No brief now")
    try await wait("cleared") { lines("codex-input.jsonl").count>=2 }
    try check(lines("codex-input.jsonl").last?.contains("no brief now") == true,"clearing the Brief says so once")
    try await wait("cleared done") { !s.isRunning }

    // With the server in Codex's own config, it counts as there (no notice).
    let home=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_TOOLS_HOME"]!).appendingPathComponent(".codex")
    try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
    try "[mcp_servers.indesign]\ncommand = \"indesign-mcp\"\n".write(to:home.appendingPathComponent("config.toml"),atomically:true,encoding:.utf8)
    try check(ChatSession.agentHasServer("indesign",.codex,session:s) && !ChatSession.agentHasServer("figma",.codex,session:s),"a server in Codex's config counts; one it lacks doesn't")
    for s in runtime.sessions {s.shutdown()}
    try runtime.flush()
    print("PASS session brief and tool context")
}
Task { @MainActor in
    do {try await test();exit(0)} catch {print("FAIL \(error.localizedDescription)");exit(1)}
}
RunLoop.main.run()

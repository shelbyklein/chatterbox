import Foundation
import Darwin
import CryptoKit
// Agent tools: levels and layering, discovery of the agents' own config (read only), and
// what Claude's launch and Codex's thread get. No agents run.
func check(_ condition: @autoclosure () -> Bool, _ message:String) throws {
    guard condition() else {throw RuntimeFailure(message)}
    print("PASS \(message)")
}
func digest(_ path:String) -> String {
    var all=""
    for case let file as String in FileManager.default.enumerator(atPath:path) ?? FileManager.default.enumerator(atPath:"/")! {
        if let data=FileManager.default.contents(atPath:path+"/"+file) { all+=file+":"+SHA256.hash(data:data).description+"\n" }
    }
    return all
}
@MainActor func test() async throws {
    let root=RuntimePaths.data.path
    precondition(root.hasPrefix("/tmp/chatterbox-agent-tools."))
    let home=ProcessInfo.processInfo.environment["CHATTERBOX_TOOLS_HOME"]!
    let fm=FileManager.default
    let project=root+"/projects/sdhq"; try fm.createDirectory(atPath:project+"/.claude/skills/wp-check",withIntermediateDirectories:true)
    try "---\nname: wp-check\n---\n".write(toFile:project+"/.claude/skills/wp-check/SKILL.md",atomically:true,encoding:.utf8)
    try #"{"mcpServers":{"wordpress":{"command":"wp-mcp","args":["--site","sdhq"]}}}"#.write(toFile:project+"/.mcp.json",atomically:true,encoding:.utf8)
    // The agents' own config, as on this Mac.
    try fm.createDirectory(atPath:home+"/.claude/skills/impeccable",withIntermediateDirectories:true)
    try "---\nname: impeccable\n---\n".write(toFile:home+"/.claude/skills/impeccable/SKILL.md",atomically:true,encoding:.utf8)
    try #"{"mcpServers":{"inspo":{"type":"http","url":"https://inspomcp.dev/api/mcp"},"graft":{"command":"node","args":["graft.mjs","mcp"],"env":{"GRAFT_TOKEN":"x","MODE":"dev"}}}}"#.write(toFile:home+"/.claude.json",atomically:true,encoding:.utf8)
    try fm.createDirectory(atPath:home+"/.codex",withIntermediateDirectories:true)
    try fm.createDirectory(atPath:home+"/.agents/skills/shared-skill",withIntermediateDirectories:true)
    try "---\nname: shared-skill\n---\n".write(toFile:home+"/.agents/skills/shared-skill/SKILL.md",atomically:true,encoding:.utf8)
    try fm.createSymbolicLink(atPath:home+"/.claude/skills/shared-skill",withDestinationPath:home+"/.agents/skills/shared-skill")
    for (dir,text) in [(home+"/.claude/skills/drifted","claude"),(home+"/.agents/skills/drifted","codex")] {
        try fm.createDirectory(atPath:dir,withIntermediateDirectories:true)
        try "---\nname: drifted\n---\n\(text)\n".write(toFile:dir+"/SKILL.md",atomically:true,encoding:.utf8)
    }
    try """
    model = "gpt-6.1-sol"
    [mcp_servers.inspo]
    url = "https://inspomcp.dev/api/mcp"
    [mcp_servers.helper]
    command = "./Helper.app/run"
    args = ["mcp"]
    cwd = "."
    enabled = false
    [mcp_servers.noun-project]
    command = "/usr/bin/node"
    args = ["dist/index.js"]
    enabled = false
    [mcp_servers.noun-project.env]
    NOUN_PROJECT_API_KEY = "secret"
    """.write(toFile:home+"/.codex/config.toml",atomically:true,encoding:.utf8)
    // Plugins: one switched on (with a server and a skill), one installed but off.
    for (name,on) in [("stripe",true),("cloudflare",false)] {
        let dir=home+"/.claude/plugins/cache/\(name)"
        try fm.createDirectory(atPath:dir+"/skills/\(name)-skill",withIntermediateDirectories:true)
        try "---\nname: x\n---\n".write(toFile:dir+"/skills/\(name)-skill/SKILL.md",atomically:true,encoding:.utf8)
        try #"{"mcpServers":{"api":{"type":"http","url":"https://example/mcp"}}}"#.write(toFile:dir+"/.mcp.json",atomically:true,encoding:.utf8)
        _ = on
    }
    try #"{"plugins":{"stripe@official":[{"installPath":"HOME/.claude/plugins/cache/stripe"}],"cloudflare@official":[{"installPath":"HOME/.claude/plugins/cache/cloudflare"}]}}"#.replacingOccurrences(of:"HOME",with:home).write(toFile:home+"/.claude/plugins/installed_plugins.json",atomically:true,encoding:.utf8)
    try #"{"enabledPlugins":{"stripe@official":true,"cloudflare@official":false}}"#.write(toFile:home+"/.claude/settings.json",atomically:true,encoding:.utf8)
    try fm.createDirectory(atPath:home+"/.codex/helper/Helper.app",withIntermediateDirectories:true)
    fm.createFile(atPath:home+"/.codex/helper/Helper.app/run",contents:Data("#!/bin/sh\n".utf8),attributes:[.posixPermissions:0o755])
    try fm.createDirectory(atPath:project+"/.codex",withIntermediateDirectories:true)
    try "[mcp_servers.sdhq-db]\ncommand = \"db-mcp\"\n".write(toFile:project+"/.codex/config.toml",atomically:true,encoding:.utf8)
    let before=digest(home)+digest(project)

    // T3: discovery
    let found=ToolDiscovery.discover(projectFolder:project)
    func item(_ kind:DiscoveredTool.Kind,_ name:String)->DiscoveredTool?{found.first{$0.kind==kind && $0.name==name}}
    try check(item(.server,"inspo")?.agents == [.claude,.codex],"a server both agents have is one row for both")
    try check(item(.server,"graft")?.source == .claude && item(.server,"wordpress")?.source == .project,"Claude's and the project's own servers are found")
    try check(item(.server,"noun-project")?.enabledThere == false,"Codex servers it has switched off are marked off")
    try check(item(.skill,"impeccable") != nil && item(.skill,"wp-check")?.source == .project,"Claude's and the project's skills are found")
    try check(found.filter{$0.kind == .skill && $0.name=="shared-skill"}.map(\.agents)==[[.claude,.codex]],"a skill both agents load from one folder is one row for both")
    try check(found.filter{$0.kind == .skill && $0.name=="drifted"}.count==2 && item(.skill,"drifted")?.drift==true,"copies that differ are both listed and marked")
    try check(item(.connector,"ChatGPT apps")?.offKey == ToolKey.codexApps,"Codex's apps are one connector row")
    try check(item(.server,"plugin:stripe:api")?.offKey == ToolKey.server("plugin_stripe_api") && item(.skill,"stripe:stripe-skill") != nil,"a switched-on plugin's servers and skills are found")
    try check(!found.contains { $0.name.contains("cloudflare") },"a plugin that's switched off isn't listed")
    try check(item(.server,"graft")?.importable?.env == ["MODE":"dev"],"import copies plain env and leaves keys for Secrets")
    let helper=item(.server,"helper")?.importable
    try check(helper?.command==home+"/.codex/helper/Helper.app/run" && helper?.cwd==home+"/.codex/helper","a server with relative paths imports with absolute ones")
    ToolDiscovery.noteClaudeServers(["inspo","claude.ai Gmail","claude.ai Google Calendar"])
    try check(ToolDiscovery.connectors().map(\.name).contains("Gmail"),"claude.ai connectors a chat loaded are listed")

    // T2: levels
    let runtime=try ConversationRuntime(root:RuntimePaths.data)
    var p=ConversationRecord(model:"default",effort:"",personality:.neutral);p.projectFolder=project;p.activeBackend = .claude
    let projectChat=try runtime.insert(p)
    var st=ConversationRecord(model:"default",effort:"",personality:.neutral);st.studioID=UUID();st.activeBackend = .codex
    st.codex=CodexSettings(folder:root,canEdit:false,mode:"fullAccess")
    let studioChat=try runtime.insert(st)
    let plain=try runtime.insert(ConversationRecord(model:"default",effort:"",personality:.neutral))
    let baseline=ClaudeCodeProcess.arguments(.init(cwd:root,model:"opus",effort:"",permissionMode:"default",appendSystemPrompt:"x"))
    try check(ToolScopes.effective(for:projectChat).isEmpty && ToolScopes.fingerprint(for:projectChat).isEmpty,"no Tools settings: nothing changes")
    let linear=ToolServer(name:"linear",kind:.url,url:"https://mcp.linear.app/mcp",bearerSecret:"LINEAR_TOKEN")
    let wp=ToolServer(name:"wp",kind:.command,command:"wp-mcp",args:["--x"],agents:[.claude])
    let figma=ToolServer(name:"figma",kind:.url,url:"https://figma/mcp")
    try ToolScopes.save([
        "chatterbox":ToolSet(servers:[linear],off:[ToolKey.skill("impeccable")]),
        "studios":ToolSet(servers:[figma],off:[ToolKey.server("inspo"),ToolKey.codexApps]),
        ToolScope.project(project).key:ToolSet(servers:[wp],off:[ToolKey.server("linear"),ToolKey.connector("Gmail")],skillFolders:[project+"/.claude/skills"]),
    ])
    let ep=ToolScopes.effective(for:projectChat), es=ToolScopes.effective(for:studioChat), eplain=ToolScopes.effective(for:plain)
    try check(eplain.servers.map(\.name)==["linear"],"a plain chat gets Chatterbox-wide")
    try check(Set(es.servers.map(\.name))==["linear","figma"] && es.isOff(ToolKey.server("inspo")),"a Studio chat gets Chatterbox-wide + Studios, with its offs")
    try check(ep.servers.map(\.name)==["wp"],"a project can turn off a Chatterbox-wide server for itself")
    try check(ep.isOff(ToolKey.skill("impeccable")),"Chatterbox-wide offs reach every level")
    var side=projectChat.record;side.id=UUID();side.projectFolder=nil;side.sidechatOf=projectChat.id;side.sidechatProjectFolder=project
    try check(ToolScopes.effective(for:ChatSession(record:side)).servers.map(\.name)==["wp"],"a project's Sidechats and sidequests get the project's set")

    // T4: Claude's launch
    let file=projectChat.claudeToolsMCPConfigFile(ep)!
    let spec=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:file))) as! [String:Any]
    try check(((spec["mcpServers"] as! [String:Any])["wp"] as! [String:Any])["command"] as? String=="wp-mcp","the added servers go in a --mcp-config file")
    let mode=try fm.attributesOfItem(atPath:file)[.posixPermissions] as? Int
    try check(mode==0o600,"that file is readable only by this user")
    let rules=ChatSession.claudeDisallowedTools(ep)
    try check(rules.contains("mcp__linear") && rules.contains("mcp__claude_ai_Gmail") && rules.contains("Skill(impeccable)"),"what's off becomes tool rules (server, connector, skill)")
    var shared=ep;shared.skillFolders.append(home+"/.agents/skills/shared-skill");shared.skillFolderAgents[home+"/.agents/skills/shared-skill"]=[.codex]
    try check(shared.skillFolders(for:.claude).count==1 && shared.skillFolders(for:.codex).count==2,"a skill shared with one agent goes only to that agent")
    let plugin=projectChat.claudeToolsPluginDir(ep)!
    try check(fm.fileExists(atPath:plugin+"/skills/wp-check/SKILL.md") && fm.fileExists(atPath:plugin+"/.claude-plugin/plugin.json"),"added skill folders become a plugin")
    let args=ClaudeCodeProcess.arguments(.init(cwd:root,model:"opus",effort:"",permissionMode:"default",appendSystemPrompt:"x",toolsMCPConfig:file,disallowedTools:rules,pluginDirs:[plugin]))
    try check(args.contains("--mcp-config="+file) && args.contains("--disallowedTools=mcp__linear") && args.contains(plugin),"Claude's launch carries them, joined with =")
    try check(ClaudeCodeProcess.arguments(.init(cwd:root,model:"opus",effort:"",permissionMode:"default",appendSystemPrompt:"x"))==baseline,"a launch without tools is unchanged")

    // T5: Codex's thread config
    let codex=studioChat.codexToolsConfig(es,codexServers:ToolDiscovery.codexServerNames())
    try check(codex["mcp_servers.figma"]?["url"]?.string=="https://figma/mcp","Codex threads get the added servers")
    try check(codex["mcp_servers.inspo.enabled"]==false && codex["features.apps"]==false,"and its own servers and apps switched off")
    let stray=studioChat.codexToolsConfig(EffectiveTools(off:[ToolKey.server("not-a-codex-server")]),codexServers:ToolDiscovery.codexServerNames())
    try check(stray.isEmpty,"servers Codex doesn't have aren't named")
    try check(projectChat.codexToolsConfig(ep,codexServers:[])["mcp_servers.wp"]==nil,"a Claude-only server stays out of Codex")
    let key1=studioChat.codexConfigurationKey
    var sets=ToolScopes.load();sets["studios"]?.off.removeAll{$0==ToolKey.codexApps};try ToolScopes.save(sets)
    try check(studioChat.codexConfigurationKey != key1,"a change reloads the Codex thread")
    try check(item(.server,"sdhq-db")?.source == .project && ToolDiscovery.codexServerNames(projectFolder:project).contains("sdhq-db"),"a project's .codex/config.toml servers are found, and can be switched off")

    // T6: the toolbar's Tools popover
    func state(_ list:[ToolDiscovery.LoadedServer],_ name:String)->ToolDiscovery.LoadedServer.State?{list.first{$0.name==name}?.state}
    let claudeLoads=ToolDiscovery.loadedServers(.claude,projectFolder:project,tools:ep)
    try check([state(claudeLoads,"inspo"),state(claudeLoads,"graft"),state(claudeLoads,"wordpress"),state(claudeLoads,"plugin:stripe:api")].allSatisfy{$0 == .on},"a Claude chat lists ~/.claude.json's, the project's and plugins' servers")
    try check(state(claudeLoads,"wp") == .addedInChatterbox && state(claudeLoads,"sdhq-db")==nil,"plus what Chatterbox adds, and not Codex's")
    let codexLoads=ToolDiscovery.loadedServers(.codex,projectFolder:project,tools:es)
    try check(state(codexLoads,"inspo") == .offInChatterbox && state(codexLoads,"noun-project") == .offInConfig,"a Codex chat marks what Chatterbox or its config switched off")
    try check(state(codexLoads,"sdhq-db") == .on && state(codexLoads,"figma") == .addedInChatterbox,"and lists the project's and Chatterbox's servers")
    try check(ChatSession.claudeToolSearch([:]) && ChatSession.claudeToolSearch(["ANTHROPIC_BASE_URL":"https://api.anthropic.com"]),"tool search is on by default")
    try check(!ChatSession.claudeToolSearch(["ANTHROPIC_BASE_URL":"http://127.0.0.1:8317"]),"and off on another base URL")
    try check(ChatSession.claudeToolSearch(["ANTHROPIC_BASE_URL":"http://127.0.0.1:8317","ENABLE_TOOL_SEARCH":"true"]) && !ChatSession.claudeToolSearch(["ENABLE_TOOL_SEARCH":"false"]),"unless ENABLE_TOOL_SEARCH says otherwise")

    try check(digest(home)+digest(project)==before,"the agents' own config files are untouched")
    for s in runtime.sessions {s.shutdown()};try runtime.flush()
    print("PASS agent tools")
}
Task { @MainActor in do {try await test();exit(0)} catch {print("FAIL \(error.localizedDescription)");exit(1)} }
RunLoop.main.run()

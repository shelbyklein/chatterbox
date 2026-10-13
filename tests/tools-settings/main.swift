@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Settings → Tools at the Chatterbox level, and a project's Tools… sheet, against a fixture
// home folder. Evidence: chatterbox.png, project.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func shot(_ view:some View,_ size:NSSize,_ name:String,_ root:String) async throws {
    let window=NSWindow(contentRect:NSRect(origin:.init(x:40,y:40),size:size),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:view.frame(width:size.width,height:size.height).environment(\.colorScheme,.dark).background(Color(white:0.12)))
    window.orderFrontRegardless()
    try await Task.sleep(for:.seconds(2))
    let v=window.contentView!;v.layoutSubtreeIfNeeded()
    let rep=v.bitmapImageRepForCachingDisplay(in:v.bounds)!;v.cacheDisplay(in:v.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/"+name))
    window.orderOut(nil)
}
@MainActor func run() async throws {
    let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
    precondition(root.hasPrefix("/tmp/chatterbox-tools-settings."))
    let home=ProcessInfo.processInfo.environment["CHATTERBOX_TOOLS_HOME"]!
    let fm=FileManager.default
    try fm.createDirectory(atPath:home+"/.claude/skills/impeccable",withIntermediateDirectories:true)
    try "---\nname: impeccable\n---\n".write(toFile:home+"/.claude/skills/impeccable/SKILL.md",atomically:true,encoding:.utf8)
    try fm.createDirectory(atPath:home+"/.claude/skills/dev-sync",withIntermediateDirectories:true)
    try "---\nname: dev-sync\n---\n".write(toFile:home+"/.claude/skills/dev-sync/SKILL.md",atomically:true,encoding:.utf8)
    try #"{"mcpServers":{"inspo":{"type":"http","url":"https://inspomcp.dev/api/mcp"},"graft":{"command":"node","args":["graft.mjs","mcp"]}}}"#.write(toFile:home+"/.claude.json",atomically:true,encoding:.utf8)
    try fm.createDirectory(atPath:home+"/.codex",withIntermediateDirectories:true)
    try "[mcp_servers.noun-project]\ncommand = \"node\"\nargs = [\"dist/index.js\"]\nenabled = false\n".write(toFile:home+"/.codex/config.toml",atomically:true,encoding:.utf8)
    ToolDiscovery.noteClaudeServers(["claude.ai Gmail"])
    let folder=root+"/sdhq"; try fm.createDirectory(atPath:folder,withIntermediateDirectories:true)
    try ToolScopes.save([
        "chatterbox":ToolSet(servers:[ToolServer(name:"linear",kind:.url,url:"https://mcp.linear.app/mcp")],off:[ToolKey.skill("impeccable")]),
        ToolScope.project(folder).key:ToolSet(servers:[ToolServer(name:"wordpress",kind:.command,command:"wp-mcp",args:["--site","sdhq"])],off:[ToolKey.connector("Gmail")]),
    ])
    let model=AppModel()
    try await shot(ToolsSettingsView().environment(model),NSSize(width:760,height:900),"chatterbox.png",root)
    try await shot(ProjectToolsSheet(folder:folder,name:"SDHQ").environment(model),NSSize(width:680,height:900),"project.png",root)
    print("PASS tools settings render. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

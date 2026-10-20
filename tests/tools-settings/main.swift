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
    // Exercise the actual button, including the loading-to-results transition. Rendering
    // SessionToolsSummary by itself never exercises NSPopover's animated window resize.
    @MainActor func openTools(_ backend:Backend,_ name:String) async throws {
        var record=ConversationRecord(model:"default",effort:"",personality:.neutral)
        record.projectFolder=folder;record.activeBackend=backend
        let session=model.insertSession(record)
        let window=NSWindow(contentRect:NSRect(x:80,y:80,width:400,height:500),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua)
        window.contentView=NSHostingView(rootView:ToolsButton(session:session).environment(model).frame(width:400,height:500))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for:.milliseconds(250))
        let point=window.contentView!.convert(NSPoint(x:200,y:250),to:nil)
        print("Opening Tools: \(name)");fflush(stdout)
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
        }
        try await Task.sleep(for:.milliseconds(40))
        guard let popover=NSApp.windows.first(where:{$0.isVisible && $0 != window}) else {preconditionFailure("Tools click must present its popover")}
        let first=popover.frame.size
        try await Task.sleep(for:.milliseconds(700))
        precondition(abs(popover.frame.height-first.height)<1 && abs(popover.frame.width-first.width)<1,"Tools must not resize after discovery")
        precondition(popover.frame.height>=360 && popover.frame.height<410,"Tools keeps a bounded, fixed window instead of resizing to its contents (\(popover.frame))")
        if let view=popover.contentView {
            let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/"+name+".png"))
        }
        print("PASS actual Tools popover \(name), stable \(first)");fflush(stdout)
        popover.orderOut(nil);window.orderOut(nil)
    }
    for backend in [Backend.claude,.codex] {try await openTools(backend,"button-"+backend.rawValue)}
    try await shot(ToolsSettingsView().environment(model),NSSize(width:760,height:900),"chatterbox.png",root)
    try await shot(ProjectToolsSheet(folder:folder,name:"SDHQ").environment(model),NSSize(width:680,height:900),"project.png",root)
    // The toolbar's Tools popover for a Claude and a Codex chat in the project.
    try #"{"mcpServers":{"wordpress":{"command":"wp-mcp"}}}"#.write(toFile:folder+"/.mcp.json",atomically:true,encoding:.utf8)
    var sets=ToolScopes.load();sets[ToolScope.project(folder).key]?.off.append(ToolKey.server("graft"));try ToolScopes.save(sets)
    for backend in [Backend.claude,.codex] {
        var record=ConversationRecord(model:"default",effort:"",personality:.neutral);record.projectFolder=folder;record.activeBackend=backend
        let chat=model.insertSession(record)
        try await shot(SessionToolsSummary(session:chat).padding(16).frame(width:320).environment(model),NSSize(width:320,height:360),"popover-\(backend.rawValue).png",root)
    }
    // Settings → Instructions: a Studio's note, the Brief, and each project's handed-across file.
    try "# SDHQ\nBuild with the shared scripts.\n".write(toFile:folder+"/AGENTS.md",atomically:true,encoding:.utf8)
    try "@AGENTS.md\n".write(toFile:folder+"/CLAUDE.md",atomically:true,encoding:.utf8)
    let other=root+"/site"; try fm.createDirectory(atPath:other,withIntermediateDirectories:true)
    try "# Site\nDeploy with wrangler.\n".write(toFile:other+"/AGENTS.md",atomically:true,encoding:.utf8)
    var site=ConversationRecord(model:"default",effort:"",personality:.neutral);site.projectFolder=other
    _=model.insertSession(site)
    model.studios=[Studio(name:"Brand",folder:root+"/studio",instructions:"Use the brand kit in Figma.")]
    try await shot(InstructionsSettingsView().environment(model),NSSize(width:760,height:1100),"instructions.png",root)
    // A large result stays inside the same window; an empty result does too.
    let many=(0..<60).map { "[mcp_servers.server-\($0)]\ncommand = \"test-server\"\n" }.joined(separator:"\n")
    try many.write(toFile:home+"/.codex/config.toml",atomically:true,encoding:.utf8)
    try await openTools(.codex,"button-many")
    try "".write(toFile:home+"/.codex/config.toml",atomically:true,encoding:.utf8)
    try ToolScopes.save([:])
    try await openTools(.codex,"button-empty")
    // Clean exits replace the previous-run marker, even if one already exists.
    let diagnostics=URL(fileURLWithPath:root+"/Diagnostics")
    try Data("old marker".utf8).write(to:diagnostics.appendingPathComponent("last-run.json"))
    Diagnostics.shared.stop()
    let saved=try JSONSerialization.jsonObject(with:Data(contentsOf:diagnostics.appendingPathComponent("last-run.json"))) as! [String:Any]
    precondition(saved["pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier),"the latest run replaces the stale marker")
    precondition(!fm.fileExists(atPath:diagnostics.appendingPathComponent("running.json").path),"a clean exit clears the running marker")
    print("PASS tools settings render, real popovers and crash markers. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

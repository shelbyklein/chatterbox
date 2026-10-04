import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: env["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-columns."))
    UserDefaults.standard.setVolatileDomain([
        "dotCheckIns":false, "dotWatchWaiting":false, "dotSummarizeFinished":false, "dotEmailWatch":false,
        "companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,
        "golemPanelOpen":true
    ],forName: UserDefaults.argumentDomain)
    // Writable preferences in this standalone test executable, not launch-argument overrides.
    // Argument-domain values cannot be changed by AppStorage, which would make drag tests inert.
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    for (key,value) in ["mainSidebarVisible":true,"mainSidebarWidth":260.0,"golemInspectorWidth":0.0,"issuesInspectorWidth":0.0,"previewInspectorWidth":0.0] as [String:Any] {
        UserDefaults.standard.set(value,forKey:key)
    }
    let model = AppModel()
    let dot = model.sessions.first { $0.isDot }!
    let project = model.sessions.first { $0.record.projectFolder == "/Users/shelbyklein/Vibes/Chatterbox" }!
    model.selectedID = dot.id
    let panel = NSPanel(contentRect:NSRect(x:20,y:80,width:1600,height:820),styleMask:[.titled,.closable,.resizable,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.contentView = NSHostingView(rootView:ContentView().environment(model))
    panel.orderFrontRegardless()
    func all(_ v:NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
    func frames() -> [(String,CGRect)] {
        all(panel.contentView!).compactMap { v in
            guard let p = v as? ColumnProbe.Probe else { return nil }
            return (p.role,p.convert(p.bounds,to:nil))
        }
    }
    func check(_ label:String) {
        let width = panel.contentView!.bounds.width
        let values=frames()
        precondition(!values.isEmpty,"No frame probes")
        print("MEASURE \(label) window=\(width) \(values)"); fflush(stdout)
        capture(panel,root.appendingPathComponent(label+".png"))
        for (role,f) in values {
            precondition(f.minX >= -0.5 && f.maxX <= width+0.5,"\(label) \(role) outside window: \(f), width \(width)")
            precondition(f.width > 0)
        }
        precondition(!all(panel.contentView!).contains { $0 is NSSplitView },"Nested split returned")
        print("PASS \(label) window=\(width) \(values)")
        capture(panel,root.appendingPathComponent(label+".png"))
    }
    try await Task.sleep(for:.seconds(2))
    for width in [1600.0,1100,950,800,640] {
        panel.setContentSize(NSSize(width:width,height:820))
        try await Task.sleep(for:.milliseconds(600))
        check("golem-\(Int(width))")
    }
    // A real AppKit drag, routed to the production divider's mouse handlers.
    panel.setContentSize(NSSize(width:1100,height:820))
    try await Task.sleep(for:.milliseconds(500))
    let before=frames().first {$0.0=="sidebar"}!.1.width
    let handle=all(panel.contentView!).compactMap {$0 as? ColumnResizeHandle.Handle}.min { $0.convert($0.bounds,to:nil).minX < $1.convert($1.bounds,to:nil).minX }!
    let center=handle.convert(NSPoint(x:3,y:100),to:nil)
    func event(_ type:NSEvent.EventType,_ x:CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:center.y),modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    }
    handle.mouseDown(with:event(.leftMouseDown,center.x))
    handle.mouseDragged(with:event(.leftMouseDragged,center.x+40))
    try await Task.sleep(for:.milliseconds(400))
    let after=frames().first {$0.0=="sidebar"}!.1.width
    precondition(abs(after-before-40)<1,"Divider did not resize: \(before) -> \(after)")
    check("golem-resized")
    model.sidebarToggleRequest += 1
    try await Task.sleep(for:.milliseconds(400))
    precondition(!frames().contains {$0.0=="sidebar"})
    model.sidebarToggleRequest += 1
    try await Task.sleep(for:.milliseconds(400))
    precondition(abs(frames().first {$0.0=="sidebar"}!.1.width-after)<1,"Width lost after toggle")
    // Force full text + image content to stay bounded after switching away and back.
    model.selectedID=project.id
    try await Task.sleep(for:.milliseconds(700))
    check("project-1100")
    model.selectedID=dot.id
    try await Task.sleep(for:.milliseconds(700))
    check("golem-reopened")
    // The same container with actual Issues and WebKit views, no network service involved.
    var noRepo = project.record
    noRepo.projectFolder = nil; noRepo.githubRepo = nil; noRepo.items = []
    let quiet = ChatSession(record: noRepo)
    let html = root.appendingPathComponent("preview.html")
    try "<html><body style='background:#222;color:white'><h1>Local preview</h1><p>Bounded preview test</p></body></html>".write(to:html,atomically:true,encoding:.utf8)
    for web in [false,true] {
        panel.contentView = NSHostingView(rootView:InspectorFixture(session:quiet,url:html,web:web).environment(model))
        for width in [1100.0,800,640] {
            panel.setContentSize(NSSize(width:width,height:820))
            try await Task.sleep(for:.milliseconds(700))
            check("\(web ? "preview" : "issues")-\(Int(width))")
        }
        let overlay=frames().first {$0.0=="inspector-overlay"}!.1
        let position=NSPoint(x:overlay.maxX-20,y:overlay.maxY-20)
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            let click=NSEvent.mouseEvent(with:type,location:position,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            panel.sendEvent(click)
        }
        try await Task.sleep(for:.milliseconds(500))
        precondition(!frames().contains {$0.0.hasPrefix("inspector")},"Overlay close did not work")
        check("\(web ? "preview" : "issues")-closed")
    }
    print("PASS native pane bounds, real divider drag, sidebar toggle and width persistence, chat switch; Issues and local WebKit; actual overlay close clicks; no nested NSSplitView")
    exit(0)
}
struct InspectorFixture: View {
    let session: ChatSession
    let url: URL
    let web: Bool
    @State private var open = true
    var body: some View {
        ChatColumns(sidebar:AnyView(Text("Sidebar")),chat:AnyView(ChatView(session:session)),
            inspector:open ? (web ? AnyView(WebPaneView(page:WebPage(url:url)) {open=false}) : AnyView(IssuesPanel(session:session,panel:IssuesPanelState()))) : nil,
            inspectorMinimum:web ? 360 : 300,inspectorIdeal:web ? 620 : 380,inspectorMaximum:web ? 1400 : 640,
            closeInspector:{open=false})
    }
}
@MainActor func capture(_ window:NSWindow,_ url:URL) {
    typealias Fn = @convention(c) (CGRect,UInt32,UInt32,UInt32)->Unmanaged<CGImage>?
    guard let sym=dlsym(UnsafeMutableRawPointer(bitPattern:-2),"CGWindowListCreateImage") else {return}
    let fn=unsafeBitCast(sym,to:Fn.self)
    guard let image=fn(.null,1<<3,UInt32(window.windowNumber),(1<<0)|(1<<3))?.takeRetainedValue() else {return}
    try? NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])?.write(to:url)
}
Task { do {try await run()} catch {print("FAIL",error);exit(1)} }
app.run()

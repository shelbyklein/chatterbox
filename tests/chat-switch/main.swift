@testable import Chatterbox
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
    dot.draft = "Unsent Golem draft"
    project.draft = "Unsent project draft"
    let counts = [dot.items.count,project.items.count]
    let transition = ChatSwitchTransition()
    model.selectedID = dot.id
    let panel = NSPanel(contentRect:NSRect(x:20,y:80,width:1100,height:820),styleMask:[.titled,.closable,.resizable,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.contentView = NSHostingView(rootView:ContentView(chatSwitch:transition).environment(model))
    panel.orderFrontRegardless()
    func snap(_ label:String) {
        capture(panel,root.appendingPathComponent(label+".png"))
        print("FRAME \(label) id=\(String(describing:transition.displayedID)) opacity=\(transition.opacity) offset=\(transition.offset) switching=\(transition.switching)"); fflush(stdout)
    }
    func wait(_ predicate:() -> Bool) async throws {
        let until=Date().addingTimeInterval(8)
        while !predicate() {
            precondition(Date()<until,"Transition timed out")
            try await Task.sleep(for:.milliseconds(5))
        }
    }
    try await Task.sleep(for:.seconds(2))
    snap("01-golem")
    let switchStarted=Date()
    model.selectedID = project.id
    try await wait {transition.switching}
    snap("02-outgoing-or-hidden")
    try await wait {transition.displayedID==project.id}
    precondition(transition.opacity==0 && transition.switching)
    snap("03-hidden-swap")
    try await wait {transition.opacity==1}
    try await Task.sleep(for:.milliseconds(70))
    snap("04-incoming")
    try await wait {!transition.switching}
    print("NATIVE selection-to-interactive: \(Int(Date().timeIntervalSince(switchStarted)*1000))ms (includes capture overhead)")
    snap("05-project")
    // Repeated picks through the actual ContentView task cancellation path.
    model.selectedID = dot.id
    try await Task.sleep(for:.milliseconds(40))
    model.selectedID = project.id
    try await Task.sleep(for:.milliseconds(40))
    model.selectedID = dot.id
    try await wait {transition.displayedID==dot.id && !transition.switching}
    snap("06-rapid-final-golem")
    print("DRAFT CHECK golem=\(dot.draft.debugDescription) project=\(project.draft.debugDescription)")
    precondition(dot.draft=="Unsent Golem draft" && project.draft=="Unsent project draft")
    precondition(counts==[dot.items.count,project.items.count],"Switch submitted or mutated transcript")
    // Capture-free measurements separate render/cancellation latency from screenshot cost.
    for target in [project.id,dot.id,project.id,dot.id] {
        let start=Date()
        model.selectedID=target
        try await wait {transition.displayedID==target && !transition.switching}
        print("NATIVE capture-free selection-to-interactive: \(Int(Date().timeIntervalSince(start)*1000))ms")
    }
    // Narrow layout remains bounded after animated switching.
    panel.setContentSize(NSSize(width:800,height:820))
    try await Task.sleep(for:.milliseconds(400))
    snap("07-narrow")
    func all(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(all)}
    for probe in all(panel.contentView!).compactMap({$0 as? ColumnProbe.Probe}) {
        let f=probe.convert(probe.bounds,to:nil)
        precondition(f.minX >= -0.5 && f.maxX<=800.5,"Animated pane outside window")
    }
    print("PASS native Golem/regular hidden swap, outgoing/incoming captures, rapid latest selection, unchanged drafts/transcripts, narrow pane bounds")
    exit(0)
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

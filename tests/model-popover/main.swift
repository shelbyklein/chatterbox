@testable import Chatterbox
import AppKit
import SwiftUI
// The model popover: Claude | Codex | Open models, that provider's list, the effort slider.
// Evidence: popover.png (Claude), popover-open.png (a session on a PC open model).
let app=NSApplication.shared
app.setActivationPolicy(.regular)
var failures=0
func check(_ ok:Bool,_ what:String) { print((ok ? "PASS " : "FAIL ")+what); fflush(stdout); if !ok { failures+=1 } }
Thread.detachNewThread { Thread.sleep(forTimeInterval: 120); print("FAIL timed out"); exit(2) }
@MainActor func shot(_ window:NSWindow,_ name:String,_ root:URL) throws {
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotEmailWatch":false,"companionEnabled":false],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    let session=model.newChat(backend:.claude)
    session.setModel("opus");session.setEffort("high")
    let window=NSWindow(contentRect:NSRect(x:60,y:60,width:420,height:640),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    window.appearance=NSAppearance(named:.darkAqua)
    var closed=false
    window.contentView=NSHostingView(rootView:ModelPopover(session:session){ closed=true }.background(Color(white:0.14)).environment(model).environment(\.colorScheme,.dark))
    window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
    try await Task.sleep(for:.seconds(1.5))
    try shot(window,"popover.png",root)
    func press(_ chars:String,_ code:UInt16) {
        for type in [NSEvent.EventType.keyDown,.keyUp] {
            window.sendEvent(NSEvent.keyEvent(with:type,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!)
        }
    }
    press("\r",36)
    try await Task.sleep(for:.milliseconds(300))
    check(closed,"Return closes it")
    // A session on an open model opens on the Open models list.
    session.record.openModel="qwen3.5:9b"
    window.contentView=NSHostingView(rootView:ModelPopover(session:session){}.background(Color(white:0.14)).environment(model).environment(\.colorScheme,.dark))
    try await Task.sleep(for:.milliseconds(900))
    try shot(window,"popover-open.png",root)
    print(failures==0 ? "PASS model popover. Evidence: \(root.path)" : "FAIL \(failures) checks. Evidence: \(root.path)")
    exit(failures==0 ? 0 : 1)
}
Task { @MainActor in do {try await run()} catch {print(error);exit(1)} }
app.run()

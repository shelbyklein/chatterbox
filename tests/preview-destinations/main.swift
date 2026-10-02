import AppKit
import SwiftUI
import WebKit
import ScreenCaptureKit
@testable import ChatterboxTestEngine
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"keepMacAwake":false], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let session = model.newChat(backend:.claude)
    session.setModel("claude-opus-5-5")
    session.setFastMode(true)
    precondition(session.fastMode && session.supportsClaudeFastMode)
    let roundTrip = try JSONDecoder().decode(ConversationRecord.self, from: JSONEncoder().encode(session.record))
    precondition(roundTrip.claudeFastMode == true)
    session.setModel("claude-sonnet-5")
    precondition(!session.fastMode && !session.supportsClaudeFastMode)
    session.setModel("claude-opus-5-6")
    precondition(!session.supportsClaudeFastMode, "Unknown Opus minor was incorrectly supported")
    session.setModel("claude-opus-5-5")
    precondition(session.fastMode, "Switching models lost saved preference")
    let options = CompanionMapper.detail(session, model:model).options!
    precondition(options.fastMode == true)
    CompanionMapper.apply(.init(fastMode:false), to:session)
    precondition(session.record.claudeFastMode == false)
    let config = ClaudeCodeProcess.Config(cwd:root.path, model:"claude-opus-5-5", effort:"medium", permissionMode:"default", appendSystemPrompt:"", resumeSessionID:nil, fastMode:true)
    let args = ClaudeCodeProcess.arguments(config)
    let settings = args[args.firstIndex(of:"--settings")! + 1]
    let decoded = try JSONSerialization.jsonObject(with:Data(settings.utf8)) as! [String:Bool]
    precondition(decoded["fastMode"] == true)
    precondition(PreviewDestination.allCases.count == 6)
    precondition(PreviewDestination.chrome.bundleID == "com.google.Chrome" && PreviewDestination.chromium.bundleID == "org.chromium.Chromium" && PreviewDestination.safari.bundleID == "com.apple.Safari")
    let url = URL(fileURLWithPath:"/Users/shelbyklein/Chatterbox/Dot/output/medieval-parallax-cape.html")
    let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:490),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.appearance = NSAppearance(named:.darkAqua)
    var selected:PreviewDestination?
    let view = NSHostingView(rootView:PreviewDestinationChooser(url:url) { selected = $0 })
    panel.contentView = view
    panel.center();panel.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1))
    func webCount(_ v:NSView) -> Int { (v is WKWebView ? 1:0) + v.subviews.reduce(0) { $0 + webCount($1) } }
    precondition(webCount(view) == 0 && selected == nil, "Chooser eagerly loaded a web view")
    let target = try await SCShareableContent.currentProcess.windows.first { $0.windowID == CGWindowID(panel.windowNumber) }!
    let capture = SCStreamConfiguration();capture.width=840;capture.height=Int(panel.frame.height*2);capture.ignoreShadowsSingleWindow=true
    let image = try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:target),configuration:capture)
    try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("chooser.png"))
    func targets(_ v: NSView) -> [NSView] {
        let type = String(describing: type(of:v))
        return (type.contains("FocusRingView") && v.frame.width > 200 ? [v] : []) + v.subviews.flatMap(targets)
    }
    let buttons = targets(view).sorted { view.convert($0.bounds, from:$0).minY < view.convert($1.bounds, from:$1).minY }
    print("Native row targets", buttons.map { view.convert($0.bounds, from:$0) }, "flipped", view.isFlipped)
    precondition(buttons.count == 6, "Couldn't locate six native button targets")
    for (index, option) in PreviewDestination.allCases.enumerated() where option.available {
        let row = buttons[view.isFlipped ? index : 5-index]
        let point = row.convert(NSPoint(x:row.bounds.midX,y:row.bounds.midY), to:nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with:type, location:point, modifierFlags:[], timestamp:ProcessInfo.processInfo.systemUptime,
                                          windowNumber:panel.windowNumber, context:nil, eventNumber:1, clickCount:1, pressure:1)!
            app.sendEvent(event)
        }
        try await Task.sleep(for:.milliseconds(150))
        precondition(selected == option, "Chooser dispatched wrong destination for \(option.title)")
    }
    panel.close()
    let fastPanel = NSPanel(contentRect:NSRect(x:0,y:0,width:380,height:600), styleMask:[.titled,.nonactivatingPanel], backing:.buffered,defer:false)
    fastPanel.appearance = NSAppearance(named:.darkAqua)
    fastPanel.contentView = NSHostingView(rootView:ModelPopover(session:session) {})
    fastPanel.center(); fastPanel.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(700))
    let fastTarget = try await SCShareableContent.currentProcess.windows.first { $0.windowID == CGWindowID(fastPanel.windowNumber) }!
    capture.width=760;capture.height=Int(fastPanel.frame.height*2)
    let fastImage = try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:fastTarget),configuration:capture)
    try NSBitmapImageRep(cgImage:fastImage).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("claude-fast.png"))
    fastPanel.close()
    print("PASS six lazy destinations (zero WKWebViews before choice); native mouse button selections; browser application IDs; Claude model support, persistence, mobile settings mapping and session CLI arguments. No paid request or external browser launch.")
}
Task {do{try await run();exit(0)}catch{print("FAIL",error);exit(1)}}
app.run()

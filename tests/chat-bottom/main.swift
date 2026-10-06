import AppKit
import SwiftUI
import Vision
let app = NSApplication.shared
app.setActivationPolicy(.regular)
typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
func pressAccessible(_ label: String, in root: Any) -> Bool {
    guard let object = root as? NSObject else { return false }
    if object.responds(to: NSSelectorFromString("accessibilityLabel")),
       (object.value(forKey: "accessibilityLabel") as? String) == label,
       object.responds(to: NSSelectorFromString("accessibilityPerformPress")) {
        return object.perform(NSSelectorFromString("accessibilityPerformPress")) != nil || true
    }
    if object.responds(to: NSSelectorFromString("accessibilityChildren")),
       let kids = object.value(forKey: "accessibilityChildren") as? [Any] {
        for kid in kids where pressAccessible(label, in: kid) { return true }
    }
    return false
}

@MainActor func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], root.hasPrefix("/tmp/chatterbox-perf.") else { fatalError("isolated only") }
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotEmailWatch":false,"companionEnabled":false,"themeBackground":"black"], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let chat = model.activeSessions.filter { !$0.isDot }.max { $0.items.count < $1.items.count }!
    print("ITEMS", chat.items.count, "LAST", chat.items.last?.id.uuidString ?? "none")
    let window = NSWindow(contentRect: NSRect(x: 60,y:60,width:1300,height:900),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
    window.contentView = NSHostingView(rootView: ContentView().environment(model))
    window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
    try await Task.sleep(for:.seconds(2))
    model.showingHome=false; model.selectedID=chat.id
    try await Task.sleep(for:.seconds(4))
    func descendants(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(descendants) }
    func save(_ name:String) throws {
        if let im=capture(.null,8,UInt32(window.windowNumber),1|8)?.takeRetainedValue() {
            try NSBitmapImageRep(cgImage:im).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:ProcessInfo.processInfo.environment["FIND_OUT"]!+"/"+name+".png"))
        }
    }
    for scroll in descendants(window.contentView!).compactMap({$0 as? NSScrollView}) {
        print("SCROLL",scroll.frame,"DOC",scroll.documentView?.frame ?? .zero,"VISIBLE",scroll.documentVisibleRect)
        if let doc=scroll.documentView,doc.frame.height>2000 {
            doc.scroll(NSPoint(x:0,y:doc.isFlipped ? doc.frame.height-scroll.contentView.bounds.height : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    try await Task.sleep(for:.seconds(1));try save("bottom")
    chat.appendItem(DisplayItem(kind:.assistant,text:"BOTTOM REACHABILITY MARKER"))
    try await Task.sleep(for:.seconds(2));try save("appended")
    for scroll in descendants(window.contentView!).compactMap({$0 as? NSScrollView}) { print("AFTER",scroll.frame,"DOC",scroll.documentView?.frame ?? .zero,"VISIBLE",scroll.documentVisibleRect) }
    let shot = capture(.null,8,UInt32(window.windowNumber),1|8)!.takeRetainedValue()
    let request = VNRecognizeTextRequest()
    try VNImageRequestHandler(cgImage:shot).perform([request])
    let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:" ")
    guard recognized.contains("BOTTOM REACHABILITY MARKER") else { fatalError("Newest row is below reachable scroll range") }
    print("PASS newest row visible at bottom")
    var stopped = false
    chat.remoteCommand = nil
    chat.codexTurnID = nil
    chat.isRunning = true
    try await Task.sleep(for:.milliseconds(500))
    try save("stop")
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: ".", charactersIgnoringModifiers: ".", isARepeat: false, keyCode: 47)!
    window.makeKeyAndOrderFront(nil)
    let accepted = window.performKeyEquivalent(with: event)
    print("Stop shortcut accepted", accepted)
    try await Task.sleep(for:.milliseconds(300))
    guard chat.codexStopRequested else { fatalError("Stop shortcut did not reach session") }
    print("PASS Stop shortcut reaches session; no provider started")
    exit(0)
}
Task { @MainActor in do {try await run()}catch{print(error);exit(1)} }
app.run()

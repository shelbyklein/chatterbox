import AppKit
import SwiftUI
import ScreenCaptureKit
@testable import ChatterboxTestEngine
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-fast."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"keepMacAwake":false,"mobilePushConfigured":false],forName:UserDefaults.argumentDomain)
    let legacy = try JSONDecoder().decode(CodexSettings.self,from:Data("{\"folder\":\"/tmp\",\"canEdit\":false}".utf8))
    precondition(legacy.fastMode == nil)
    let model = AppModel()
    let session = model.newChat(backend:.codex)
    let request = try JSONDecoder().decode(Companion.SettingsRequest.self,from:Data("{\"fastMode\":true}".utf8))
    CompanionMapper.apply(request,to:session)
    precondition(session.record.codex?.fastMode == true)
    let saved = try JSONEncoder().encode(session.record)
    let restored = try JSONDecoder().decode(ConversationRecord.self,from:saved)
    precondition(restored.codex?.fastMode == true)
    precondition(session.settingsDescription.contains("Fast mode"))
    CompanionMapper.apply(.init(fastMode:false),to:session)
    precondition(session.record.codex?.fastMode == false)
    precondition(session.settingsDescription.contains("Standard speed"))
    print("PASS legacy decode, mobile request, persistence, on/off and settings feedback")
    session.setCodexFastMode(true)
    let panel=NSPanel(contentRect:NSRect(x:20,y:20,width:340,height:560),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.appearance=NSAppearance(named:.darkAqua)
    panel.contentView=NSHostingView(rootView:ChatSettingsCog(session:session).main.padding().background(Color.black))
    panel.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1))
    let cg=windowImage(panel)
    try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("fast-mode-cog.png"))
    panel.orderOut(nil)
    print("PASS rendered Golem Fast mode control")
}
Task {do {try await run();exit(0)}catch{print(error);exit(1)}}
app.run()

/// The window server's image of one of this process's own windows. Needs no screen-recording
/// permission, which ScreenCaptureKit now asks for even for your own windows.
func windowImage(_ window: NSWindow) -> CGImage {
    window.displayIfNeeded()
    typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
    guard let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { fatalError("Couldn't capture the test window") }
    return image
}

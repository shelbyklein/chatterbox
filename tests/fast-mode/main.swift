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
    let target=try await SCShareableContent.currentProcess.windows.first{$0.windowID==CGWindowID(panel.windowNumber)}!
    let config=SCStreamConfiguration();config.width=680;config.height=1120;config.ignoreShadowsSingleWindow=true
    let cg=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:target),configuration:config)
    try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("fast-mode-cog.png"))
    panel.orderOut(nil)
    print("PASS rendered Golem Fast mode control")
}
Task {do {try await run();exit(0)}catch{print(error);exit(1)}}
app.run()

import AppKit
import SwiftUI
import ScreenCaptureKit
@testable import ChatterboxTestEngine
@MainActor @Observable final class Driver {
    var modeRequest = 0
    var modelRequest = 0
    var directRequest = 0
}
struct Entry: View {
    let session: ChatSession
    let driver: Driver
    let edge: String
    let direct: Bool
    var body: some View {
        VStack {
            if edge == "bottom" { Spacer() }
            HStack {
                if edge != "left" { Spacer() }
                if direct {
                    ModelPicker(session:session,summary:"Model",color:.green,openRequest:driver.directRequest)
                } else {
                    ChatSettingsCog(session:session,modelRequest:driver.modelRequest,modeRequest:driver.modeRequest)
                }
                if edge == "left" { Spacer() }
            }.padding(20)
            if edge != "bottom" { Spacer() }
        }
    }
}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"keepMacAwake":false,"mobilePushConfigured":false,"themeBackground":"black"],forName:UserDefaults.argumentDomain)
    let model=AppModel()
    let session=model.ensureDot()
    session.setBackend(.codex)
    session.setCodexModel("gpt-6-astra")
    session.setCodexEffort("medium")
    session.setCodexFastMode(true)
    session.setMode("ask")
    try await CodexAppServer.shared.ensureStarted()
    try await CodexAppServer.shared.refreshModels()
    let original=session.record.codex!
    let originalMode = session.mode.id
    let originalBackend = session.record.backend
    func capture(_ label:String,_ host:NSWindow) async throws {
        try await Task.sleep(for:.milliseconds(650))
        guard let window=app.windows.first(where:{$0 !== host && $0.isVisible && $0.frame.width>250}) else {fatalError("No presented popover")}
        print(label,"window",window.frame,"fitting",window.contentView?.fittingSize ?? .zero)
        func dump(_ view:NSView,_ depth:Int) { if depth<4 {print(String(repeating:" ",count:depth),type(of:view),view.frame);view.subviews.forEach{dump($0,depth+1)}} }
        dump(window.contentView!,0)
        let image=windowImage(window)
        try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(label+".png"))
        precondition(session.record.codex==original && session.mode.id==originalMode && session.record.backend==originalBackend,"Presentation changed settings")
        precondition(window.contentView!.fittingSize == window.frame.size,"Popover fitting size differs from its window")
    }
    for (label,width,edge,direct) in [("wide",1100.0,"left",false),("narrow",420.0,"left",false),("right-edge",420.0,"right",false),("bottom-edge",420.0,"bottom",false),("direct",420.0,"left",true)] {
        let driver=Driver()
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:width,height:700),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.appearance=NSAppearance(named:.darkAqua)
        panel.contentView=NSHostingView(rootView:Entry(session:session,driver:driver,edge:edge,direct:direct))
        if edge=="right",let screen=NSScreen.main {panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-width,y:screen.visibleFrame.maxY-720))}
        else if edge=="bottom",let screen=NSScreen.main {panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.minX+100,y:screen.visibleFrame.minY))}
        else {panel.center()}
        panel.orderFrontRegardless()
        try await Task.sleep(for:.milliseconds(300))
        if direct {driver.directRequest += 1} else {driver.modeRequest += 1}
        if !direct {
            try await capture(label+"-settings",panel)
            driver.modelRequest += 1
        }
        try await capture(label+"-model",panel)
        if !direct {driver.modeRequest += 1;try await capture(label+"-return",panel)}
        panel.close()
        try await Task.sleep(for:.milliseconds(150))
    }
    CodexAppServer.shared.terminate()
    print("PASS settings preserved through actual cog page transitions and direct entry")
}
Task {do {try await run();exit(0)}catch{print("FAIL",error);exit(1)}}
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

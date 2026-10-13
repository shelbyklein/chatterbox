@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// The Automations panel with one automation open for editing: its agent, model and effort
// pickers. Evidence: panel.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
    precondition(root.hasPrefix("/tmp/chatterbox-automations-panel."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotEmailWatch":false,"companionEnabled":false],forName:UserDefaults.argumentDomain)
    let folder=root+"/sdhq"
    var wordpress=ProjectAutomation(projectFolder:folder,title:"WordPress updates",template:.wordpress,instructions:ProjectAutomations.wordpressInstructions,weekday:2,hour:9)
    wordpress.backend="claude";wordpress.effort="high"
    try ProjectAutomations.save([wordpress])
    let model=AppModel()
    let window=NSWindow(contentRect:NSRect(x:80,y:80,width:640,height:700),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua)
    window.contentView=NSHostingView(rootView:AutomationsSheet(projectFolder:folder,projectName:"SDHQ",initiallyEditing:wordpress.id).environment(model).environment(\.colorScheme,.dark))
    window.orderFrontRegardless()
    try await Task.sleep(for:.seconds(1.5))
    let view=window.contentView!;view.layoutSubtreeIfNeeded()
    let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("panel.png"))
    print("PASS automations panel renders with its model pickers. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

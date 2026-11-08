@testable import Chatterbox
import AppKit
import SwiftUI
// The Mac's pressure indicator (MacPressureViews.swift): the toolbar's dot at OK, "Mac busy" and
// "Mac overloaded"; the readings popover; the menu bar panel's row. No agents run.
// Evidence: pressure-*.png in the data folder.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
func reading(_ level:String) -> Companion.Pressure {
    let busy=level=="busy",over=level=="overloaded"
    return Companion.Pressure(level:level,since:Date(timeIntervalSince1970:1_800_000_000),updatedAt:Date(),updated:Int(Date().timeIntervalSince1970),
        summary:over ? "load 52 on 16 cores (over 3\u{00D7}) for 1 min; swap grew 1.4 GB in 5 min" : busy ? "load 30 on 16 cores (over 1.5\u{00D7}) for 2 min" : "load 6.0 on 16 cores, memory normal, swap 1.0 GB, thermal nominal",
        reasons:[],memory:over ? "warning" : "normal",swapUsedGB:over ? 6.2 : 1.0,swapGrowthGB:over ? 1.4 : 0,compressedGB:over ? 27 : 3.1,
        load1:over ? 52 : busy ? 30 : 6,load5:over ? 40 : busy ? 26 : 6,load15:over ? 31 : busy ? 20 : 5,cores:16,thermal:"nominal",
        holding:over ? PressureNames.over : busy ? PressureNames.busy : [],waiting:over || busy ? 2 : 0,cpuPercent:over ? 91 : busy ? 72 : 12)
}
enum PressureNames {
    static let busy=["Builds run one at a time; agents' builds get a quarter of the cores, at lower priority","Simulators idle 5 minutes are shut down","New work threads wait to start until the Mac is OK","2 work threads waiting"]
    static let over=["New builds wait (running ones carry on, at lower priority)","Simulators no build or test is using are shut down","Work threads don't start their next turn; new ones wait to start","2 work threads waiting"]
}
@MainActor func render<V:View>(_ view:V,_ name:String,_ root:URL,width:CGFloat?=nil) async throws -> NSSize {
    let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:width ?? 300,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    panel.appearance=NSAppearance(named:.darkAqua)
    panel.contentView=NSHostingView(rootView:view.environment(\.colorScheme,.dark).padding(10).background(Color(white:0.14)).fixedSize())
    panel.orderFrontRegardless()
    try await Task.sleep(for:.milliseconds(500))
    let host=panel.contentView!;host.layoutSubtreeIfNeeded()
    let size=host.fittingSize
    host.frame=NSRect(origin:.zero,size:size)
    let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("pressure-\(name).png"))
    panel.orderOut(nil)
    return size
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-mac-pressure."))
    UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
    let model=MacPressureModel.shared
    var fails=0
    func check(_ ok:Bool,_ what:String){print(ok ? "PASS \(what)" : "FAIL \(what)");if !ok {fails+=1}}
    // Nothing yet (an older service): the toolbar item takes no room.
    model.show(nil)
    let empty=try await render(MacPressureBadge(),"none",root)
    check(empty.width<=24,"no reading: the badge takes no room (\(empty))")
    model.show(reading("ok"))
    let ok=try await render(MacPressureBadge(),"toolbar-ok",root)
    model.show(reading("busy"))
    let busy=try await render(MacPressureBadge(),"toolbar-busy",root)
    model.show(reading("overloaded"))
    let over=try await render(MacPressureBadge(),"toolbar-overloaded",root)
    check(ok.width<busy.width && busy.width<over.width,"OK shows its load reading; Busy and Overloaded add their label (\(ok.width), \(busy.width), \(over.width))")
    check(reading("busy").label=="Mac busy" && reading("overloaded").label=="Mac overloaded" && reading("ok").label=="Mac OK","labels")
    let details=try await render(MacPressureDetails(pressure:reading("overloaded")).frame(width:320),"popover-overloaded",root,width:340)
    check(details.height>150,"the popover lists readings and what's held back (\(details))")
    _=try await render(MacPressureDetails(pressure:reading("busy")).frame(width:320),"popover-busy",root,width:340)
    // The menu bar panel, with its row.
    let app=AppModel()
    model.show(reading("busy"))
    _=try await render(MenuBarPanel(model:app),"menu-bar-busy",root)
    model.show(reading("ok"))
    _=try await render(MenuBarPanel(model:app),"menu-bar-ok",root)
    if fails>0 {throw NSError(domain:"mac-pressure",code:fails)}
    print("PASS pressure indicator renders. Evidence: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

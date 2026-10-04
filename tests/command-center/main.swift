@testable import Chatterbox
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-command-center."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"nextStepsEnabled":false],forName:UserDefaults.argumentDomain)
    let suite="CommandCenterFixture-"+UUID().uuidString
    let defaults=UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let model=AppModel()
    func thread(_ name: String, _ backend: Backend) throws -> ChatSession {
        let folder=root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var record=ConversationRecord(model:backend == .codex ? "gpt-6.1-sol" : "opus",effort:"medium",personality:.pragmatic)
        record.title=name;record.projectNickname=name;record.projectFolder=folder.path;record.activeBackend=backend
        record.items=[DisplayItem(kind:.user,text:"Can we review the latest update?",agent:backend),DisplayItem(kind:.assistant,text:"The latest update is ready for review. Your original files and conversation are preserved.\n\nWe can check the details here while the other project stays open beside it.",phase:.final)]
        return model.insertSession(record)
    }
    let first=try thread("Chatterbox",.codex), second=try thread("SDHQ",.claude), third=try thread("Galley",.codex)
    let fourth=try thread("PlayCase",.claude)
    first.draft="Chatterbox draft";second.draft="SDHQ draft"
    let layout=CommandCenterLayout(defaults:defaults)
    let slotA=layout.add(first.id), slotB=layout.add(second.id)
    precondition(layout.add(first.id)==slotA && layout.slots.count==2)
    precondition(!layout.replace(slotA,with:second.id),"Duplicate live session accepted")
    layout.columns=3;layout.tileHeight=560
    let reloaded=CommandCenterLayout(defaults:defaults)
    precondition(reloaded.slots==layout.slots && reloaded.columns==3 && reloaded.tileHeight==560)
    precondition(CommandCenterLayout.fittingColumns(requested:4,width:640)==1)
    precondition(CommandCenterLayout.fittingColumns(requested:4,width:1200)==2)
    precondition(CommandCenterLayout.fittingColumns(requested:4,width:1800)==4)
    let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
    let original=try encoder.encode(first.record), originalSecond=try encoder.encode(second.record)
    layout.columns=2;layout.activeID=slotA
    model.selectedID=first.id;model.showingCommandCenter=true
    let panel=NSPanel(contentRect:NSRect(x:40,y:90,width:1200,height:760),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    panel.makeKeyAndOrderFront(nil)
    var globalOrigin=CGPoint.zero
    func render(_ width: CGFloat, _ height: CGFloat, _ name: String, _ dark: Bool=true) async throws {
        CommandCenterDebug.tiles=[:]
        panel.setContentSize(NSSize(width:width,height:height))
        panel.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
        panel.contentView=NSHostingView(rootView:ContentView(commandCenter:layout).environment(model).environment(\.colorScheme,dark ? .dark : .light)
            .onGeometryChange(for:CGPoint.self) { $0.frame(in:.global).origin } action: { globalOrigin=$0 })
        try await Task.sleep(for:.milliseconds(600))
        let view=panel.contentView!;view.layoutSubtreeIfNeeded()
        let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
    }
    func editors(_ view: NSView) -> [NSTextView] {
        var result:[NSTextView]=[]
        if let editor=view as? NSTextView, editor.isEditable, editor.accessibilityLabel()=="Message" { result.append(editor) }
        for child in view.subviews { result += editors(child) }
        return result
    }
    func click(_ rect: CGRect, window: NSWindow?=nil) async throws {
        let target=window ?? panel
        let origin=window == nil ? globalOrigin : CommandCenterDebug.chooserOrigin
        let height=target.contentView!.bounds.height
        let point=NSPoint(x:rect.midX-origin.x,y:height-(rect.midY-origin.y))
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            app.postEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:target.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!,atStart:false)
        }
        try await Task.sleep(for:.milliseconds(250))
    }
    try await render(1200,760,"wide")
    let activeBeforeMove=layout.activeID
    precondition(!layout.move(slotA,by:-1),"Moved beyond first slot")
    try await click(CommandCenterDebug.moveEarlier[second.id]!)
    precondition(layout.slots.map(\.id)==[slotB,slotA] && layout.activeID==activeBeforeMove,"Arrow reorder changed active chat or failed")
    precondition(CommandCenterLayout(defaults:defaults).slots==layout.slots,"Reorder did not persist")
    precondition(first.draft=="Chatterbox draft" && second.draft=="SDHQ draft" && (try! encoder.encode(first.record))==original,"Reorder changed conversation/draft")
    try await render(1200,760,"reordered")
    try await click(CommandCenterDebug.moveEarlier[first.id]!)
    precondition(layout.slots.map(\.id)==[slotA,slotB],"Move back failed")
    let boxes=editors(panel.contentView!)
    precondition(boxes.count==2,"Expected two independent native composers")
    let left=boxes.first {$0.string=="Chatterbox draft"}!, right=boxes.first {$0.string=="SDHQ draft"}!
    panel.makeFirstResponder(left)
    try await Task.sleep(for:.milliseconds(200))
    precondition(layout.activeID==slotA,"Left composer did not activate its own tile")
    left.setSelectedRange(NSRange(location:left.string.utf16.count,length:0));left.insertText(" A",replacementRange:left.selectedRange())
    try await Task.sleep(for:.milliseconds(150))
    precondition(first.draft=="Chatterbox draft A" && second.draft=="SDHQ draft")
    panel.makeFirstResponder(right)
    try await Task.sleep(for:.milliseconds(200))
    precondition(layout.activeID==slotB && panel.firstResponder===right,"Right focus was stolen by another tile")
    right.setSelectedRange(NSRange(location:right.string.utf16.count,length:0));right.insertText(" B",replacementRange:right.selectedRange())
    try await Task.sleep(for:.milliseconds(200))
    precondition(first.draft=="Chatterbox draft A" && second.draft=="SDHQ draft B")
    let staleReturn=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
    left.keyDown(with:staleReturn)
    try await Task.sleep(for:.milliseconds(150))
    precondition(first.draft=="Chatterbox draft A" && first.items.count==2,"Inactive keyboard submit sent or cleared another draft")
    precondition((try! encoder.encode(first.record))==original && (try! encoder.encode(second.record))==originalSecond,"Typing mutated transcript")
    // Native switch button opens the real project/thread chooser without selecting a main chat.
    try await click(CommandCenterDebug.switches[first.id]!)
    try await Task.sleep(for:.milliseconds(350))
    guard let sheet=panel.attachedSheet else {fatalError("Switch did not open native chooser sheet")}
    let content=sheet.contentView!;content.layoutSubtreeIfNeeded()
    let rep=content.bitmapImageRepForCachingDisplay(in:content.bounds)!
    content.cacheDisplay(in:content.bounds,to:rep)
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("chooser.png"))
    try await click(CommandCenterDebug.choices[third.id]!,window:sheet)
    precondition(layout.slots.first(where: {$0.id==slotA})?.sessionID==third.id,"Native chooser did not switch thread")
    try await Task.sleep(for:.milliseconds(350))
    precondition(first.draft=="Chatterbox draft A" && second.draft=="SDHQ draft B")
    precondition((try! encoder.encode(first.record))==original && first.record.archivedAt==nil)
    try await render(1200,760,"switched")
    try await click(CommandCenterDebug.removes[third.id]!)
    precondition(layout.slots.count==1 && layout.slots.first?.sessionID==second.id,"Native remove tile failed")
    precondition(third.record.archivedAt==nil && model.sessions.contains {$0.id==third.id},"Tile removal archived/deleted thread")
    layout.add(first.id)
    try await render(640,900,"narrow",false)
    for id in [first.id,second.id] {
        if let frame=CommandCenterDebug.tiles[id] {precondition(frame.minX>=globalOrigin.x && frame.maxX<=globalOrigin.x+640,"Clipped narrow tile")}
    }
    precondition(first.draft=="Chatterbox draft A" && second.draft=="SDHQ draft B")
    layout.singleRow=true
    try await render(1200,900,"single-row-two-chats")
    layout.singleRow=false
    try await render(1200,760,"before-add")
    try await click(CommandCenterDebug.add)
    try await Task.sleep(for:.milliseconds(350))
    guard let addSheet=panel.attachedSheet else {fatalError("Add chat did not open chooser")}
    try await click(CommandCenterDebug.choices[fourth.id]!,window:addSheet)
    precondition(layout.slots.count==3 && layout.slots.contains {$0.sessionID==fourth.id},"Native Add chat failed")
    layout.add(third.id);layout.columns=2;layout.tileHeight=420
    try await render(1200,1030,"four-chats")
    precondition(editors(panel.contentView!).count==4,"Four-chat grid lost composers")
    layout.singleRow=true
    try await render(1200,900,"single-row")
    let frames=CommandCenterDebug.tiles
    precondition(frames.count==4)
    let top=frames[first.id]!.minY
    for frame in frames.values {
        precondition(abs(frame.minY-top)<1 && frame.height>750,"Single row did not fill height")
    }
    precondition(CommandCenterLayout(defaults:defaults).singleRow,"Single row preference lost")
    try await render(640,900,"single-row-narrow",false)
    precondition(CommandCenterDebug.tiles[first.id]!.width>=400,"Single row squeezed chat width")
    layout.singleRow=false
    let restored=CommandCenterLayout(defaults:defaults)
    precondition(restored.slots==layout.slots)
    restored.reconcile(available:[first.id])
    precondition(restored.slots.map(\.sessionID)==[first.id])
    model.showingHome=true;precondition(!model.showingCommandCenter)
    model.showingCommandCenter=true;precondition(!model.showingHome)
    model.selectedID=first.id;precondition(!model.showingCommandCenter)
    panel.orderOut(nil)
    print("PASS: persistence/uniqueness/adaptive grid, two native composers/focus/isolated drafts, native switch sheet and removal, thread histories retained. Proof: \(root.path)")
}
Task { @MainActor in do {try await run();exit(0)} catch {print("FAIL: \(error)");exit(1)} }
app.run()

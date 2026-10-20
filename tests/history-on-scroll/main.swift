@testable import Chatterbox
import AppKit
import SwiftUI
import ScreenCaptureKit
// A long chat opens with only its newest rows and loads earlier ones only on a click;
// and a chat's "waiting on you" check follows questions and approvals as they're answered,
// added, or moved by a row inserted before them; and a chat's thumbnail stays when the part
// of the chat the app holds has no image in it.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
var failures=0
func check(_ ok:Bool,_ what:String) { print((ok ? "PASS " : "FAIL ")+what); if !ok { failures+=1 } }
@MainActor func run() async throws {
    let model=AppModel()
    // Waiting-on-you follows its rows.
    var waiting=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    waiting.title="Waiting"
    waiting.items=(0..<50).map { DisplayItem(kind: $0 % 2 == 0 ? .user : .assistant, text:"Row \($0)") }
    let w=model.insertSession(waiting)
    check(!w.isWaitingOnYou,"no request, not waiting")
    let question=DisplayItem(kind:.questions,text:"Choose",approvalState:.pending)
    w.record.items.append(question)
    check(w.isWaitingOnYou && w.pendingRequests.map(\.id)==[question.id],"a new question waits")
    w.record.items.insert(DisplayItem(kind:.user,text:"Inserted"),at:3)
    check(w.pendingRequests.map(\.id)==[question.id],"a row inserted earlier doesn't lose the question")
    let index=w.record.items.firstIndex { $0.id==question.id }!
    w.record.items[index].approvalState = .approved
    check(!w.isWaitingOnYou,"an answered question stops waiting")
    w.record.items.removeLast()
    w.record.items.append(DisplayItem(kind:.approval,text:"Approve",approvalState:.pending))
    check(w.isWaitingOnYou,"a replaced last row is seen")
    w.record.items=[]
    check(!w.isWaitingOnYou,"a cleared chat isn't waiting")

    // A message sent through the service shows at once, until the service's row replaces it.
    var sent=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic);sent.title="Sent"
    let q=model.insertSession(sent)
    var commands:[String]=[]
    q.remoteCommand={ op,_ in commands.append(op) }
    q.send("  Make the logo bigger  ")
    check(commands==["send"] && q.items.last?.text=="Make the logo bigger" && q.items.last?.kind == .user,"a sent message shows at once")
    q.send("Make the logo bigger")
    check(q.items.filter { $0.text=="Make the logo bigger" }.count==2,"the same text sent twice shows twice")
    var fromService=q.record;fromService.items=[]           // a refresh from before the service added them
    q.record=fromService;q.keepSentEchoes()
    check(q.items.filter { $0.text=="Make the logo bigger" }.count==2,"an earlier refresh doesn't drop them")
    fromService.items=[DisplayItem(kind:.user,text:"Make the logo bigger")]
    q.record=fromService;q.keepSentEchoes()
    check(q.items.filter { $0.text=="Make the logo bigger" }.count==2 && q.sentEchoes.count==1,"the service's first row replaces the first, the second still shows")
    fromService.items.append(DisplayItem(kind:.user,text:"Make the logo bigger"))
    q.record=fromService;q.keepSentEchoes()
    check(q.items.count==2 && q.sentEchoes.isEmpty,"both replaced, none doubled")
    q.send("!ls")
    check(q.items.count==2,"a ! command isn't shown as a message")

    // A thumbnail is remembered past the rows that held it.
    let png=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!).appendingPathComponent("shot.png")
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:4,pixelsHigh:4,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    try rep.representation(using:.png,properties:[:])!.write(to:png)
    var pictured=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    pictured.title="Pictured"
    var withImage=DisplayItem(kind:.user,text:"Here")
    withImage.attachments=[Attachment(name:"shot.png",path:png.path,mediaType:"image/png",kind:.image)]
    pictured.items=[withImage]
    let p=model.insertSession(pictured)
    check(p.latestThumbnailURL()?.path==png.path,"the image is found")
    p.record.items=[DisplayItem(kind:.assistant,text:"Only the newest rows, no image")]
    check(p.latestThumbnailURL()?.path==png.path,"the thumbnail stays when the held rows have no image")
    try FileManager.default.removeItem(at:png)
    p.record.items.append(DisplayItem(kind:.user,text:"Later"))
    check(p.latestThumbnailURL()==nil,"a deleted image's thumbnail goes")

    // Reaching the top waits for an explicit click, even with a full legacy transcript.
    var long=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
    long.title="Long chat"
    long.items=(0..<400).map { i in
        i % 2 == 0 ? DisplayItem(kind:.user,text:"Question \(i)") : DisplayItem(kind:.assistant,text:"Answer \(i): "+String(repeating:"Some words in a paragraph. ",count:6))
    }
    let session=model.insertSession(long)
    let window=NSWindow(contentRect:NSRect(x:40,y:60,width:900,height:800),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false
    let host=NSHostingView(rootView:ChatView(session:session).environment(model))
    window.contentView=host;window.orderFrontRegardless()
    func all(_ v:NSView)->[NSScrollView]{ (v as? NSScrollView).map{[$0]} ?? [] + v.subviews.flatMap(all) }
    // The transcript: the scroll view with the tallest content.
    func find(_ v:NSView)->NSScrollView?{ all(v).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) } }
    try await Task.sleep(for:.seconds(1.5))
    guard let scroll=find(host) else { check(false,"transcript scroll view found"); exit(1) }
    let opened=scroll.documentView!.frame.height
    try await Task.sleep(for:.seconds(1))
    check(abs(scroll.documentView!.frame.height-opened)<1,"history doesn't grow on its own after opening (\(Int(opened)) pt)")
    let atBottom=scroll.contentView.bounds.maxY >= scroll.documentView!.frame.height-2
    check(atBottom,"opens at the newest message (visible \(Int(scroll.contentView.bounds.minY))–\(Int(scroll.contentView.bounds.maxY)) of \(Int(scroll.documentView!.frame.height)), flipped \(scroll.documentView!.isFlipped), insets \(scroll.contentInsets))")
    scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
    try await Task.sleep(for:.seconds(1.5))
    let grown=scroll.documentView!.frame.height
    check(abs(grown-opened)<1,"scrolling to the top doesn't load older rows (\(Int(opened)) → \(Int(grown)) pt)")
    // A direct native click also covers the full-width button's hit region. Bare
    // NSHostingView fixtures do not consistently publish SwiftUI's AX children.
    let point = scroll.documentView!.convert(NSPoint(x:scroll.documentView!.bounds.midX,y:34),to:nil)
    for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
        let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
            windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        window.sendEvent(event)
    }
    try await Task.sleep(for:.seconds(1))
    let expanded = scroll.documentView!.frame.height
    check(expanded>opened+500 && expanded<opened*2.5,"one click reveals one small chunk (\(Int(opened)) → \(Int(expanded)) pt)")
    check(abs(scroll.contentView.bounds.minY-(expanded-opened))<80,"loading earlier keeps the previously top message in view")
    scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
    try await Task.sleep(for:.seconds(1))
    check(abs(scroll.documentView!.frame.height-expanded)<1,"reaching the top again waits for another click")
    if #available(macOS 14.4, *), let path = ProcessInfo.processInfo.environment["HISTORY_CAPTURE"] {
        let target = try await SCShareableContent.currentProcess.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
        let config = SCStreamConfiguration(); config.width = 900; config.height = 800; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
        try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
    }
    // At the newest message, the agent starting (typing dots) keeps the bottom in view.
    let doc=scroll.documentView!
    scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,doc.frame.height-scroll.contentView.bounds.height)));scroll.reflectScrolledClipView(scroll.contentView)
    try await Task.sleep(for:.seconds(1))
    // As sending does: the message, then the agent starting.
    session.record.items.append(DisplayItem(kind:.user,text:"One more thing"))
    try await Task.sleep(for:.seconds(1))
    session.isRunning=true
    try await Task.sleep(for:.seconds(1.5))
    let gap=doc.frame.height-scroll.contentView.bounds.maxY
    check(gap<4,"the typing dots stay in view when the agent starts (\(Int(gap)) pt below)")
    session.isRunning=false
    window.orderOut(nil)
    print(failures==0 ? "PASS explicit history loading" : "FAIL \(failures) checks")
    exit(failures==0 ? 0 : 1)
}
Task { @MainActor in do {try await run()} catch {print(error);exit(1)} }
app.run()

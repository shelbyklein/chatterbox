@testable import Chatterbox
import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
setbuf(stdout, nil)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-mini-ack."))
    UserDefaults.standard.setVolatileDomain([
        "dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,
        "companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,
        GolemMiniWindow.collapsedKey:false
    ],forName:UserDefaults.argumentDomain)
    let model = AppModel(), dot = model.ensureDot()
    dot.setTitle("Golem")
    dot.draft = "Keep my unsent draft"
    let attachment = Attachment(name:"draft.txt",path:root.appendingPathComponent("draft.txt").path,mediaType:"text/plain",kind:.text)
    dot.draftAttachments = [attachment]
    let reply = DisplayItem(kind:.assistant,text:"The preview is ready. Hover me, then leave to acknowledge this reply.",phase:.final)
    dot.appendItem(reply)
    model.showingDot = true
    let mini = model.dotMiniWindow!, panel = mini.panel!
    panel.setFrame(NSRect(x:40,y:80,width:400,height:420),display:true)
    try await Task.sleep(for:.milliseconds(600))
    let count = dot.items.count
    func pause() async throws {try await Task.sleep(for:.milliseconds(250))}
    mini.replyHoverChanged(inside:false,replyID:reply.id)
    try await pause()
    precondition(!mini.collapsed,"Unhovered reply was dismissed")
    mini.replyHoverChanged(inside:true,replyID:reply.id)
    mini.replyHoverChanged(inside:false,replyID:reply.id)
    try await Task.sleep(for:.milliseconds(80))
    mini.replyHoverChanged(inside:true,replyID:reply.id)
    try await pause()
    precondition(!mini.collapsed,"Reentry did not cancel acknowledgement")
    mini.replyHoverChanged(inside:false,replyID:reply.id)
    dot.isRunning = true
    try await pause()
    precondition(!mini.collapsed,"Running response was acknowledged")
    dot.isRunning = false
    var question = DisplayItem(kind:.questions,text:"Which option?",phase:.final)
    question.approvalState = .pending
    dot.appendItem(question)
    mini.replyHoverChanged(inside:true,replyID:reply.id)
    mini.replyHoverChanged(inside:false,replyID:reply.id)
    try await pause()
    precondition(!mini.collapsed,"Unanswered question was dismissed")
    dot.record.items.removeAll {$0.id==question.id}
    mini.replyHoverChanged(inside:true,replyID:reply.id)
    mini.replyHoverChanged(inside:false,replyID:reply.id)
    let newReply = DisplayItem(kind:.assistant,text:"A new response must be hovered before acknowledgement.",phase:.final)
    dot.appendItem(newReply)
    try await pause()
    precondition(!mini.collapsed,"Unseen newer reply was acknowledged")
    print("PASS no hover, reentry, running response, question and newer reply protection")
    // Exercise the actual SwiftUI hover entry point with native cursor events.
    let original = NSEvent.mouseLocation
    defer {
        let screen = NSScreen.screens.first!
        CGWarpMouseCursorPosition(CGPoint(x:original.x,y:screen.frame.maxY-original.y))
    }
    func move(_ point:NSPoint) async throws {
        let screen = NSScreen.screens.first!
        let location = CGPoint(x:point.x,y:screen.frame.maxY-point.y)
        CGWarpMouseCursorPosition(location)
        CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:location,mouseButton:.left)?.post(tap:.cghidEventTap)
        try await Task.sleep(for:.milliseconds(100))
    }
    func capture(_ name:String) {
        typealias Fn = @convention(c) (CGRect,UInt32,UInt32,UInt32)->Unmanaged<CGImage>?
        let sym = dlsym(UnsafeMutableRawPointer(bitPattern:-2),"CGWindowListCreateImage")!
        let fn = unsafeBitCast(sym,to:Fn.self)
        let image = fn(.null,1<<3,UInt32(panel.windowNumber),(1<<0)|(1<<3))!.takeRetainedValue()
        try! NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
    }
    try await move(NSPoint(x:600,y:80))
    try await pause()
    try await move(NSPoint(x:panel.frame.midX,y:panel.frame.minY+300))
    try await move(NSPoint(x:panel.frame.midX,y:panel.frame.minY+105))
    try await move(NSPoint(x:panel.frame.midX,y:panel.frame.minY+37))
    try await pause()
    precondition(!mini.collapsed,"Movement from body to composer dismissed chat")
    capture("before-exit")
    try await move(NSPoint(x:600,y:80))
    try await Task.sleep(for:.milliseconds(600))
    precondition(mini.collapsed,"Actual native hover exit did not collapse mini")
    precondition(Attention.shared.dotSeenItem == newReply.id,"Reply not marked seen")
    precondition(dot.draft=="Keep my unsent draft" && dot.draftAttachments==[attachment] && dot.items.count==count+1,"Draft, attachment or transcript changed")
    capture("after-exit")
    print("PASS actual bubble/body/composer hover, exit collapse, seen marker, draft/attachment and transcript preserved")
    model.showingDot = false
}
Task {do {try await run();exit(0)} catch {print(error);exit(1)}}
app.run()

@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// A reply's ```actions block: buttons that only send text, live only on the newest reply.
// Evidence: mac-ship-button.png (live) and mac-ship-button-used.png (after the tap).
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
func check(_ ok:Bool,_ text:String){ if !ok {print("FAIL: \(text)");exit(1)}; print("PASS: \(text)") }

/// The transcript as ChatView shows it, with the resolver ChatView sets.
struct Transcript: View {
 @Binding var items:[DisplayItem]
 var body: some View {
  VStack(alignment:.leading,spacing:14) {
   ForEach(items) { ItemView(item:$0) }
  }
  .environment(\.replyActionResolver, ReplyActionResolver(items:items, send: { text in items.append(DisplayItem(kind:.user,text:text)) }, tint: ReaderStyle.defaults.color(for: .claude)))
 }
}

/// Just the newest reply's buttons, live from the transcript, for clicking.
struct Buttons: View {
 @Binding var items:[DisplayItem]
 let reply:UUID
 var body: some View {
  MarkdownText(text:"```actions\nShip to the real app | ship\nStart the next part | start the next part\n```")
   .environment(\.replyActions, ReplyActionResolver(items:items) { text in items.append(DisplayItem(kind:.user,text:text)) }.context(for:reply))
 }
}

@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-reply-actions."))
 // Parsing.
 let parsed=ReplyActions.parse("Ship to the real app | ship\n\n- Force restart | restart now\nStart the next part\n | nothing\n")
 check(parsed==[ReplyAction(label:"Ship to the real app",message:"ship"),ReplyAction(label:"Force restart",message:"restart now"),
                ReplyAction(label:"Start the next part",message:"Start the next part")],"label | message lines; a bare line is both; blank and label-less lines skipped")
 check(ReplyActions.parse((1...9).map{"B\($0)"}.joined(separator:"\n")).count==ReplyActions.limit,"at most \(ReplyActions.limit) buttons")
 check(MarkdownText.blocks("Done.\n\n```actions\nShip | ship\n```").contains { if case .code(_, let language, true)=$0 {return language=="actions"}; return false },"an actions fence is a closed code block")
 // State: live on the newest reply; used once a message followed; stale after another reply.
 check(ReplyActions.state(following:[ReplyActions.Turn]())==ReplyActions.State.live,"nothing after: live")
 check(ReplyActions.state(following:[ReplyActions.Turn.other,.user(" ship\n")])==ReplyActions.State.used("ship"),"a message after: used, with what was sent")
 check(ReplyActions.state(following:[ReplyActions.Turn.reply,.user("ship")])==ReplyActions.State.stale,"another reply after: stale")
 let older=DisplayItem(kind:.assistant,text:"Built.\n\n```actions\nInstall to Dev | install\n```",phase:.final)
 let reply="Installed to Chatterbox Dev and restarted its service. Try it there; when it's right:\n\n```actions\nShip to the real app | ship\nStart the next part | start the next part\n```"
 let newest=DisplayItem(kind:.assistant,text:reply,phase:.final)
 var items=[DisplayItem(kind:.user,text:"Build the Desk toggle"),older,DisplayItem(kind:.user,text:"looks good, install it"),
            DisplayItem(kind:.user,text:"(work thread result)",automatic:true),newest]
 var sent:[String]=[]
 let resolver=ReplyActionResolver(items:items) { sent.append($0) }
 check(resolver.context(for:newest.id)?.state==ReplyActions.State.live,"the newest reply's buttons are live")
 check(resolver.context(for:older.id)?.state==ReplyActions.State.used("looks good, install it"),"an older reply's are used (Shelby typed something else)")
 resolver.context(for:newest.id)?.send("ship")
 check(sent==["ship"],"a button only sends its text")
 // Rendered: live, then tapped through accessibility (as a click would), then greyed with a tick.
 var shown=items
 let binding=Binding(get:{shown},set:{shown=$0})
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:660,height:420),styleMask:[.titled],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 func host() { panel.contentView=NSHostingView(rootView:Transcript(items:binding).padding(20).frame(width:660,alignment:.topLeading).background(Color(white:0.1)).environment(\.colorScheme,.dark)) }
 host()
 panel.orderFrontRegardless()
 func snap(_ name:String) async throws {
  try await Task.sleep(for:.milliseconds(700))
  let view=panel.contentView!;view.layoutSubtreeIfNeeded()
  let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:rendered)
  try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(name))
 }
 try await snap("mac-ship-button.png")
 // The tap: a real click on the Ship button, the buttons alone at a known spot.
 let tap=NSPanel(contentRect:NSRect(x:40,y:600,width:420,height:80),styleMask:[.borderless],backing:.buffered,defer:false)
 tap.contentView=NSHostingView(rootView:Buttons(items:binding,reply:newest.id).padding(.leading,10).padding(.top,10).frame(width:420,height:80,alignment:.topLeading))
 tap.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(500))
 for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
  tap.sendEvent(NSEvent.mouseEvent(with:type,location:NSPoint(x:30,y:80-22),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                                   windowNumber:tap.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!)
  try await Task.sleep(for:.milliseconds(80))
 }
 try await Task.sleep(for:.milliseconds(300))
 check(shown.last?.kind == .user && shown.last?.text=="ship","clicking Ship sends \u{201C}ship\u{201D} into the thread as Shelby's message")
 check(shown.count==items.count+1,"once")
 tap.close()
 host()
 try await snap("mac-ship-button-used.png")
 items=shown
 check(ReplyActionResolver(items:items){_ in}.context(for:newest.id)?.state==ReplyActions.State.used("ship"),"the tapped reply is used, Ship ticked")
 panel.close()
 print("PASS rendered. Evidence: \(root)/mac-ship-button.png, mac-ship-button-used.png")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

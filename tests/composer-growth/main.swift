@testable import Chatterbox
import AppKit
import SwiftUI
// The message box with text taller than its limit, and with text right at the limit, with
// legacy (always shown) scroll bars: its height must settle, not keep changing.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
struct Box: View {
    @State var text: String
    let maxHeight: CGFloat
    @State var focused=true
    var body: some View {
        // As in the chat: buttons either side share the row, so the box's width is negotiated.
        HStack(alignment: .bottom, spacing: 12) {
            Image(systemName: "paperclip").frame(height: 36)
            ComposerBox(text:$text,placeholder:"Message",isFocused:$focused,maxHeight:maxHeight){}
                .padding(.vertical, 9).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            Image(systemName: "mic").frame(height: 36)
            Image(systemName: "arrow.up.circle.fill").font(.title).frame(height: 36)
        }
        .padding(.horizontal, 20).frame(maxWidth: 760).padding(10).background(Color(white:0.12))
    }
}
@MainActor var kept:[NSWindow]=[]
@MainActor func heights(_ text:String,max:CGFloat) async throws -> [CGFloat] {
    let window=NSWindow(contentRect:NSRect(x:40,y:60,width:560,height:800),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false
    let host=NSHostingView(rootView:Box(text:text,maxHeight:max))
    window.contentView=host
    window.orderFrontRegardless()
    func scroll(_ v:NSView)->NSScrollView?{ if let s=v as? NSScrollView {return s}; for c in v.subviews { if let s=scroll(c) {return s} }; return nil }
    try await Task.sleep(for:.milliseconds(200))
    scroll(host)?.scrollerStyle = .legacy
    var seen:[CGFloat]=[]
    for _ in 0..<40 { try await Task.sleep(for:.milliseconds(50)); host.layoutSubtreeIfNeeded(); seen.append(scroll(host)?.frame.height ?? -1) }
    window.orderOut(nil);kept.append(window)
    return seen
}
/// Types into the box the way a person does, recording the box's height after each key.
@MainActor func typing(_ start:String,_ extra:String,max:CGFloat) async throws -> [CGFloat] {
    let window=NSWindow(contentRect:NSRect(x:40,y:60,width:800,height:900),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false
    let host=NSHostingView(rootView:Box(text:start,maxHeight:max))
    window.contentView=host;window.makeKeyAndOrderFront(nil)
    func find<T:NSView>(_ v:NSView,_ t:T.Type)->T?{ if let x=v as? T {return x}; for c in v.subviews { if let x=find(c,t) {return x} }; return nil }
    try await Task.sleep(for:.milliseconds(300))
    let scroll=find(host,NSScrollView.self)!;scroll.scrollerStyle = .legacy
    let text=find(host,NSTextView.self)!
    window.makeFirstResponder(text);text.setSelectedRange(NSRange(location:(text.string as NSString).length,length:0))
    var seen:[CGFloat]=[]
    for ch in extra {
        text.insertText(String(ch),replacementRange:text.selectedRange())
        for _ in 0..<3 { try await Task.sleep(for:.milliseconds(16)); seen.append(scroll.frame.height) }
    }
    for _ in 0..<30 { try await Task.sleep(for:.milliseconds(30)); seen.append(scroll.frame.height) }
    window.orderOut(nil);kept.append(window)
    return seen
}
/// A height that goes up then down then up again while text only grows is the shake.
func reversals(_ h:[CGFloat]) -> Int {
    var count=0,last:CGFloat?=nil,dir=0
    for v in h { if let l=last, abs(v-l)>=1 { let d = v>l ? 1 : -1; if dir != 0 && d != dir {count+=1}; dir=d }; last=v }
    return count
}
@MainActor func run() async throws {
    let line="Size: submit ad in both sizes: 380px W x 320px H (Medium Rectangle) and 1,000px W x 100px H"
    var problems:[String]=[]
    // Every length from a few lines past the limit down to just under it.
    for count in 10...26 {
        let text=Array(repeating:line,count:count).joined(separator:"\n")
        let h=try await heights(text,max:420)
        let tail=Array(h.suffix(20))
        if Set(tail.map{Int($0.rounded())}).count>1 { problems.append("\(count) lines: \(tail.map{Int($0)})") }
    }
    // Typing across the limit, a line at a time.
    for count in [14,16,18] {
        let start=Array(repeating:line,count:count).joined(separator:"\n")
        let h=try await typing(start,"\n"+line+"\n"+line+"\nFile Format: PDF preferred, may also accept EPS, JPG or PNG, 300 minimum DPI",max:420)
        let r=reversals(h)
        if r>0 { problems.append("typing from \(count) lines: \(r) reversals, heights \(Array(Set(h.map{Int($0)})).sorted())") }
    }
    // It still grows as you type, from one line up to the limit, and shrinks back when cleared.
    let grow=try await typing("Hi","\nSecond line\nThird line\nFourth line",max:420)
    if !((grow.last ?? 0) > (grow.first ?? 0) + 20) { problems.append("didn't grow while typing: \(Array(Set(grow.map{Int($0)})).sorted())") }
    let tall=try await typing(Array(repeating:line,count:30).joined(separator:"\n"),"!",max:420)
    if Int(tall.last ?? 0) != 420 { problems.append("long text isn't capped at the limit: \(Int(tall.last ?? 0))") }
    if problems.isEmpty { print("PASS the message box settles at every length around its limit") }
    else { print("FAIL the message box keeps resizing:\n"+problems.joined(separator:"\n")); exit(1) }
}
Task { @MainActor in do {try await run();exit(0)} catch {print(error);exit(1)} }
app.run()

import AppKit
import SwiftUI
struct FrameKey: PreferenceKey {
 static let defaultValue: [String: CGRect] = [:]
 static func reduce(value: inout [String:CGRect],nextValue:()->[String:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{$1}) }
}
@MainActor final class Frames {var value:[String:CGRect]=[:]}
struct Row:View {
 let context:Bool;let frames:Frames
 var body:some View {
 ComposerStatusLayout {
 HStack(spacing:14) {
 Text("Bypass permissions").foregroundStyle(.orange).fixedSize().tracked("permissions")
 if context {Text("Context 44%").fixedSize().tracked("context")}
 }
 HStack(spacing:6) {Image(systemName:"chevron.left");Text("Claude · Opus 5.5 · Medium effort").padding(8).background(Capsule().stroke(.pink))}.tracked("model")
 }.font(.caption).coordinateSpace(name:"row").onPreferenceChange(FrameKey.self){frames.value=$0}.padding(15)
 }
}
extension View {func tracked(_ name:String)->some View {background(GeometryReader {g in Color.clear.preference(key:FrameKey.self,value:[name:g.frame(in:.named("row"))])})}}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
 for width in [760,400] {for context in [false,true] {
 let frames=Frames();let window=NSPanel(contentRect:NSRect(x:80,y:80,width:width,height:130),styleMask:[.titled],backing:.buffered,defer:false)
 window.appearance=NSAppearance(named:.darkAqua)
 window.contentView=NSHostingView(rootView:Row(context:context,frames:frames));window.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(350))
 let view=window.contentView!;let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/model-row-\(width)-\(context).png"))
 let p=frames.value["permissions"]!;let m=frames.value["model"]!
 print("width=\(width) context=\(context) permissions=\(p) model=\(m) overlap=\(p.intersects(m))")
 if ProcessInfo.processInfo.environment["ASSERT_LAYOUT"] != nil {precondition(!p.intersects(m),"Controls overlap"); if let c=frames.value["context"] {precondition(!c.intersects(p) && !c.intersects(m),"Context overlaps another control");precondition(c.minX>p.maxX && c.maxX<CGFloat(width-30)/2,"Context is not on the left")}}
 window.close()
 }}
 exit(0)
}
app.run()

@testable import Chatterbox
import AppKit
import SwiftUI
// 3D models in a session: each format shows a lit, framed model (three.js, or SceneKit for
// USDZ). Copies of the given files are used. Evidence: <format>.png and a check that each
// model covers part of the preview.
let app=NSApplication.shared
app.setActivationPolicy(.regular)
// No App Nap: it can hold this test's timers while its windows sit behind others.
let awake=ProcessInfo.processInfo.beginActivity(options:[.userInitiated,.latencyCritical],reason:"Rendering model previews")
typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let capture = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), to: CaptureFn.self)
var failures=0
func check(_ ok:Bool,_ what:String) { print((ok ? "PASS " : "FAIL ")+what); fflush(stdout); if !ok { failures+=1 } }
/// How much of the preview's middle a model covers: points that differ from its background
/// (sampled just inside the preview's corner). A blank, failed or loading card covers almost none.
func coverage(_ rep:NSBitmapImageRep)->Double {
    let w=rep.pixelsWide,h=rep.pixelsHigh
    func at(_ x:Int,_ y:Int)->NSColor? { rep.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) }
    guard w>0, let back=at(w/8,h/4) else { return 0 }
    var points=0,covered=0
    for y in stride(from:h/4,to:h*3/4,by:6) { for x in stride(from:w/4,to:w*3/4,by:6) {
        guard let c=at(x,y) else { continue }
        points+=1
        if abs(c.redComponent-back.redComponent)+abs(c.greenComponent-back.greenComponent)+abs(c.blueComponent-back.blueComponent)>0.12 { covered+=1 }
    } }
    return Double(covered)/Double(max(points,1))
}
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    let sources=CommandLine.arguments.dropFirst().map { URL(fileURLWithPath:$0) }
    for source in sources {
        let ext=source.pathExtension.lowercased()
        // A copy of the file, and for a .gltf the files it points to beside it.
        let folder=root.appendingPathComponent(ext,isDirectory:true)
        try? FileManager.default.removeItem(at:folder)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at:source,to:url)
        if ext == "gltf", let json=try? JSONSerialization.jsonObject(with:Data(contentsOf:source)) as? [String:Any] {
            for key in ["buffers","images"] { for entry in (json[key] as? [[String:Any]]) ?? [] {
                guard let uri=entry["uri"] as? String, !uri.hasPrefix("data:"), let path=uri.removingPercentEncoding else { continue }
                let to=folder.appendingPathComponent(path)
                try? FileManager.default.createDirectory(at:to.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? FileManager.default.copyItem(at:source.deletingLastPathComponent().appendingPathComponent(path),to:to)
            } }
        }
        print("… \(ext): showing \(source.lastPathComponent)");fflush(stdout)
        guard let kind=MediaKind.of(url) else { check(false,"\(ext) is a 3D model");continue }
        check(kind == (ext == "usdz" ? .usdz : .model3D),"\(ext) is a 3D model")
        let window=NSWindow(contentRect:NSRect(x:60,y:60,width:700,height:420),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.appearance=NSAppearance(named:.darkAqua)
        window.contentView=NSHostingView(rootView:MediaPreview(url:url,kind:kind).padding(20).frame(width:700,height:420).background(Color.black).environment(\.colorScheme,.dark))
        window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
        FileHandle.standardError.write(Data("… \(ext) window up\n".utf8))
        // The page loads three.js from its CDN, then parses the model: up to 40 seconds.
        var rep=NSBitmapImageRep()
        var share=0.0
        for attempt in 0..<20 {
            try await Task.sleep(for:.seconds(2))
            FileHandle.standardError.write(Data("… \(ext) attempt \(attempt)\n".utf8))
            guard let image=capture(.null,8,UInt32(window.windowNumber),1|8)?.takeRetainedValue() else { continue }
            rep=NSBitmapImageRep(cgImage:image);share=coverage(rep)
            FileHandle.standardError.write(Data("… \(ext) covers \(share)\n".utf8))
            if share>0.08 { break }
        }
        try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("\(ext).png"))
        try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("\(ext).png"))
        check(share>0.08,"\(ext) renders a model (covers \(Int(share*100))% of the middle)")
        window.orderOut(nil)
    }
    print(failures==0 ? "PASS model previews. Evidence: \(root.path)" : "FAIL \(failures) checks. Evidence: \(root.path)")
    exit(failures==0 ? 0 : 1)
}
Task { @MainActor in do {try await run()} catch {print(error);exit(1)} }
app.run()

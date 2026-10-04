@testable import Chatterbox
import AppKit
import SwiftTerm
import ScreenCaptureKit
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-terminal-color."))
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let rc=root.appendingPathComponent("user-zsh");try FileManager.default.createDirectory(at:rc,withIntermediateDirectories:true)
    try "export CHATTERBOX_RC_LOADED=yes\nPROMPT='original plain prompt> '\n".write(to:rc.appendingPathComponent(".zshrc"),atomically:true,encoding:.utf8)
    setenv("ZDOTDIR",rc.path,1)
    let terminal=ChatTerminal(folder:root.path)
    let panel=NSPanel(contentRect:NSRect(x:30,y:90,width:800,height:300),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    panel.contentView=terminal.view;panel.makeKeyAndOrderFront(nil)
    try await Task.sleep(for:.seconds(2))
    terminal.view.send(txt:"printf 'Startup: %s\\n' \"$CHATTERBOX_RC_LOADED\"\r")
    try await Task.sleep(for:.seconds(1))
    let engine=terminal.view.getTerminal()
    let text=String(data:engine.getBufferAsData(),encoding:.utf8)!
    precondition(text.contains("Startup: yes"),"Original rc not loaded")
    var colored=0
    for row in 0..<engine.rows {
        guard let line=engine.getLine(row:row) else {continue}
        for col in 0..<engine.cols {if line[col].attribute.fg != .defaultColor {colored += 1}}
    }
    precondition(colored>5,"No prompt color")
    precondition(try! String(contentsOf:rc.appendingPathComponent(".zshrc"),encoding:.utf8)=="export CHATTERBOX_RC_LOADED=yes\nPROMPT='original plain prompt> '\n")
    let target=try await SCShareableContent.currentProcess.windows.first {$0.windowID==CGWindowID(panel.windowNumber)}!
    let config=SCStreamConfiguration();config.width=1600;config.height=600
    let image=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:target),configuration:config)
    try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("prompt.png"))
    terminal.view.send(txt:"exit\r")
    try await Task.sleep(for:.milliseconds(500))
    print("PASS original zsh startup preserved; colored prompt cells \(colored); source rc unchanged")
}
Task {do {try await run();exit(0)} catch {print(error);exit(1)}}
app.run()

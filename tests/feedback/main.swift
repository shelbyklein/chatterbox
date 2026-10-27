@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// Feedback: a screenshot of the window, annotated, lands in the Chatterbox project session's
// message box, which opens (also when that session is already open). Evidence: shot.png, chat.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-feedback."))
 UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 var other=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 other.projectFolder=root+"/Website";other.title="Website"
 _=model.insertSession(other)
 var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 record.projectFolder=root+"/Chatterbox";record.title="Chatterbox"
 let project=model.insertSession(record)
 try FileManager.default.createDirectory(atPath:root+"/Chatterbox",withIntermediateDirectories:true)
 precondition(model.feedbackProject?.id==project.id,"feedback goes to the project in the Chatterbox folder")
 // The window, already showing the Chatterbox session.
 model.selectedID=project.id
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:760,height:440),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 panel.contentView=NSHostingView(rootView:ChatView(session:project).environment(model).environment(\.colorScheme,.dark))
 panel.orderFrontRegardless()
 try await Task.sleep(for:.seconds(1))
 model.startFeedback(from:panel)
 guard let shot=model.feedbackShot,let image=NSImage(contentsOf:shot.url) else{throw RuntimeFailure("no screenshot")}
 precondition(image.size.width>=700 && shot.kind == .image,"the screenshot is the window (\(image.size))")
 try FileManager.default.copyItem(at:shot.url,to:URL(fileURLWithPath:root+"/shot.png"))
 model.feedbackShot=nil
 model.placeFeedback(text:"The send button overlaps the model chip.",attachments:[shot])
 try await Task.sleep(for:.milliseconds(800))
 precondition(model.selectedID==project.id && model.composerInsertion==nil,"the open Chatterbox session took it in")
 precondition(project.draftAttachments.contains(shot) && project.draft.contains("overlaps the model chip"),"screenshot and note wait in its message box (\(project.draft))")
 let view=panel.contentView!;view.layoutSubtreeIfNeeded()
 let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/chat.png"))
 print("PASS feedback: screenshot, Chatterbox session, message box. Evidence: \(root)")
}
Task { @MainActor in do { try await run(); exit(0) } catch { print("FAIL \(error)"); exit(1) } }
app.run()

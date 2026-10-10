@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@Observable @MainActor final class Driver { var request=0 }
struct Entry:View {
 let session:ChatSession
 let summary:String
 let driver:Driver
 var body:some View {
  ModelPicker(session:session,selectionPill:true,summary:summary,color:.blue,openRequest:driver.request)
   .font(.caption).padding(20).frame(width:600,height:120)
 }
}
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-current-model."))
 let preset=ModelPreset(title:"Arty",backend:.codex,model:"gpt-6-astra",effort:"medium")
 let presets=try JSONEncoder().encode([preset,
  ModelPreset(title:"Smarty",backend:.claude,model:"sonnet",effort:"medium"),
  ModelPreset(title:"Maestro",backend:.codex,model:"gpt-6-luna",effort:"low"),
  ModelPreset(title:"Brainy",backend:.claude,model:"haiku",effort:"medium")])
 UserDefaults.standard.setVolatileDomain(["modelPresets":presets,"dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false,"themeBackground":"black"],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 record.activeBackend = .codex;record.codex=CodexSettings(model:"gpt-6-astra",effort:"medium",folder:root,canEdit:false)
 let session=model.insertSession(record)
 let driver=Driver()
 let panel=NSPanel(contentRect:NSRect(x:80,y:80,width:600,height:120),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua);panel.orderFrontRegardless()
 func save(_ view:NSView,_ name:String) throws {
  view.layoutSubtreeIfNeeded();let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
  view.cacheDisplay(in:view.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent(name+".png"))
 }
 panel.contentView=NSHostingView(rootView:Entry(session:session,summary:preset.displayName,driver:driver).environment(model))
 try await Task.sleep(for:.seconds(1));try save(panel.contentView!,"preset-name")
 let before=session.record.codex
 func control(_ node: Any, _ label: String, depth: Int = 0) -> (any NSAccessibilityProtocol)? {
  guard depth < 20, let element=node as? any NSAccessibilityProtocol else { return nil }
  if element.accessibilityLabel()==label {return element}
  for child in element.accessibilityChildren() ?? [] {if let found=control(child,label,depth:depth+1) {return found}}
  return nil
 }
 func click(_ x: CGFloat, _ y: CGFloat) {
  let point=panel.contentView!.convert(NSPoint(x:x,y:y),to:nil)
  for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
   let event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
   panel.sendEvent(event)
  }
 }
 if let reveal=control(panel.contentView!,"Show presets") {precondition(reveal.accessibilityPerformPress())}
 else {click(269,60)}
 for frame in 0..<5 {
  if frame > 0 {try await Task.sleep(for:.milliseconds(80))}
  try save(panel.contentView!,"reveal-\(frame)")
 }
 try await Task.sleep(for:.milliseconds(200));try save(panel.contentView!,"presets-expanded")
 precondition(!app.windows.contains {$0 !== panel && $0.isVisible && $0.frame.width > 300},"First stage opened full picker")
 if let more=control(panel.contentView!,"Choose model and effort") {precondition(more.accessibilityPerformPress())}
 else {click(30,60)}
 try await Task.sleep(for:.seconds(1))
 precondition(app.windows.contains {$0 !== panel && $0.isVisible && $0.frame.width > 300},"Model picker did not open")
 precondition(session.record.codex==before,"Opening picker changed model")
 if let popover=app.windows.first(where:{$0 !== panel && $0.isVisible && $0.frame.width > 300}),let view=popover.contentView {try save(view,"picker")}
 panel.contentView=NSHostingView(rootView:Entry(session:session,summary:"Codex · GPT-6-Astra · Medium effort",driver:Driver()).environment(model))
 try await Task.sleep(for:.milliseconds(700));try save(panel.contentView!,"full-model")

 var claudeRecord=ConversationRecord(model:"claude-opus-5-5",effort:"medium",personality:.pragmatic)
 claudeRecord.claudeMode="bypassPermissions"
 let claude=model.insertSession(claudeRecord)
 let chatPanel=NSPanel(contentRect:NSRect(x:80,y:80,width:760,height:440),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
 chatPanel.appearance=NSAppearance(named:.darkAqua)
 chatPanel.contentView=NSHostingView(rootView:ChatView(session:claude).environment(model).environment(\.colorScheme,.dark))
 chatPanel.orderFrontRegardless()
 try await Task.sleep(for:.seconds(1))
 try save(chatPanel.contentView!,"claude-no-context")
 claude.contextUsage[.claude]=ContextUsage(used:44000,window:100000)
 try await Task.sleep(for:.milliseconds(500))
 try save(chatPanel.contentView!,"claude-with-context")
 let chatView=chatPanel.contentView!
 let chatPoint=chatView.convert(NSPoint(x:525,y:chatView.isFlipped ? chatView.bounds.height-36 : 36),to:nil)
 for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
  chatPanel.sendEvent(NSEvent.mouseEvent(with:type,location:chatPoint,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:chatPanel.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1)!)
 }
 try await Task.sleep(for:.milliseconds(500))
 try save(chatView,"claude-presets-expanded")
 setenv("CHATTERBOX_TEST_SIDEBAR_ONLY","380",1)
 var project=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 project.projectFolder=root+"/project";project.projectNickname="Sample Project";project.title="Sample Project"
 _=model.insertSession(project)
 let side=NSPanel(contentRect:NSRect(x:100,y:100,width:380,height:650),styleMask:[.titled],backing:.buffered,defer:false)
 side.appearance=NSAppearance(named:.darkAqua);side.orderFrontRegardless()
 for chats in [false,true] {
  model.showingChatsSidebar=chats
  side.contentView=NSHostingView(rootView:ContentView().environment(model).environment(\.colorScheme,.dark))
  try await Task.sleep(for:.milliseconds(700));try save(side.contentView!,chats ? "chats-list" : "projects-cards")
 }
 print("PASS: one named model pill renders; actual picker opens and preserves settings; separate default Cards/List sidebars rendered. Evidence: \(root)")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()

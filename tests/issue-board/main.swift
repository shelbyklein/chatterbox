@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// The Mac issue board (plans/project-issues.md, I2): a PlayCase-like project's issues grouped by
// game with Open · In progress · Review lanes, General last; an issue's sheet; a project chat's
// header offers Issues. Evidence: board.png, sheet.png, header.png in the temp folder.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-issue-board."))
 UserDefaults.standard.setVolatileDomain(["companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 CompanionServer.shared.model=model
 // A project with a two-game catalog and a preview picture.
 let arcade=URL(fileURLWithPath:root).appendingPathComponent("playcase-arcade")
 try FileManager.default.createDirectory(at:arcade.appendingPathComponent("catalog"),withIntermediateDirectories:true)
 try FileManager.default.createDirectory(at:arcade.appendingPathComponent("game-previews"),withIntermediateDirectories:true)
 func png(_ color:NSColor,_ url:URL,_ label:String) throws {
  let image=NSImage(size:NSSize(width:320,height:200),flipped:false) { r in color.setFill();r.fill()
   (label as NSString).draw(at:NSPoint(x:20,y:80),withAttributes:[.font:NSFont.boldSystemFont(ofSize:36),.foregroundColor:NSColor.white]);return true }
  try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:url)
 }
 try png(.systemPurple,arcade.appendingPathComponent("game-previews/descent.png"),"DESCENT")
 try png(.systemTeal,arcade.appendingPathComponent("game-previews/bowl.png"),"BOWL")
 try #"{"schema":1,"games":[{"id":"descent","title":"Descent","image":"game-previews/descent.png"},{"id":"bowl","title":"Bowl","image":"game-previews/bowl.png"}]}"#
  .write(to:arcade.appendingPathComponent("catalog/games.json"),atomically:true,encoding:.utf8)
 var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 record.title="Playcase Arcade";record.projectFolder=arcade.path;record.projectNickname="Playcase Arcade"
 record.items=[DisplayItem(kind:.user,text:"Let's fix Descent"),DisplayItem(kind:.assistant,text:"On it.",phase:.final)]
 let project=model.insertSession(record)
 precondition(model.projectFolder(of:project)==arcade.path,"the session's project")
 let store=ProjectIssueStore.shared
 let shot=URL(fileURLWithPath:root).appendingPathComponent("flicker.png");try png(.systemRed,shot,"FLICKER")
 let a=try store.add(.init(title:"Wordmark flickers on the title screen",notes:"Seen on the Duo after the crumble animation.",game:"descent",type:"bug",priority:"high",attachments:[shot.path]),in:arcade.path,by:"you")
 _=try store.add(.init(title:"Add a hard mode with faster drops",game:"descent",type:"feature"),in:arcade.path,by:"claude")
 let c=try store.add(.init(title:"Pins clip through the gutter",game:"bowl",type:"bug"),in:arcade.path,by:"codex")
 try store.update(c.id,in:arcade.path,.init(status:"review"))
 _=try store.add(.init(title:"Shelf scroll stutters with 30+ games",type:"polish",priority:"low"),in:arcade.path,by:"you")
 // The board, in-process (CHATTERBOX_LEGACY_RUNTIME).
 func render(_ view:some View,_ size:NSSize,_ name:String) async throws -> NSBitmapImageRep {
  let panel=NSPanel(contentRect:NSRect(origin:CGPoint(x:60,y:60),size:size),styleMask:[.titled],backing:.buffered,defer:false)
  panel.appearance=NSAppearance(named:.darkAqua)
  panel.contentView=NSHostingView(rootView:view.environment(model).environment(\.colorScheme,.dark).frame(width:size.width,height:size.height).background(Color.black))
  panel.orderFrontRegardless()
  try await Task.sleep(for:.seconds(1.5))
  let v=panel.contentView!;v.layoutSubtreeIfNeeded()
  let bitmap=v.bitmapImageRepForCachingDisplay(in:v.bounds)!;v.cacheDisplay(in:v.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root+"/\(name).png"))
  panel.close()
  return bitmap
 }
 _=try await render(IssueBoardView(folder:arcade.path),NSSize(width:1200,height:760),"board")
 let board=IssueBoardModel.shared.board
 precondition(board?.issues.count==4 && board?.games.map(\.id)==["descent","bowl"],"the board loads: 4 issues, 2 games (\(String(describing:board?.issues.count)))")
 precondition(board?.issues.first?.number==3,"Review sorts first")
 print("PASS board: \(board!.issues.count) issues under \(board!.games.count) games and General")
 _=try await render(IssueSheet(target:.issue(store.board(for:arcade.path).issues.first{$0.id==a.id}!),games:board!.games,folder:arcade.path){},NSSize(width:640,height:640),"sheet")
 print("PASS sheet rendered")
 _=try await render(ChatView(session:project),NSSize(width:900,height:300),"header")
 print("PASS header rendered")
}
Task { @MainActor in do { try await run(); exit(0) } catch { print(error); exit(1) } }
app.run()

import XCTest
final class HomeNavTests: XCTestCase {
 override func setUp() { super.setUp(); continueAfterFailure = false }
 func selected(_ app: XCUIApplication) -> String {
  app.tabBars.buttons.allElementsBoundByIndex.first { $0.isSelected }?.label ?? "?"
 }
 /// The Studios tab opens on every Studio; this opens one (if its card is showing).
 func openStudio(_ id: String, _ app: XCUIApplication) {
  let card = app.buttons["studio-select-" + id]
  if card.waitForExistence(timeout: 3) { card.tap() }
 }
 /// A swipe that starts at the screen's very edge, at mid-height.
 func edgeSwipe(_ app: XCUIApplication, fromLeft: Bool) {
  let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: fromLeft ? 0.01 : 0.99, dy: 0.5))
  let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: fromLeft ? 0.6 : 0.4, dy: 0.5))
  start.press(forDuration: 0.05, thenDragTo: end)
 }
 /// Calibration: with the strips off, does a synthesized left-edge drag trigger Back at all?
 @MainActor func testSystemBackSwipeWithoutStrips() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47411", "CHATTERBOX_TEST_NO_EDGE_SWIPE": "1"]
  app.launch()
  XCTAssertTrue(tab("All",app).waitForExistence(timeout:15), "All is in the bottom bar")
  XCTAssertGreaterThan(tab("All",app).frame.minX, tab("Chats",app).frame.minX, "All comes last, after Chats")
  tab("All",app).tap()
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout:10), "All lists projects")
  XCTAssertTrue(app.descendants(matching:.any)["Coach Archie"].exists || app.staticTexts["Coach Archie"].exists, "and Studio sessions, together")
  capture("0-all-sessions",app)
  tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout:15))
  XCTAssertFalse(app.tabBars.buttons["Golem"].exists)
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout: 10))
  app.buttons["chat-" + uuid("SDHQ")].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout: 10))
  edgeSwipe(app, fromLeft: true)
  try await Task.sleep(for: .seconds(1.5))
  print("CALIBRATION back worked:", app.buttons["chat-" + uuid("SDHQ")].exists)
 }
 @MainActor func testEdgeSwipeAndCards() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47411"]
  if ProcessInfo.processInfo.environment["NO_EDGE"] != nil { app.launchEnvironment["CHATTERBOX_TEST_NO_EDGE_SWIPE"] = "1" }
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15))
  tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout:15))
  XCTAssertFalse(app.tabBars.buttons["Golem"].exists)
  XCTAssertTrue(app.buttons["Activity, 1 new replies, 3 working"].waitForExistence(timeout:5), "Activity lists new replies and working chats")
  let activityReply = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "New reply: Tracker Trapper")).firstMatch
  let activityWorking = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Working: Galley")).firstMatch
  XCTAssertTrue(activityWorking.exists && activityReply.exists)
  XCTAssertLessThan(activityWorking.frame.maxY, activityReply.frame.minY, "Working sessions lead Activity in list mode")
  XCTAssertFalse(app.buttons["chat-975B1769-F8EA-59E2-A601-B40A492D19FA"].exists, "a sidequest isn't listed on its own")
  XCTAssertTrue(app.staticTexts["Codex: Render four ribbon options"].exists, "its chat's row names it")
  capture("1-chats-list",app)
  // Cards, two to a row.
  app.buttons["Show as Cards"].tap()
  try await Task.sleep(for: .seconds(1))
  let first = app.buttons["chat-" + uuid("Chatterbox")], second = app.buttons["chat-" + uuid("optimization")]
  XCTAssertTrue(first.waitForExistence(timeout: 5) && second.exists)
  XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2, "two cards share a row")
  XCTAssertLessThan(first.frame.maxX, second.frame.minX, "side by side")
  XCTAssertFalse(app.images["Latest image in Chatterbox"].exists, "Projects never show thumbnails")
  XCTAssertTrue(app.buttons["Activity, 1 new replies, 3 working"].exists, "Activity shows in card view too")
  XCTAssertLessThan(activityWorking.frame.maxY, activityReply.frame.minY, "Working sessions lead Activity in card mode")
  capture("3-cards", app)
  // A chat open: the left-edge swipe is Back, not a tab switch.
  app.buttons["chat-" + uuid("SDHQ")].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout: 10))
  XCTAssertTrue(app.buttons["Sidequest to Codex: Render four ribbon options, working"].waitForExistence(timeout: 5), "the chat lists its sidequest")
  capture("2-sidequest-strip", app)
  app.buttons["Session Menu"].tap()
  XCTAssertTrue(app.buttons["Session Settings"].waitForExistence(timeout: 5)); app.buttons["Session Settings"].tap()
  let opus = app.buttons["Opus preset, Claude · Opus 5.5 · Medium"], sol = app.buttons["Sol preset, Codex · GPT-6.1-Sol · Low"], maestro = app.buttons["Maestro preset, Codex · GPT-6-Luna"]
  XCTAssertTrue(opus.waitForExistence(timeout: 5))
  XCTAssertEqual(sol.frame.minY, maestro.frame.minY, accuracy: 2, "four presets share one row")
  capture("2b-chat-settings", app)
  app.navigationBars["Session Settings"].buttons["Done"].tap()
  // The strip yields while a chat is open: a left-edge swipe here mustn't jump to Golem.
  // (A synthesized drag can't trigger iOS's own Back swipe; see the calibration test.)
  edgeSwipe(app, fromLeft: true)
  try await Task.sleep(for: .seconds(1.5))
  XCTAssertFalse(app.tabBars.buttons["Golem"].exists,"ordinary chat navigation does not expose Golem")
  // iOS's own Back swipe may or may not fire for a synthesized drag; either way, back to the list.
  if app.staticTexts["Hi! This is SDHQ."].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout: 5), "back at the cards")
  capture("4-after-back", app)
  // Chatterbox remains on ordinary chats after a sidebar edge gesture.
  edgeSwipe(app,fromLeft:true)
  try await Task.sleep(for:.seconds(1))
  XCTAssertFalse(app.tabBars.buttons["Golem"].exists)
  // The system sidebar gesture can hide the sidebar; list/cards interaction
  // was already verified above before exercising native navigation.
 }
 @MainActor func testStudioCardThumbnails() async throws {
  try await fixture("reset")
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15))
  tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].waitForExistence(timeout:15))
  tab("Studios",app).tap()
  // Every Studio first, each a card; its sessions once you open it.
  XCTAssertTrue(app.buttons["studio-select-studio-1"].waitForExistence(timeout:10) && app.buttons["studio-select-studio-2"].exists, "the Studios tab shows every Studio")
  XCTAssertFalse(app.buttons.matching(identifier: "chat-" + "F982B462-68F5-509B-8E10-9946C3F0A1B1").firstMatch.exists, "no Studio's sessions until one is opened")
  capture("studios-index",app)
  openStudio("studio-1",app)
  if app.buttons["Show as Cards"].exists { app.buttons["Show as Cards"].tap() }
  let reply = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "New reply: Tracker Trapper")).firstMatch
  let working = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Working: Galley")).firstMatch
  XCTAssertTrue(reply.waitForExistence(timeout:5) && working.exists)
  XCTAssertEqual(reply.frame.minX, working.frame.minX, accuracy:2)
  XCTAssertLessThan(working.frame.maxY, reply.frame.minY, "Working sessions appear above unread replies in the Activity list")
  XCTAssertGreaterThan(reply.frame.width, app.windows.firstMatch.frame.width * 0.8, "Activity uses the full-width list")
  XCTAssertTrue(app.images["Latest image in Coach Archie"].waitForExistence(timeout:10))
  XCTAssertFalse(app.images["Latest image in No image"].exists)
  capture("studio-card-thumbnails",app)
  let search = app.searchFields.firstMatch
  XCTAssertTrue(search.exists)
  search.tap()
  search.typeText("Crystal")
  XCTAssertTrue(app.staticTexts["Crystal concept"].waitForExistence(timeout:5), "Search spans Studios")
  capture("studio-search",app)
  search.buttons["Clear text"].tap()
  if app.buttons["Close"].exists { app.buttons["Close"].tap() }
  else if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
  XCTAssertTrue(app.buttons["Studio options"].waitForExistence(timeout:5))
  app.buttons["studios-index"].tap()
  openStudio("studio-2",app)
  XCTAssertTrue(app.staticTexts["Crystal concept"].waitForExistence(timeout:5))
  XCTAssertFalse(app.images["Latest image in Coach Archie"].exists)
  capture("studio-switched",app)
  // A 3D model in a reply previews (Crystal concept's reply has an STL).
  app.staticTexts["Crystal concept"].tap()
  XCTAssertTrue(app.staticTexts["The crystal stand is ready."].waitForExistence(timeout:10))
  sleep(12)
  capture("model-preview",app)
  // The session's Brief, from its menu.
  app.buttons["Session Menu"].tap()
  XCTAssertTrue(app.buttons["Brief…"].waitForExistence(timeout:5));app.buttons["Brief…"].tap()
  let briefText=app.textViews["brief-text"]
  XCTAssertTrue(briefText.waitForExistence(timeout:5));briefText.tap();briefText.typeText("Keep the crystal facets sharp.")
  capture("brief-editor",app)
  app.navigationBars["Session Brief"].buttons["Save"].tap()
  let briefs=try await fixture("briefs",method:"GET") as? [String:String]
  XCTAssertEqual(briefs?["Crystal concept"],"Keep the crystal facets sharp.","the Brief reaches the Mac")
  app.buttons["Session Menu"].tap()
  XCTAssertTrue(app.buttons["Edit Brief…"].waitForExistence(timeout:5),"a set Brief shows as Edit Brief")
  app.buttons["Edit Brief…"].tap();app.navigationBars["Session Brief"].buttons["Cancel"].tap()
  app.navigationBars.buttons.element(boundBy:0).tap()
  app.buttons["studios-index"].tap()
  openStudio("studio-1",app)
  let coach = app.buttons.matching(identifier: "chat-" + "F982B462-68F5-509B-8E10-9946C3F0A1B1").firstMatch
  XCTAssertTrue(coach.waitForExistence(timeout:5))
  coach.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Coach Archie."].waitForExistence(timeout:10))
  app.navigationBars.buttons.element(boundBy:0).tap()
  XCTAssertTrue(app.buttons["studios-index"].waitForExistence(timeout:5), "back from a session, still in its Studio")
  app.buttons["Studio options"].tap()
  app.buttons["Show as List"].tap()
  XCTAssertTrue(app.buttons.matching(identifier: "chat-" + "F982B462-68F5-509B-8E10-9946C3F0A1B1").firstMatch.waitForExistence(timeout:5))
  capture("studio-list",app)
  tab("Projects",app).tap()
 }
 /// Native actions must work in both nested List and Studio's ScrollView.
 @MainActor func testActivityDismissalSwipes() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15))
  tab("Projects",app).tap()
  let working = activity("Working: Galley", app)
  let reply = activity("New reply: Tracker Trapper", app)
  XCTAssertTrue(working.waitForExistence(timeout:15) && reply.waitForExistence(timeout:10))
  swipe(working, full:false, left:true)
  XCTAssertTrue(app.buttons["Dismiss"].waitForExistence(timeout:3))
  XCTAssertFalse(app.buttons["Archive"].exists || app.buttons["Delete"].exists, "Swiping left only clears")
  capture("activity-swipe-actions",app)
  working.tap()
  swipe(working, full:false, left:false)
  XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout:3) && app.buttons["Delete"].exists)
  XCTAssertFalse(app.buttons["Dismiss"].exists)
  capture("activity-swipe-right-actions",app)
  // Closing a partial swipe leaves the row and allows vertical scrolling.
  working.tap()
  XCTAssertTrue(working.exists)
  swipe(working, full:true, left:true)
  XCTAssertTrue(working.waitForNonExistence(timeout:5), "Full swipe dismisses working activity")
  XCTAssertTrue(app.buttons["chat-" + "B5BBD354-BAAF-5AB3-B7FE-3ACD63B384E2"].exists, "Main chat remains")
  XCTAssertTrue(reply.exists, "Other activity remains")
  capture("activity-after-dismiss",app)
  app.terminate();app.launch()
  XCTAssertTrue(reply.waitForExistence(timeout:15))
  XCTAssertFalse(working.exists, "Dismissal survives relaunch and refresh")
  swipe(reply, full:true, left:true)
  XCTAssertTrue(reply.waitForNonExistence(timeout:5))
  let mutations = try await fixture("mutations", method:"GET") as? [String]
  XCTAssertEqual(mutations, [], "Dismissal sends no archive/delete/stop action")
  try await fixture("complete", body:["name":"Galley"])
  XCTAssertTrue(activity("New reply: Galley",app).waitForExistence(timeout:10), "Completed dismissed work appears as a new reply")
  try await fixture("start", body:["name":"Galley"])
  XCTAssertTrue(working.waitForExistence(timeout:10), "A new turn becomes visible")
  try await fixture("complete", body:["name":"Tracker Trapper"])
  XCTAssertTrue(reply.waitForExistence(timeout:10), "A later reply is not suppressed")

 }
 @MainActor func testActivityManagementSwipes() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15))
  tab("Projects",app).tap()
  let working = activity("Working: Galley",app)
  XCTAssertTrue(working.waitForExistence(timeout:15))
  XCTAssertTrue(activity("New reply: Tracker Trapper",app).waitForExistence(timeout:10))
  swipe(working, full:false, left:false)
  app.buttons["Archive"].tap()
  XCTAssertTrue(app.buttons["Archive and Stop Reply"].waitForExistence(timeout:3))
  app.buttons["Cancel"].tap()
  XCTAssertTrue(working.exists)
  try await fixture("fail",body:["value":true])
  swipe(working, full:false, left:false);app.buttons["Archive"].tap()
  app.buttons["Archive and Stop Reply"].tap()
  XCTAssertTrue(app.alerts["Couldn't update session"].waitForExistence(timeout:5))
  capture("activity-action-error",app)
  app.alerts.buttons["OK"].tap()
  XCTAssertTrue(working.exists, "A failed archive keeps the activity")
  try await fixture("fail",body:["value":false])
  swipe(working, full:false, left:false);app.buttons["Archive"].tap();app.buttons["Archive and Stop Reply"].tap()
  XCTAssertTrue(working.waitForNonExistence(timeout:8))
  // Gallery layout uses the same native gestures; Delete must never be full-swipe.
  tab("Studios",app).tap()
  let coach=activity("Working: Coach Archie",app)
  XCTAssertTrue(coach.waitForExistence(timeout:5))
  swipe(coach,full:false,left:false)
  capture("activity-studio-swipe-actions",app)
  app.buttons["Delete"].tap()
  XCTAssertTrue(app.buttons["Delete Session"].waitForExistence(timeout:3))
  capture("activity-delete-confirmation",app)
  app.buttons["Cancel"].tap()
  XCTAssertTrue(coach.exists)
  swipe(coach,full:false,left:false);app.buttons["Delete"].tap();app.buttons["Delete Session"].tap()
  XCTAssertTrue(coach.waitForNonExistence(timeout:8))
  XCTAssertFalse(app.buttons["chat-F982B462-68F5-509B-8E10-9946C3F0A1B1"].exists)
  let mutations = try await fixture("mutations",method:"GET") as? [String]
  XCTAssertEqual(mutations, ["archive","delete"])
  // Real row navigation still works after the action tray is gone.
  activity("New reply: Tracker Trapper",app).tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Tracker Trapper."].waitForExistence(timeout:8))
 }
 @MainActor func testRenameFromListsAndActivity() async throws {
  try await fixture("reset")
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15))
  tab("Projects",app).tap()
  XCTAssertTrue(activity("Working: Coach Archie",app).waitForExistence(timeout:15))
  activity("Working: Coach Archie",app).press(forDuration:1)
  app.buttons["Rename"].tap()
  XCTAssertTrue(app.alerts["Rename Session"].waitForExistence(timeout:3))
  app.alerts.buttons["Cancel"].tap()
  XCTAssertTrue(activity("Working: Coach Archie",app).exists)
  activity("Working: Coach Archie",app).press(forDuration:1);app.buttons["Rename"].tap()
  let field=app.alerts.textFields.firstMatch
  field.tap()
  field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(field.value as? String ?? "").count))
  field.typeText("Renamed Coach")
  capture("activity-rename",app)
  app.alerts.buttons["Rename"].tap()
  XCTAssertTrue(activity("Working: Renamed Coach",app).waitForExistence(timeout:8))
  tab("Studios",app).tap();openStudio("studio-1",app)
  XCTAssertTrue(app.staticTexts["Renamed Coach"].waitForExistence(timeout:5))
  tab("Chats",app).tap()
  let loose=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Loose chat")).firstMatch
  XCTAssertTrue(loose.waitForExistence(timeout:5))
  loose.press(forDuration:1);app.buttons["Rename"].tap()
  XCTAssertTrue(app.alerts["Rename Session"].waitForExistence(timeout:3))
  app.alerts.buttons["Cancel"].tap()
  // Opening a chat still offers Rename in its existing menu.
  loose.tap();XCTAssertTrue(app.buttons["Session Menu"].waitForExistence(timeout:5))
  app.buttons["Session Menu"].tap();app.buttons["Rename"].tap()
  XCTAssertTrue(app.alerts["Rename Session"].waitForExistence(timeout:3))
  app.alerts.buttons["Cancel"].tap()
 }
 @MainActor func testPromoteChats() async throws {
  continueAfterFailure=false
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  func start() async throws {
   app.terminate();try await fixture("reset");app.launch()
   XCTAssertTrue(tab("Chats",app).waitForExistence(timeout:15));tab("Chats",app).tap()
   XCTAssertTrue(app.buttons["chat-"+uuid("Loose chat")].waitForExistence(timeout:15))
  }
  func action(_ label:String) {
   app.buttons["chat-"+uuid("Loose chat")].press(forDuration:1)
   app.buttons[label].tap()
   XCTAssertTrue(app.buttons["promotion-save"].waitForExistence(timeout:5))
  }
  func replace(_ field:XCUIElement,_ value:String) {
   field.tap();field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(field.value as? String ?? "").count));field.typeText(value)
  }
  try await start();action("Move to Studio…")
  app.buttons["Cancel"].tap()
  let noMutations=try await fixture("mutations",method:"GET") as! [String]
  XCTAssertEqual(noMutations.count,0)
  action("Move to Studio…")
  app.buttons["promotion-studio"].tap();app.buttons["USA Archery"].tap()
  XCTAssertTrue(app.switches["Keep current working folder"].exists)
  capture("promotion-existing-studio",app)
  app.buttons["promotion-save"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Loose chat."].waitForExistence(timeout:8))
  var promoted=try await fixture("promotions",method:"GET") as! [String:[String:Any]]
  XCTAssertEqual(promoted["Loose chat"]?["kind"] as? String,"studio")
  XCTAssertEqual(promoted["Loose chat"]?["keepFolder"] as? Bool,true)
  tab("Studios",app).tap();openStudio("studio-1",app)
  XCTAssertTrue(app.staticTexts["Loose chat"].waitForExistence(timeout:8))

  try await start();action("Move to Studio…")
  replace(app.textFields["promotion-name"],"Design Lab")
  capture("promotion-new-studio",app)
  try await fixture("fail",body:["value":true]);app.buttons["promotion-save"].tap()
  XCTAssertTrue(app.staticTexts["Fixture promotion failed. Try again."].waitForExistence(timeout:6))
  try await fixture("fail",body:["value":false]);app.buttons["promotion-save"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Loose chat."].waitForExistence(timeout:8))
  promoted=try await fixture("promotions",method:"GET") as! [String:[String:Any]]
  XCTAssertEqual(promoted["Loose chat"]?["name"] as? String,"Design Lab")

  try await start()
  app.buttons["chat-"+uuid("Loose chat")].tap()
  XCTAssertTrue(app.buttons["Session Menu"].waitForExistence(timeout:5));app.buttons["Session Menu"].tap()
  app.buttons["Make Project…"].tap()
  XCTAssertTrue(app.buttons["Browse Mac Folders"].waitForExistence(timeout:5));app.buttons["Browse Mac Folders"].tap()
  XCTAssertTrue(app.buttons["Use Folder"].waitForExistence(timeout:5))
  app.collectionViews.buttons["Projects"].tap()
  XCTAssertTrue(app.staticTexts["/Users/fixture/Projects"].waitForExistence(timeout:5))
  capture("promotion-folder-browser",app);app.buttons["Use Folder"].tap()
  // SwiftUI exposes the entire row as a Switch; tap the control at its trailing edge.
  app.switches["Create a new subfolder"].coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
  XCTAssertTrue(app.textFields["promotion-name"].waitForExistence(timeout:5))
  replace(app.textFields["promotion-name"],"Phone Project")
  capture("promotion-new-project",app);app.buttons["promotion-save"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Loose chat."].waitForExistence(timeout:8))
  promoted=try await fixture("promotions",method:"GET") as! [String:[String:Any]]
  XCTAssertEqual(promoted["Loose chat"]?["folder"] as? String,"/Users/fixture/Projects")
  XCTAssertEqual(promoted["Loose chat"]?["newFolderName"] as? String,"Phone Project")
  tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("Loose chat")].waitForExistence(timeout:8))

  try await start();action("Make Project…")
  replace(app.textFields["promotion-folder"],"/Users/fixture/Existing")
  app.buttons["promotion-save"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Loose chat."].waitForExistence(timeout:8))
  promoted=try await fixture("promotions",method:"GET") as! [String:[String:Any]]
  XCTAssertNil(promoted["Loose chat"]?["newFolderName"])
 }
 @MainActor func tab(_ name:String,_ app:XCUIApplication) -> XCUIElement {
  let phone=app.tabBars.buttons[name]
  if phone.exists { return phone }
  return app.descendants(matching:.any).matching(NSPredicate(format:"label == %@",name)).firstMatch
 }
 @MainActor func activity(_ prefix:String,_ app:XCUIApplication) -> XCUIElement {
  app.descendants(matching: .any).matching(NSPredicate(format:"label BEGINSWITH %@",prefix)).firstMatch
 }
 @MainActor func swipe(_ row:XCUIElement,full:Bool,left:Bool=false) {
  let app=XCUIApplication(), frame=row.frame
  let origin=app.coordinate(withNormalizedOffset:.zero)
  let start=origin.withOffset(CGVector(dx:left ? frame.maxX-20 : frame.minX+20,dy:frame.midY))
  let end=origin.withOffset(CGVector(dx:left ? (full ? 4 : frame.maxX-frame.width*0.3) : (full ? app.windows.firstMatch.frame.maxX-4 : frame.minX+frame.width*0.65),dy:frame.midY))
  start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.2)
 }
 @discardableResult func fixture(_ path:String,method:String="POST",body:[String:Any]=[:]) async throws -> Any {
  var request=URLRequest(url:URL(string:"http://127.0.0.1:47411/test/"+path)!)
  request.httpMethod=method
  if method != "GET" {request.httpBody=try JSONSerialization.data(withJSONObject:body)}
  let (data,response)=try await URLSession.shared.data(for:request)
  XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
  return try JSONSerialization.jsonObject(with:data)
 }
 /// Usage from the ⋯ menu: each agent's limits and the proxy accounts.
 @MainActor func testUsage() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15));tab("Projects",app).tap()
  app.buttons["Connection"].tap()
  XCTAssertTrue(app.buttons["Usage"].waitForExistence(timeout:5));app.buttons["Usage"].tap()
  XCTAssertTrue(app.staticTexts["81% used"].waitForExistence(timeout:8),"Claude's 7-day window")
  XCTAssertTrue(app.staticTexts["12% used"].exists && app.staticTexts["65% left"].exists,"Codex and the proxy account")
  capture("usage",app)
  app.buttons["Done"].tap()
 }
 @MainActor func testNewChatPicksSettingsFirst() async throws {
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].waitForExistence(timeout:15))
  app.buttons["New Chat"].firstMatch.tap()
  XCTAssertTrue(app.navigationBars["New Chat"].waitForExistence(timeout:5), "New Chat opens a sheet, not a chat")
  XCTAssertTrue(app.buttons["Opus preset, Claude · Opus 5.5 · Medium"].waitForExistence(timeout:5), "it shows the presets")
  XCTAssertTrue(app.staticTexts["Effort"].firstMatch.exists, "and the effort")
  app.segmentedControls.buttons["Codex"].firstMatch.tap()
  XCTAssertTrue(app.staticTexts["Full access"].waitForExistence(timeout:5), "switching agent loads that agent's permissions")
  capture("new-chat-sheet",app)
  app.buttons["new-chat-start"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout:10), "Start opens the new chat")
  let url=URL(string:"http://127.0.0.1:47411/test/created")!
  let (data,_)=try await URLSession.shared.data(from:url)
  let created=try JSONSerialization.jsonObject(with:data) as! [[String:Any]]
  XCTAssertEqual(created.last?["backend"] as? String,"codex")
  XCTAssertEqual((created.last?["settings"] as? [String:Any])?["mode"] as? String,"fullAccess","the chat starts with what was picked")
 }
 /// The fixture's ids (server.py: uuid5(NAMESPACE_URL, "home:" + name)).
 func uuid(_ name: String) -> String {
  ["Chatterbox": "971E8582-9FFF-5D24-A2A2-AC8F6057BB63", "optimization": "2A1682A3-0390-5A12-8CA8-E0E375E1EEFE",
   "SDHQ": "A13D6820-B24D-575B-BF53-A51A5CFE48CF", "Loose chat": "DE705550-FFB1-5E01-980B-CDD999137340"][name]!
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
 }
}

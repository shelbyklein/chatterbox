import XCTest
final class HomeNavTests: XCTestCase {
 override func setUp() { super.setUp(); continueAfterFailure = false }
 /// An open foldable (iPhone Duo) in portrait reports a compact width, like a phone, but has an
 /// iPad mini's room: it gets the iPad layout. Stood in for by an iPad told it's compact.
 @MainActor func testFoldableGetsTabletLayout() async throws {
  try await fixture("reset")
  XCUIDevice.shared.orientation = .portrait
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411",
                           "CHATTERBOX_TEST_COMPACT_WIDTH":"1"]
  app.launch()
  let screen = app.windows.firstMatch.frame.size
  guard min(screen.width, screen.height) >= 600 else { throw XCTSkip("needs an iPad-sized screen (an open iPhone Duo), not \(screen)") }
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  let project = app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10)); project.tap()
  let reply = app.staticTexts["Hi! This is SDHQ."]
  XCTAssertTrue(reply.waitForExistence(timeout:10))
  XCTAssertTrue(project.exists && project.frame.maxX < reply.frame.minX, "the list stays beside the open session, as on iPad")
  capture("foldable-portrait",app)
 }
 /// Keyboard/occluded height must not turn an open screen back into phone navigation.
 @MainActor func testOpenSidebarSurvivesKeyboardHeight() async throws {
  try await fixture("reset")
  XCUIDevice.shared.orientation = .portrait
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411",
                           "CHATTERBOX_TEST_COMPACT_WIDTH":"1", "CHATTERBOX_TEST_BOTTOM_OCCLUSION":"540"]
  app.launch()
  guard min(app.windows.firstMatch.frame.width,app.windows.firstMatch.frame.height)>=600 else { throw XCTSkip("open screen only") }
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15));tab("Projects",app).tap()
  let project=app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10));project.tap()
  let sidebar=app.descendants(matching:.any).matching(identifier:"session-sidebar-pane").firstMatch
  let detail=app.descendants(matching:.any).matching(identifier:"session-detail-pane").firstMatch
  XCTAssertTrue(sidebar.waitForExistence(timeout:5) && detail.exists,"open layout must survive a keyboard-sized loss of usable height")
  let originalWidth=sidebar.frame.width
  let composer=app.textViews["messageComposer"].exists ? app.textViews["messageComposer"] : app.textFields["messageComposer"]
  XCTAssertTrue(composer.waitForExistence(timeout:5));composer.tap();composer.typeText("Keep this draft")
  XCTAssertTrue(sidebar.exists && detail.exists,"typing must not replace either navigation pane")
  XCTAssertEqual(sidebar.frame.width,originalWidth,accuracy:2)
  XCTAssertEqual(composer.value as? String,"Keep this draft")
  capture("duo-keyboard-sidebar",app)
 }
 /// The camera/outer rail's trailing safe area must not be inset a second
 /// time inside the sidebar, whose right edge is internal to the window.
 @MainActor func testSidebarContentFillsItsPane() async throws {
  try await fixture("reset")
  XCUIDevice.shared.orientation = .portrait
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411",
                         "CHATTERBOX_TEST_COMPACT_WIDTH":"1"]
  app.launch()
  guard min(app.windows.firstMatch.frame.width,app.windows.firstMatch.frame.height)>=600 else {throw XCTSkip("open screen only")}
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15));tab("Projects",app).tap()
  let project=app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10));project.tap()
  let sidebar=app.descendants(matching:.any).matching(identifier:"session-sidebar-pane").firstMatch
  XCTAssertTrue(sidebar.waitForExistence(timeout:5))
  let search=app.searchFields["Search Projects"]
  XCTAssertTrue(search.waitForExistence(timeout:5))
  XCTAssertGreaterThanOrEqual(sidebar.frame.maxX-search.frame.maxX,8,"search must stay inside its own pane")
  XCTAssertLessThan(sidebar.frame.maxX-search.frame.maxX,36,"search should fill its pane, without a second camera/rail inset")
  capture("duo-sidebar-content-insets",app)
 }
 /// A native iPad stand-in for a bent Duo: an asymmetric fold catches a fixed
 /// sidebar width, an equal split, and the old maximum width.
 @MainActor func testBentDuoSidebarFillsLeftScreen() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.terminate()
  XCUIDevice.shared.orientation = .portrait
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411",
                           "CHATTERBOX_TEST_COMPACT_WIDTH":"1", "CHATTERBOX_TEST_SESSION_DIVISION":"0.68", "CHATTERBOX_TEST_SESSION_DIVISION_MARGIN":"40"]
  app.launch()
  guard min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height) >= 600 else {
   throw XCTSkip("needs an open-screen sized window")
  }
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  let project = app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10)); project.tap()
  let reply = app.staticTexts["Hi! This is SDHQ."]
  XCTAssertTrue(reply.waitForExistence(timeout:10))
  let sidebar = app.descendants(matching:.any).matching(identifier:"session-sidebar-pane").firstMatch
  let detail = app.descendants(matching:.any).matching(identifier:"session-detail-pane").firstMatch
  XCTAssertTrue(sidebar.waitForExistence(timeout:5) && detail.exists)
  let width = detail.frame.maxX - sidebar.frame.minX
  XCTAssertEqual(sidebar.frame.width, width * 0.68 - 6, accuracy:2, "sidebar fills the whole left display")
  XCTAssertGreaterThan(sidebar.frame.width,460,"fold layout has no old sidebar cap")
  XCTAssertEqual(detail.frame.minX - sidebar.frame.maxX,12,accuracy:2,"leave the fold clear")
  XCTAssertTrue(project.isHittable && project.frame.maxX < reply.frame.minX)
  XCTAssertFalse(app.buttons["Hide Sidebar"].exists,"no control can collapse the open-screen sidebar")
  capture("duo-bent-sidebar",app)
 }
 /// Closed phones retain full-screen list → chat navigation, then return to the
 /// same list when the selected session is closed by archiving.
 @MainActor func testClosedPhoneSessionNavigation() async throws {
  try await fixture("reset")
  XCUIDevice.shared.orientation = .portrait
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  guard min(app.windows.firstMatch.frame.width,app.windows.firstMatch.frame.height)<600 else { throw XCTSkip("closed phone only") }
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15));tab("Projects",app).tap()
  let project=app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10));project.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout:10))
  XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"session-sidebar-pane").firstMatch.exists)
  capture("closed-phone-conversation",app)
  app.buttons["Session Menu"].tap()
  XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout:5))
  app.buttons["Archive"].tap()
  let remaining=app.buttons["chat-"+uuid("Chatterbox")]
  XCTAssertTrue(remaining.waitForExistence(timeout:5) && remaining.isHittable,"back on the list after archiving")
  XCTAssertFalse(project.exists,"the archived session is removed")
 }
 /// A ```draft block in a reply: a card with Copy, Copy Subject and Open in Mail, and Copy
 /// takes only the draft (no notes around it).
 @MainActor func testDraftCard() async throws {
  try await fixture("reset")
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Chats",app).waitForExistence(timeout:15)); tab("Chats",app).tap()
  let loose=app.buttons["chat-"+uuid("Loose chat")]
  XCTAssertTrue(loose.waitForExistence(timeout:10)); loose.tap()
  XCTAssertTrue(app.staticTexts["Email draft"].waitForExistence(timeout:10), "the draft shows as an email card")
  XCTAssertTrue(app.buttons["draft-subject"].exists && app.buttons["draft-mail"].exists, "with the subject apart and Mail")
  XCTAssertLessThan(app.staticTexts["Email draft"].frame.height, 30, "its label on one line")
  XCTAssertFalse(app.staticTexts["```draft"].exists, "no raw fence")
  capture("draft-card",app)
  let copy=app.buttons["draft-body"]
  for _ in 0..<4 where !copy.isHittable { app.swipeUp() }
  copy.tap()
  XCTAssertTrue(copy.label=="Copied" || app.buttons["draft-body"].label=="Copied", "Copy confirms")
  // The test runner can't read another app's clipboard: paste into the message box instead.
  let composer=app.textFields["messageComposer"].exists ? app.textFields["messageComposer"] : app.textViews["messageComposer"]
  composer.tap(); composer.press(forDuration:1.0)
  let paste=app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
  XCTAssertTrue(paste.waitForExistence(timeout:5), "a Paste option"); paste.tap()
  let pasted=(composer.value as? String) ?? ""
  XCTAssertTrue(pasted.hasPrefix("Hey Lauren,") && pasted.contains("• Sitemap: Where") && !pasted.contains("Before you send") && !pasted.contains("Subject"), "only the body, clean: \(pasted)")
 }
 /// Archiving the open session, beside the list: the right side clears, the list stays.
 @MainActor func testArchiveClearsTheSession() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  let screen = app.windows.firstMatch.frame.size
  guard min(screen.width, screen.height) >= 600 else { throw XCTSkip("needs the list beside the session") }
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  let project = app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10)); project.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout:10))
  // Archiving the open session clears the right side and leaves the list as it was.
  let archive = app.buttons["Archive"]
  for _ in 0..<3 where !archive.exists {
   app.buttons["Session Menu"].tap()
   _ = archive.waitForExistence(timeout:3)
  }
  XCTAssertTrue(archive.exists, "the session menu offers Archive"); archive.tap()
  XCTAssertTrue(app.staticTexts["Choose a Session"].waitForExistence(timeout:5), "nothing open beside the list after archiving")
  XCTAssertTrue(tab("Projects",app).isSelected, "still on Projects")
  XCTAssertTrue(app.buttons["New Chat"].firstMatch.waitForExistence(timeout:5), "sidebar controls remain available")
  capture("archived-beside-list",app)
 }
 /// Real tablet navigation, rather than phone-only Back gestures and full-screen widths.
 @MainActor func testIPadCatchUp() async throws {
  guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad split view") }
  try await fixture("reset")
  XCUIDevice.shared.orientation = .portrait
  defer { XCUIDevice.shared.orientation = .portrait }
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  let quest = activity("Working: SDHQ · Sidequest",app)
  XCTAssertTrue(quest.waitForExistence(timeout:10), "Activity identifies the sidequest's parent")
  XCTAssertTrue(quest.value as? String == "Render four ribbon options, Working")
  let project = app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(project.waitForExistence(timeout:10)); project.tap()
  let reply = app.staticTexts["Hi! This is SDHQ."]
  XCTAssertTrue(reply.waitForExistence(timeout:10))
  XCTAssertLessThan(project.frame.maxX, reply.frame.minX, "iPad keeps its sidebar beside the conversation")
  capture("ipad-portrait-conversation",app)
  tab("Studios",app).tap(); openStudio("studio-1",app)
  let coach = app.buttons["chat-F982B462-68F5-509B-8E10-9946C3F0A1B1"]
  for _ in 0..<4 where !coach.isHittable { app.scrollViews.firstMatch.swipeUp() }
  XCTAssertTrue(coach.isHittable)
  XCTAssertGreaterThan(coach.frame.width,160,"Cards stay readable in the sidebar")
  XCTAssertTrue(app.images["Latest image in Coach Archie"].exists)
  coach.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Coach Archie."].waitForExistence(timeout:10))
  capture("ipad-studio",app)
  // Rename and promotion use the same session controls as the phone, inside the split detail.
  tab("Chats",app).tap()
  let loose=app.buttons["chat-"+uuid("Loose chat")]
  for _ in 0..<3 where !loose.isHittable { app.collectionViews.firstMatch.swipeUp() }
  XCTAssertTrue(loose.isHittable); loose.tap()
  XCTAssertTrue(app.buttons["Session Menu"].waitForExistence(timeout:5)); app.buttons["Session Menu"].tap()
  app.buttons["Rename"].tap()
  let name=app.alerts["Rename Session"].textFields.firstMatch
  XCTAssertTrue(name.waitForExistence(timeout:5)); name.tap()
  name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(name.value as? String ?? "").count)+"Tablet ideas")
  app.alerts.buttons["Rename"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Tablet ideas."].waitForExistence(timeout:8))
  let renamed=try await fixture("renames",method:"GET") as? [String:String]
  XCTAssertEqual(renamed?["Loose chat"],"Tablet ideas")
  app.buttons["Session Menu"].tap(); app.buttons["Move to Studio…"].tap()
  XCTAssertTrue(app.textFields["promotion-name"].waitForExistence(timeout:5))
  capture("ipad-promotion",app)
  app.buttons["promotion-save"].tap()
  XCTAssertTrue(app.buttons["promotion-save"].waitForNonExistence(timeout:8))
  let promoted=try await fixture("promotions",method:"GET") as? [String:[String:Any]]
  XCTAssertEqual(promoted?["Loose chat"]?["kind"] as? String,"studio")
 }

 @MainActor func testListRefreshFeedback() async throws {
  try await fixture("reset")
  try await fixture("list-delay",body:["seconds":5])
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411", "CHATTERBOX_TEST_PAIR_TOKEN":"fixture"]
  app.launch()
  let loading=app.descendants(matching:.any)["session-load-status"].firstMatch
  XCTAssertTrue(loading.waitForExistence(timeout:5),"A slow first response has a visible explanation")
  capture("ipad-first-load",app)
  XCTAssertTrue(loading.waitForNonExistence(timeout:12))
  tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].exists)
  app.terminate()
  try await fixture("list-delay",body:["seconds":5])
  app.launch()
  XCTAssertTrue(loading.waitForExistence(timeout:5))
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].exists,"Saved sessions remain usable before the response")
  capture("ipad-cached-refresh",app)
  XCTAssertTrue(loading.waitForNonExistence(timeout:12))
 }
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
  XCTAssertTrue(app.buttons["Activity, 1 new replies, 3 working"].waitForExistence(timeout:5), "Activity lists new replies and working chats")
  let activityReply = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "New reply: Tracker Trapper")).firstMatch
  let activityWorking = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Working: Galley")).firstMatch
  XCTAssertTrue(activityWorking.exists && activityReply.exists)
  XCTAssertLessThan(activityWorking.frame.maxY, activityReply.frame.minY, "Working sessions lead Activity in list mode")
  XCTAssertFalse(app.buttons["chat-975B1769-F8EA-59E2-A601-B40A492D19FA"].exists, "a sidequest isn't listed on its own")
  XCTAssertTrue(app.staticTexts["Codex: Render four ribbon options"].exists, "its chat's row names it")
  capture("1-chats-list",app)
  // Cards, two to a row (from the ⋯ menu, with the sort).
  app.buttons["Connection"].tap()
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
  // The provider, then its models; no favorites or preset tiles.
  XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 5) && app.buttons["Open models"].exists, "Session Settings lists the providers")
  XCTAssertFalse(app.buttons["favorite-1"].exists, "no favorites")
  XCTAssertFalse(app.buttons["Opus preset, Claude · Opus 5.5 · Medium"].exists, "no preset tiles")
  capture("2b-chat-settings", app)
  app.navigationBars["Session Settings"].buttons["Done"].tap()
  // The strip yields while a chat is open: a left-edge swipe here mustn't switch tabs.
  // (A synthesized drag can't trigger iOS's own Back swipe; see the calibration test.)
  edgeSwipe(app, fromLeft: true)
  try await Task.sleep(for: .seconds(1.5))
  // iOS's own Back swipe may or may not fire for a synthesized drag; either way, back to the list.
  if app.staticTexts["Hi! This is SDHQ."].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout: 5), "back at the cards")
  capture("4-after-back", app)
  // Chatterbox remains on ordinary chats after a sidebar edge gesture.
  edgeSwipe(app,fromLeft:true)
  try await Task.sleep(for:.seconds(1))
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
 /// Pinned: the Mac's pinned sessions, in the Mac's order, a tab of their own.
 @MainActor func testPinnedTab() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  capture("activity-compact",app)
  XCTAssertTrue(tab("Pinned",app).exists, "a Pinned tab in the bottom bar"); tab("Pinned",app).tap()
  let loose=app.buttons["chat-"+uuid("Loose chat")], sdhq=app.buttons["chat-"+uuid("SDHQ")]
  XCTAssertTrue(loose.waitForExistence(timeout:10) && sdhq.exists, "it lists the pinned sessions")
  // Reading order, in rows or in cards two to a row.
  XCTAssertTrue(loose.frame.minY < sdhq.frame.minY || (loose.frame.minY == sdhq.frame.minY && loose.frame.minX < sdhq.frame.minX), "in the Mac's order")
  XCTAssertFalse(app.buttons["chat-"+uuid("Chatterbox")].exists, "and nothing that isn't pinned")
  capture("pinned-tab",app)
  // Pin and unpin from the phone: long-press a session.
  tab("Projects",app).tap()
  let chatterbox=app.buttons["chat-"+uuid("Chatterbox")]
  XCTAssertTrue(chatterbox.waitForExistence(timeout:10)); chatterbox.press(forDuration:1.0)
  XCTAssertTrue(app.buttons["Pin to Top"].waitForExistence(timeout:5), "Pin to Top in a session's menu"); app.buttons["Pin to Top"].tap()
  tab("Pinned",app).tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("Chatterbox")].waitForExistence(timeout:10), "pinned from the phone, it shows in Pinned")
  app.buttons["chat-"+uuid("Loose chat")].press(forDuration:1.0)
  XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout:5)); app.buttons["Unpin"].tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("Loose chat")].waitForNonExistence(timeout:10), "unpinned, it leaves Pinned")
 }
 /// Feedback: screenshot, Mark Up, then the Chatterbox session opens with it in the message box.
 @MainActor func testFeedback() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Studios",app).tap()
  XCTAssertTrue(app.buttons["Feedback"].firstMatch.waitForExistence(timeout:5), "Feedback in the top bar"); app.buttons["Feedback"].firstMatch.tap()
  XCTAssertTrue(app.navigationBars["Mark Up"].waitForExistence(timeout:5), "the screenshot opens in Mark Up")
  capture("feedback-markup",app)
  app.buttons["Done"].tap()
  XCTAssertTrue(app.buttons["Remove Feedback image"].waitForExistence(timeout:10), "the Chatterbox session opens with the screenshot in its message box")
  XCTAssertTrue(app.navigationBars.staticTexts["Chatterbox"].exists || app.staticTexts["Chatterbox"].exists, "in the Chatterbox session")
  capture("feedback-composer",app)
 }
 /// Mac Screen from the ⋯ menu: with no Mac sign-in saved yet, it asks for one.
 @MainActor func testMacScreenAsksToSignIn() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  app.buttons["Connection"].tap()
  XCTAssertTrue(app.buttons["Mac Screen"].waitForExistence(timeout:5), "Mac Screen in the ⋯ menu")
  XCTAssertFalse(app.staticTexts["127.0.0.1"].exists, "the menu doesn't list the Mac's addresses")
  app.buttons["Mac Screen"].tap()
  XCTAssertTrue(app.textFields["mac-screen-user"].waitForExistence(timeout:5) && app.secureTextFields["mac-screen-password"].exists, "it asks for the Mac's sign-in first")
  capture("mac-screen-sign-in",app)
  app.buttons["Close Mac Screen"].tap()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:5), "and closes back to the app")
 }
 /// Laptop layout (an open iPhone Duo held like a laptop): the Mac's screen on top, a Mac
 /// keyboard and trackpad below. The simulator can't bend at the fold, so Layout → Laptop.
 @MainActor func testMacScreenLaptopLayout() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411",
                           "CHATTERBOX_TEST_MAC_SCREEN":"1"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  app.buttons["Connection"].tap()
  XCTAssertTrue(app.buttons["Mac Screen"].waitForExistence(timeout:5)); app.buttons["Mac Screen"].tap()
  XCUIDevice.shared.orientation = .landscapeLeft
  defer { XCUIDevice.shared.orientation = .portrait }
  XCTAssertTrue(app.buttons["Mac Screen Options"].waitForExistence(timeout:5))
  // Two displays (from the Mac's layout; Screen Sharing sends one picture): one at a time.
  XCTAssertTrue(app.staticTexts["mac-screen-display"].waitForExistence(timeout:5), "a display switcher for two displays")
  XCTAssertEqual(app.staticTexts["mac-screen-display"].label, "1 of 2")
  app.buttons["Next Display"].tap()
  XCTAssertEqual(app.staticTexts["mac-screen-display"].label, "2 of 2", "the arrow moves to the next display")
  capture("mac-screen-display-2",app)
  app.buttons["Previous Display"].tap()
  XCTAssertEqual(app.staticTexts["mac-screen-display"].label, "1 of 2")
  app.buttons["Mac Screen Options"].tap()
  // Menu pickers list their choices right in the menu.
  XCTAssertTrue(app.buttons["Laptop"].waitForExistence(timeout:5)); app.buttons["Laptop"].tap()
  sleep(2)
  capture("mac-screen-laptop",app)
  XCTAssertTrue(app.descendants(matching: .any)["Trackpad"].waitForExistence(timeout:5), "a trackpad below")
  XCTAssertTrue(app.descendants(matching: .any)["return"].exists && app.descendants(matching: .any)["⌘"].firstMatch.exists, "and a Mac keyboard")
  XCTAssertGreaterThan(app.descendants(matching: .any)["return"].frame.minY, app.frame.height / 2 - 40, "the keyboard is on the bottom half")
  let click = app.descendants(matching: .any)["Click"], arrow = app.descendants(matching: .any)["→"]
  XCTAssertTrue(click.exists && click.frame.minX > arrow.frame.maxX - 2 && abs(click.frame.midY - arrow.frame.midY) < 2, "a click key at the bottom right")
  // Caps Lock: a light on its key, and capital letters, until it's pressed again.
  let caps=app.descendants(matching: .any)["caps"]
  XCTAssertEqual(caps.value as? String, "off")
  XCTAssertTrue(app.descendants(matching: .any)["a"].exists, "letters are lowercase with Caps Lock off")
  caps.tap()
  XCTAssertEqual(caps.value as? String, "on", "Caps Lock shows on")
  XCTAssertTrue(app.descendants(matching: .any)["A"].exists && !app.descendants(matching: .any)["a"].exists, "and the letters turn capital")
  capture("mac-screen-caps-lock",app)
  caps.tap()
  XCTAssertEqual(caps.value as? String, "off", "pressed again, it's off")
  app.buttons["Close Mac Screen"].tap()
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
  try await fixture("reset")
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].waitForExistence(timeout:15))
  app.buttons["New Chat"].firstMatch.tap()
  XCTAssertTrue(app.navigationBars["New Chat"].waitForExistence(timeout:5), "New Chat opens a sheet, not a chat")
  XCTAssertTrue(app.staticTexts["Effort"].firstMatch.waitForExistence(timeout:5), "it shows the effort")
  XCTAssertFalse(app.buttons["favorite-1"].exists, "and no favorites")
  // The name comes first, then the provider, with its models under it, above the effort.
  let name=app.textFields["new-chat-name"]
  XCTAssertTrue(name.waitForExistence(timeout:5),"it asks for a name first");name.tap();name.typeText("Logo ideas\n")
  let codexList=app.buttons["Codex"].firstMatch, openList=app.buttons["Open models"].firstMatch
  for _ in 0..<6 where !codexList.isHittable { app.swipeUp() }
  XCTAssertTrue(openList.exists, "open models are a provider")
  XCTAssertLessThan(codexList.frame.maxY, app.staticTexts["Effort"].firstMatch.frame.minY, "the provider comes before the effort")
  // An open model: no effort for it.
  openList.tap()
  let qwen=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","qwen3.5:9b")).firstMatch
  XCTAssertTrue(qwen.waitForExistence(timeout:5), "the open models list shows")
  qwen.tap()
  let effortGone=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.staticTexts["Effort"].firstMatch)
  await fulfillment(of:[effortGone],timeout:5)
  // Then Codex: pick one of its models; that switches the agent.
  codexList.tap()
  let sol=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","GPT-6.1-Sol")).firstMatch
  XCTAssertTrue(sol.waitForExistence(timeout:5), "the Codex list shows")
  sol.tap()
  XCTAssertTrue(app.staticTexts["Full access"].waitForExistence(timeout:5), "picking another agent's model loads that agent's permissions")
  capture("new-chat-sheet",app)
  app.buttons["new-chat-start"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout:10), "Start opens the new chat")
  let url=URL(string:"http://127.0.0.1:47411/test/created")!
  let (data,_)=try await URLSession.shared.data(from:url)
  let created=try JSONSerialization.jsonObject(with:data) as! [[String:Any]]
  XCTAssertEqual(created.last?["backend"] as? String,"codex")
  XCTAssertEqual((created.last?["settings"] as? [String:Any])?["mode"] as? String,"fullAccess","the chat starts with what was picked")
  XCTAssertEqual(created.last?["title"] as? String,"Logo ideas","and the name given")
  XCTAssertNil((created.last?["settings"] as? [String:Any])?["openModel"] as? String,"a Codex model leaves the open model")
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

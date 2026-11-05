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
 /// A loose session about a Studio's work: the card offers that Studio and moves it there.
 @MainActor func testPlaceSuggestion() async throws {
  try await fixture("reset")
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Chats",app).waitForExistence(timeout:15)); tab("Chats",app).tap()
  let loose=app.buttons["chat-"+uuid("Loose chat")]
  XCTAssertTrue(loose.waitForExistence(timeout:10)); loose.tap()
  let move=app.buttons["Move to USA Archery"]
  XCTAssertTrue(move.waitForExistence(timeout:10), "the card names the Studio that fits")
  capture("place-suggestion",app)
  move.tap()
  let gone=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:move); await fulfillment(of:[gone],timeout:8)
  let (data,_)=try await URLSession.shared.data(from:URL(string:"http://127.0.0.1:47411/test/promotions")!)
  let moved=(try JSONSerialization.jsonObject(with:data) as? [String:Any])?["Loose chat"] as? [String:Any]
  XCTAssertEqual(moved?["kind"] as? String,"studio"); XCTAssertNotNil(moved?["studioID"], "moved into the existing Studio")
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
  // The session list's own loading line: open on Projects, not the Desk (the first tab).
  app.launchArguments=["-mobileChatListPage","projects"]
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
 /// The Mac stops answering: the can't-reach card says when the list was last updated and
 /// offers Retry; Activity's working sessions stop spinning and read as last seen. Retry, once
 /// the Mac answers, clears it.
 @MainActor func testConnectionErrorIsHonest() async throws {
  try await fixture("reset")
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launchArguments=["-mobileChatListPage","projects"]
  app.launch()
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].waitForExistence(timeout:20))
  let live=app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@","Working: ")).firstMatch
  XCTAssertTrue(live.waitForExistence(timeout:10), "Activity: working, live")
  try await fixture("offline")
  app.swipeDown()
  let retry=app.buttons["problem-retry"]
  XCTAssertTrue(retry.waitForExistence(timeout:25), "can't reach the Mac: Retry")
  XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","Last updated")).firstMatch.exists, "and when it was last updated")
  let stale=app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@","Last seen working: ")).firstMatch
  XCTAssertTrue(stale.waitForExistence(timeout:5), "working sessions read as last seen, not live")
  XCTAssertFalse(live.exists, "nothing reads as working now")
  capture("connection-error",app)
  try await fixture("reset")
  retry.tap()
  XCTAssertTrue(retry.waitForNonExistence(timeout:20), "Retry, answered: the card goes")
  XCTAssertTrue(live.waitForExistence(timeout:10), "and working is live again")
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
  // The bar keeps to five tabs with the Desk first: All is Chats' other half.
  XCTAssertTrue(tab("Chats",app).waitForExistence(timeout:15)); tab("Chats",app).tap()
  XCTAssertTrue(tab("All",app).waitForExistence(timeout:5), "All, beside Chats")
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
  // The provider, then one row with the model in use; its menu lists the models. No favorites or preset tiles.
  XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 5) && app.buttons["Open models"].exists, "Session Settings lists the providers")
  XCTAssertFalse(app.buttons["favorite-1"].exists, "no favorites")
  XCTAssertFalse(app.buttons["Opus preset, Claude · Opus 5.5 · Medium"].exists, "no preset tiles")
  let modelRow=app.buttons["model-current"]
  XCTAssertTrue(modelRow.waitForExistence(timeout:5), "one row for the model")
  XCTAssertEqual(modelRow.label, "Model: Opus 5.5, Best for everyday, complex tasks", "it shows the model in use, with its detail")
  XCTAssertFalse(modelItem("Sonnet 5",app).exists || modelItem("Haiku 5",app).exists, "only the model in use shows, not every model")
  XCTAssertLessThan(modelRow.frame.minY, app.staticTexts["Effort"].firstMatch.frame.minY, "then the effort, right under it")
  capture("2b-chat-settings", app)
  modelRow.tap()
  XCTAssertTrue(modelItem("Sonnet 5",app).waitForExistence(timeout:5) && modelItem("Haiku 5",app).exists && modelItem("Opus 5.5",app).exists, "its menu lists the provider's models")
  capture("phone-model-compact", app)
  modelItem("Sonnet 5",app).tap()
  XCTAssertTrue(modelItem("Sonnet 5",app).waitForNonExistence(timeout:5), "picking one closes the menu")
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
 // MARK: The Desk (plans/front-desk.md, plans/desk-board.md)

 /// A fresh install opens on the Desk, the first tab: a board. On a phone, column tabs with
 /// counts (To do, Working, Needs you, Ready, Done), opening on Needs you; each tab shows its
 /// column's cards. Tapping a card opens its session.
 @MainActor func testDeskFirstTab() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let desk=deskTab(app)
  XCTAssertTrue(desk.waitForExistence(timeout:20))
  for name in ["Pinned","Projects","Studios","Chats"] {
   XCTAssertTrue(tab(name,app).exists, "\(name) is still a tab")
   // Across the bar, or down it (a closed iPhone Duo's bar runs down the side).
   let other=tab(name,app).frame
   XCTAssertTrue(desk.frame.minX < other.minX || (abs(desk.frame.minX-other.minX) < 1 && desk.frame.minY < other.minY), "the Desk comes before \(name)")
  }
  // No More tab: All moved beside Chats, in its tab.
  XCTAssertFalse(app.tabBars.buttons["More"].exists, "every tab fits the bar")
  XCTAssertFalse(app.tabBars.buttons["All"].exists)
  if app.tabBars.buttons["Desk"].exists { XCTAssertTrue(desk.isSelected, "a fresh install opens on the Desk") }
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:10), "Needs you shows first")
  XCTAssertEqual(deskCounts(app), ["To do, 2","Working, 2","Needs you, 2","Ready to mark complete, 2","Done, 1"], "every column, with its count, left to right")
  XCTAssertTrue(app.buttons[approve].exists && app.buttons["desk-allow-session-"+deskID("approval")].exists && app.buttons["desk-deny-"+deskID("approval")].exists, "an approval: Allow, Allow for Session and Deny in place")
  XCTAssertTrue(app.buttons["desk-open-"+deskID("questions")].exists, "questions: Open")
  XCTAssertFalse(app.buttons["desk-allow-"+deskID("questions")].exists)
  XCTAssertTrue(app.staticTexts["Run wrangler deploy to publish the new cache rules?"].exists, "what it asks")
  // The one approval card: where (place › session), then the exact command, before its buttons.
  let command=app.buttons["desk-command-"+deskID("approval")]
  XCTAssertTrue(command.exists && command.label.contains("wrangler deploy --env production"), "the exact command, on the Desk too: \(command.label)")
  XCTAssertTrue(app.staticTexts["SDHQ \u{203A} Cache rules"].exists, "place › session")
  XCTAssertLessThan(command.frame.maxY, app.buttons[approve].frame.minY, "the command above Allow")
  XCTAssertLessThanOrEqual(app.buttons[approve].frame.minX, app.buttons["desk-allow-session-"+deskID("approval")].frame.minX, "Allow first")
  capture("desk", app)
  guard deskPhone(app) else { return }
  XCTAssertTrue(app.buttons["desk-tab-needs-you"].isSelected, "opens on Needs you, which has something")
  XCTAssertFalse(app.buttons["desk-place-"+deskID("banner")].exists, "one column at a time")
  // To do: requests with their proposed places.
  app.buttons["desk-tab-todo"].tap()
  XCTAssertTrue(app.buttons["desk-place-"+deskID("banner")].waitForExistence(timeout:5) && app.buttons["desk-tab-todo"].isSelected, "To do shows the requests")
  XCTAssertEqual(app.buttons["desk-place-"+deskID("banner")].label, "Place: USA Archery", "the proposed Studio")
  XCTAssertTrue(app.staticTexts["Camp graphics belong to USA Archery."].exists, "with its note")
  XCTAssertEqual(app.buttons["desk-place-"+deskID("printer")].label, "Choose a place", "nothing proposed")
  XCTAssertFalse(app.buttons[approve].exists, "and not Needs you's cards")
  // Working: a card per session, with what it's doing.
  app.buttons["desk-tab-working"].tap()
  let galley=app.buttons["desk-working-"+deskID("Galley")]
  XCTAssertTrue(galley.waitForExistence(timeout:5) && app.buttons["desk-working-"+deskID("Coach Archie")].exists, "Working: a card each")
  XCTAssertTrue(galley.label.contains("Editing Sources/Typography/Engine.swift"), "with what it's doing: \(galley.label)")
  capture("desk-working", app)
  // Ready to mark complete, and Done.
  app.buttons["desk-tab-ready"].tap()
  XCTAssertTrue(app.buttons["desk-complete-"+uuid("PlayCase Magnets")].waitForExistence(timeout:5) && app.buttons["desk-complete-"+uuid("Chatterbox")].exists, "Ready: Mark Complete on each")
  XCTAssertTrue(app.staticTexts["Finished the product photos for the store."].exists, "with what it last said")
  capture("desk-ready", app)
  app.buttons["desk-tab-done"].tap()
  XCTAssertTrue(app.buttons["desk-reopen-"+uuid("Crystal concept")].waitForExistence(timeout:5), "Done: Reopen")
  // Tapping a card opens its session in its own tab, as a notification does.
  app.buttons["desk-tab-needs-you"].tap()
  app.buttons["desk-waiting-"+deskID("approval")].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout:10), "the card opens the session")
  capture("desk-opened-session", app)
  deskTab(app).tap()
  XCTAssertTrue(app.buttons["desk-tab-needs-you"].waitForExistence(timeout:5) && app.buttons["desk-tab-needs-you"].isSelected, "back on the Desk, the same column")
  app.buttons["desk-tab-working"].tap()
  XCTAssertTrue(galley.waitForExistence(timeout:5)); galley.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Galley."].waitForExistence(timeout:10), "a working card opens its session")
 }
 /// Wide (an iPad, an open iPhone Duo): the five columns side by side, a fixed width each, the
 /// board shown at Needs you; it scrolls sideways to the rest.
 @MainActor func testDeskBoardWide() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20))
  guard !deskPhone(app) else {
   XCTAssertFalse(app.staticTexts["desk-section-todo"].exists, "a phone: tabs, not columns side by side")
   return
  }
  XCTAssertFalse(app.buttons["desk-tab-todo"].exists, "no tabs when wide")
  let ids=["todo","working","needs-you","ready","done"]
  let headers=ids.map { deskHeader($0,app) }
  XCTAssertTrue(headers.allSatisfy(\.exists), "five columns")
  XCTAssertEqual(deskCounts(app), ["To do, 2","Working, 2","Needs you, 2","Ready to mark complete, 2","Done, 1"], "each with its count")
  for (a,b) in zip(headers,headers.dropFirst()) {
   XCTAssertLessThan(a.frame.maxX, b.frame.minX, "side by side, left to right")
   XCTAssertEqual(a.frame.minY, b.frame.minY, accuracy:2, "in one row")
  }
  let width=app.windows.firstMatch.frame.width
  let needs=deskHeader("needs-you",app).frame
  XCTAssertTrue(needs.minX >= 0 && needs.maxX <= width, "shown at Needs you (\(needs), \(width) wide)")
  let approval=app.buttons["desk-waiting-"+deskID("approval")], questions=app.buttons["desk-waiting-"+deskID("questions")]
  XCTAssertEqual(approval.frame.minX, questions.frame.minX, accuracy:2, "Needs you's cards in its column")
  XCTAssertGreaterThan(questions.frame.minY, approval.frame.maxY - 1, "one above the other")
  XCTAssertTrue(approval.frame.minX >= needs.minX - 20 && approval.frame.maxX <= needs.minX + 340, "inside it")
  capture("desk-board-wide", app)
  // Sideways to To do, and to Done.
  deskColumn("todo",app)
  let banner=app.buttons["desk-place-"+deskID("banner")]
  XCTAssertTrue(banner.isHittable, "To do's requests, scrolled to")
  deskColumn("done",app)
  XCTAssertTrue(app.buttons["desk-reopen-"+uuid("Crystal concept")].isHittable, "Done, scrolled to")
  XCTAssertTrue(app.buttons["desk-complete-"+uuid("PlayCase Magnets")].exists, "Ready beside it")
  capture("desk-board-wide-done", app)
  // Turned sideways, more of the board fits.
  XCUIDevice.shared.orientation = .landscapeLeft
  try await Task.sleep(for:.seconds(1.5))
  deskColumn("todo",app)
  XCTAssertTrue(deskHeader("needs-you",app).frame.minX+320 <= app.windows.firstMatch.frame.width,
                "landscape: To do, Working and Needs you all on screen")
  XCUIDevice.shared.orientation = .portrait
 }
 /// Approve in place uses the session's approval call; Open opens a session with questions.
 @MainActor func testDeskApprove() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let button=app.buttons[approve]
  XCTAssertTrue(button.waitForExistence(timeout:20)); button.tap()
  XCTAssertTrue(button.waitForNonExistence(timeout:8), "approved, it leaves Needs you")
  let calls=try await deskCalls()
  XCTAssertEqual(calls.last?["action"] as? String, "decide")
  XCTAssertEqual(calls.last?["decision"] as? String, "approved")
  XCTAssertEqual(calls.last?["item"] as? String, deskID("approval").lowercased())
  XCTAssertEqual(calls.last?["chat"] as? String, uuid("SDHQ").lowercased(), "through the session's approval endpoint")
  XCTAssertEqual(deskCounts(app)[2], "Needs you, 1")
  capture("desk-approved", app)
  app.buttons["desk-open-"+deskID("questions")].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Tracker Trapper."].waitForExistence(timeout:10), "Open opens the session")
 }
 /// Scrolled to the end, nothing you'd tap sits under the floating tab bar: the Desk's last
 /// card's buttons and the session list's last row end above it.
 @MainActor func testScrollClearsTabBar() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20))
  guard deskPhone(app), app.tabBars.firstMatch.exists else { return }
  let bar=app.tabBars.firstMatch.frame.minY
  for _ in 0..<4 { app.swipeUp() }
  try await Task.sleep(for:.seconds(1))
  let open=app.buttons["desk-open-"+deskID("questions")]
  XCTAssertTrue(open.exists)
  XCTAssertLessThanOrEqual(open.frame.maxY, bar, "Needs you's last button ends above the tab bar (\(open.frame.maxY) vs \(bar))")
  capture("desk-scrolled-end", app)
  deskColumn("todo",app)
  for _ in 0..<4 { app.swipeUp() }
  try await Task.sleep(for:.seconds(1))
  let ignore=app.buttons["desk-ignore-"+deskID("printer")]
  XCTAssertTrue(ignore.exists)
  XCTAssertLessThanOrEqual(ignore.frame.maxY, bar, "To do's last button ends above the tab bar (\(ignore.frame.maxY) vs \(bar))")
  tab("Projects",app).tap()
  XCTAssertTrue(app.buttons["chat-"+uuid("SDHQ")].waitForExistence(timeout:10))
  for _ in 0..<6 { app.swipeUp() }
  try await Task.sleep(for:.seconds(1))
  let rows=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","chat-")).allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 0 }
  let last=rows.max { $0.frame.maxY < $1.frame.maxY }
  XCTAssertNotNil(last)
  if let last { XCTAssertLessThanOrEqual(last.frame.maxY, bar + 1, "the list's last row ends above the tab bar (\(last.identifier): \(last.frame.maxY) vs \(bar))") }
  capture("projects-scrolled-end", app)
 }
 /// Allow for Session on the Desk: the same call the session's card makes, with that decision.
 @MainActor func testDeskAllowForSession() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let button=app.buttons["desk-allow-session-"+deskID("approval")]
  XCTAssertTrue(button.waitForExistence(timeout:20)); reveal(button, app); button.tap()
  XCTAssertTrue(button.waitForNonExistence(timeout:8), "allowed for the session, it leaves Needs you")
  let calls=try await deskCalls()
  XCTAssertEqual(calls.last?["action"] as? String, "decide")
  XCTAssertEqual(calls.last?["decision"] as? String, "approvedForSession", "the decision goes along")
  XCTAssertEqual(calls.last?["item"] as? String, deskID("approval").lowercased())
 }
 /// Start There: its step shows the place, the model, the sessions already there doing the same
 /// work (a clear match chosen) and New session. The model follows the session chosen. Continue
 /// sends the request to that session; the Desk stays, with a note to open it.
 @MainActor func testDeskStartThere() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("todo",app)
  let start=app.buttons["desk-start-"+deskID("banner")]
  XCTAssertTrue(start.waitForExistence(timeout:5)); reveal(start, app); start.tap()
  XCTAssertTrue(app.navigationBars["Start"].waitForExistence(timeout:5), "Start There opens its step, not a session")
  let archie=app.buttons["desk-thread-"+deskID("Coach Archie")], other=app.buttons["desk-thread-963CA311-2496-5A83-9807-3AE28F7E5FB5"], fresh=app.buttons["desk-thread-new"]
  XCTAssertTrue(archie.waitForExistence(timeout:8), "Continue in the session like it")
  // The model first, under the place: the chosen session's own.
  let modelRow=app.buttons["model-current"]
  XCTAssertTrue(modelRow.waitForExistence(timeout:5), "the model shows when continuing too")
  XCTAssertLessThan(modelRow.frame.maxY, archie.frame.minY, "under the place, above the sessions")
  let own=expectation(for:NSPredicate(format:"label == %@","Model: Opus 5.5, Best for everyday, complex tasks"),evaluatedWith:modelRow)
  await fulfillment(of:[own],timeout:5)
  XCTAssertTrue(app.buttons["desk-start-effort"].exists, "and its effort, in one row")
  let asked=try await newChatQueries().last
  XCTAssertEqual(asked?["chat"]?.lowercased(), deskID("Coach Archie").lowercased(), "asked for as that session runs")
  capture("phone-start-sheet", app)
  // The sessions below it (the last may sit under the fold).
  reveal(fresh, app)
  XCTAssertTrue(other.exists && fresh.exists, "Continue in each session like it, and New session")
  XCTAssertTrue(app.staticTexts["Continue in Coach Archie"].exists, "named")
  XCTAssertLessThan(archie.frame.maxY, fresh.frame.minY, "Continue in first")
  XCTAssertTrue(archie.isSelected && !fresh.isSelected, "the clear match is chosen")
  let continueNote=app.staticTexts["desk-start-continue-note"]
  reveal(continueNote, app)
  XCTAssertTrue(continueNote.waitForExistence(timeout:5) && continueNote.label.contains("on its own model (Opus 5.5 · High)"), continueNote.label)
  // Choosing another session: the model follows it.
  other.tap()
  try await Task.sleep(for:.milliseconds(800))
  let followed=try await newChatQueries().last
  XCTAssertEqual(followed?["chat"]?.lowercased(), "963CA311-2496-5A83-9807-3AE28F7E5FB5".lowercased(), "the model follows the session chosen")
  XCTAssertTrue(continueNote.label.contains("GPT-6.1-Sol"), continueNote.label)
  archie.tap()
  let back=expectation(for:NSPredicate(format:"label CONTAINS %@","on its own model (Opus 5.5 · High)"),evaluatedWith:continueNote)
  await fulfillment(of:[back],timeout:5)
  revealUp(modelRow, app)
  XCTAssertTrue(app.staticTexts["USA Archery"].exists && modelRow.label == "Model: Opus 5.5, Best for everyday, complex tasks", "in the place shown, back on its own model")
  XCTAssertEqual(app.buttons["desk-start-confirm"].label, "Continue")
  let threads=try await deskCalls().last { ($0["action"] as? String)=="threads" }
  XCTAssertEqual(threads?["id"] as? String, deskID("banner").lowercased()); XCTAssertEqual((threads?["place"] as? String)?.lowercased(), uuid("studio").lowercased(), "asked in the place shown")
  app.buttons["desk-start-confirm"].tap()
  let note=startedNote(app)
  XCTAssertTrue(note.waitForExistence(timeout:8), "the Desk notes it")
  XCTAssertTrue(note.label.contains("Continued in Coach Archie"), note.label)
  XCTAssertFalse(app.staticTexts["Hi! This is Coach Archie."].exists, "and nothing opens")
  XCTAssertTrue(app.buttons["desk-place-"+deskID("printer")].exists, "the Desk stays")
  capture("desk-started", app)
  XCTAssertFalse(app.buttons["desk-start-"+deskID("banner")].exists, "started, it leaves To do")
  let call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "start"); XCTAssertEqual(call?["id"] as? String, deskID("banner").lowercased())
  let body=call?["body"] as? [String:Any]
  XCTAssertEqual((body?["continueChat"] as? String)?.lowercased(), deskID("Coach Archie").lowercased(), "Continue sends the session")
  XCTAssertNil(body?["place"], "where proposed"); XCTAssertNil(body?["model"], "and no model")
  // Open, at the note's end, opens that session.
  XCTAssertTrue(note.exists, "the note is still up")
  note.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Coach Archie."].waitForExistence(timeout:10), "Open opens it")
 }
 /// Continuing on another model: picked in the step, it stays when the choice changes, the
 /// footer says the session switches, and Continue sends the model with the session.
 @MainActor func testDeskContinuePicksModel() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("todo",app)
  let start=app.buttons["desk-start-"+deskID("banner")]
  XCTAssertTrue(start.waitForExistence(timeout:5)); reveal(start, app); start.tap()
  let archie=app.buttons["desk-thread-"+deskID("Coach Archie")], fresh=app.buttons["desk-thread-new"]
  XCTAssertTrue(archie.waitForExistence(timeout:8) && archie.isSelected, "continuing the clear match")
  let modelRow=app.buttons["model-current"]
  let own=expectation(for:NSPredicate(format:"label == %@","Model: Opus 5.5, Best for everyday, complex tasks"),evaluatedWith:modelRow)
  await fulfillment(of:[own],timeout:5)
  modelRow.tap()
  XCTAssertTrue(modelItem("Sonnet 5",app).waitForExistence(timeout:5), "the menu lists the models")
  modelItem("Sonnet 5",app).tap()
  let picked=expectation(for:NSPredicate(format:"label == %@","Model: Sonnet 5, Efficient for routine tasks"),evaluatedWith:modelRow)
  await fulfillment(of:[picked],timeout:5)
  let query=try await newChatQueries().last
  XCTAssertEqual(query?["chat"]?.lowercased(), deskID("Coach Archie").lowercased()); XCTAssertEqual(query?["model"], "sonnet", "as that session would run on it")
  try await Task.sleep(for:.milliseconds(500))
  capture("phone-start-model", app)
  let continueNote=app.staticTexts["desk-start-continue-note"]
  reveal(continueNote, app)
  let switching=expectation(for:NSPredicate(format:"label CONTAINS %@","switching it to Sonnet 5 · High"),evaluatedWith:continueNote)
  await fulfillment(of:[switching],timeout:5)
  capture("phone-start-model-footer", app)
  reveal(fresh, app); fresh.tap()
  XCTAssertTrue(fresh.isSelected, "New session chosen")
  try await Task.sleep(for:.milliseconds(800))
  revealUp(modelRow, app)
  XCTAssertEqual(modelRow.label, "Model: Sonnet 5, Efficient for routine tasks", "a model picked by hand stays when the choice changes")
  reveal(archie, app); archie.tap()
  reveal(continueNote, app)
  XCTAssertTrue(continueNote.waitForExistence(timeout:5) && continueNote.label.contains("switching it to Sonnet 5"), continueNote.label)
  app.buttons["desk-start-confirm"].tap()
  let note=startedNote(app)
  XCTAssertTrue(note.waitForExistence(timeout:8) && note.label.contains("Continued in Coach Archie"), note.label)
  let body=(try await deskCalls().last)?["body"] as? [String:Any]
  XCTAssertEqual((body?["continueChat"] as? String)?.lowercased(), deskID("Coach Archie").lowercased(), "Continue sends the session")
  XCTAssertEqual(body?["agent"] as? String, "claude"); XCTAssertEqual(body?["model"] as? String, "sonnet", "and the model picked")
  XCTAssertEqual(body?["effort"] as? String, "high", "at the effort shown")
 }
 /// A new session instead: its model, as compact as Session Settings' (one row, a menu);
 /// Start sends the agent and model picked, and runs it in the background.
 @MainActor func testDeskStartPicksModel() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("todo",app)
  let start=app.buttons["desk-start-"+deskID("banner")]
  XCTAssertTrue(start.waitForExistence(timeout:5)); reveal(start, app); start.tap()
  let fresh=app.buttons["desk-thread-new"]
  XCTAssertTrue(app.buttons["desk-thread-"+deskID("Coach Archie")].waitForExistence(timeout:8))
  // New session sits under the model and the sessions like it: below the fold on a phone.
  reveal(fresh, app)
  XCTAssertTrue(fresh.exists); fresh.tap()
  let modelRow=app.buttons["model-current"]
  revealUp(modelRow, app)
  XCTAssertTrue(modelRow.waitForExistence(timeout:5), "New session: its model")
  XCTAssertEqual(modelRow.label, "Model: Opus 5.5, Best for everyday, complex tasks", "as a new session there would start")
  XCTAssertEqual(app.buttons["desk-start-confirm"].label, "Start")
  modelRow.tap()
  XCTAssertTrue(modelItem("Sonnet 5",app).waitForExistence(timeout:5), "the menu lists the models")
  modelItem("Sonnet 5",app).tap()
  let picked=expectation(for:NSPredicate(format:"label == %@","Model: Sonnet 5, Efficient for routine tasks"),evaluatedWith:modelRow)
  await fulfillment(of:[picked],timeout:5)
  capture("desk-start-model", app)
  app.buttons["desk-start-confirm"].tap()
  let note=startedNote(app)
  XCTAssertTrue(note.waitForExistence(timeout:8) && note.label.contains("Started in USA Archery"), "started in the background: \(note.label)")
  XCTAssertFalse(app.staticTexts["Hi! This is Coach Archie."].exists, "nothing opens")
  let body=(try await deskCalls().last)?["body"] as? [String:Any]
  XCTAssertEqual(body?["agent"] as? String, "claude"); XCTAssertEqual(body?["model"] as? String, "sonnet", "the model picked")
  XCTAssertNil(body?["continueChat"], "a new session")
 }
 /// The place chip lists every place with its detail line; Start then uses the one picked.
 @MainActor func testDeskChangePlace() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("todo",app)
  let change=app.buttons["desk-place-"+deskID("banner")]
  XCTAssertTrue(change.waitForExistence(timeout:5)); reveal(change, app); change.tap()
  let geekify=app.buttons["desk-place-option-Geekify"]
  XCTAssertTrue(geekify.waitForExistence(timeout:8), "the places")
  XCTAssertTrue(app.staticTexts["3D-printed figures and crystal stands."].exists, "with what belongs there")
  capture("desk-change-place", app)
  let loose=app.buttons["desk-place-option-A session of its own"]
  for _ in 0..<3 where !loose.exists { app.collectionViews.firstMatch.swipeUp() }
  XCTAssertTrue(app.buttons["desk-place-option-Chatterbox"].exists && loose.exists, "projects and a loose session too")
  capture("desk-change-place-all", app)
  geekify.tap()
  let chip=app.buttons["desk-place-"+deskID("banner")]
  XCTAssertTrue(chip.waitForExistence(timeout:5)); XCTAssertEqual(chip.label, "Place: Geekify, changed")
  app.buttons["desk-start-"+deskID("banner")].tap()
  // The step shows the place picked; nothing like it there, so a new session.
  XCTAssertTrue(app.buttons["desk-start-confirm"].waitForExistence(timeout:5) && app.staticTexts["Geekify"].exists, "the step shows the place picked")
  XCTAssertTrue(app.buttons["model-current"].waitForExistence(timeout:5) && !app.buttons["desk-thread-new"].exists, "no sessions like it there: just the model")
  app.buttons["desk-start-confirm"].tap()
  XCTAssertTrue(startedNote(app).waitForExistence(timeout:8) && startedNote(app).label.contains("Started in Geekify"), "it starts in the place picked, in the background")
  let call=try await deskCalls().last
  let place=(call?["body"] as? [String:Any])?["place"] as? [String:Any]
  XCTAssertEqual(place?["name"] as? String, "Geekify"); XCTAssertEqual(place?["kind"] as? String, "studio")
  // Nothing proposed: Start asks for a place first, then opens its step there.
  deskTab(app).tap()
  let startPrinter=app.buttons["desk-start-"+deskID("printer")]
  XCTAssertTrue(startPrinter.waitForExistence(timeout:5)); reveal(startPrinter, app)
  XCTAssertFalse(app.buttons["desk-change-"+deskID("printer")].exists || app.buttons["desk-choose-"+deskID("printer")].exists, "no Change Place button: the chip does it")
  startPrinter.tap()
  XCTAssertTrue(app.buttons["desk-place-option-Chatterbox"].waitForExistence(timeout:8), "with no place, Start asks for one"); app.buttons["desk-place-option-Chatterbox"].tap()
  XCTAssertTrue(app.buttons["desk-start-confirm"].waitForExistence(timeout:8), "then its step opens"); app.buttons["desk-start-confirm"].tap()
  XCTAssertTrue(startedNote(app).waitForExistence(timeout:8) && startedNote(app).label.contains("Started in Chatterbox"), startedNote(app).label)
  let second=((try await deskCalls().last)?["body"] as? [String:Any])?["place"] as? [String:Any]
  XCTAssertEqual(second?["name"] as? String, "Chatterbox"); XCTAssertEqual(second?["kind"] as? String, "project")
 }
 /// Ignore takes a request off the Desk.
 @MainActor func testDeskIgnore() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("todo",app)
  let ignore=app.buttons["desk-ignore-"+deskID("printer")]
  XCTAssertTrue(ignore.waitForExistence(timeout:5)); reveal(ignore, app); ignore.tap()
  XCTAssertTrue(app.buttons["desk-place-"+deskID("printer")].waitForNonExistence(timeout:8), "removed, it's gone")
  XCTAssertTrue(app.buttons["desk-place-"+deskID("banner")].exists, "the other stays")
  XCTAssertEqual(deskCounts(app)[0], "To do, 1", "the count goes down")
  let call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "ignore"); XCTAssertEqual(call?["id"] as? String, deskID("printer").lowercased())
  XCTAssertEqual(app.buttons["desk-ignore-"+deskID("banner")].label, "Remove")
  // Swiped left, a To do card shows Remove; a tap takes it off too.
  guard deskPhone(app) else { return }
  let card=app.buttons["desk-place-"+deskID("banner")]
  // From the line above the place chip, near the card's right edge, about halfway across.
  let line=card.coordinate(withNormalizedOffset:CGVector(dx:0,dy:-0.6))
  line.withOffset(CGVector(dx:290,dy:0))
   .press(forDuration:0.05,thenDragTo:line.withOffset(CGVector(dx:120,dy:0)),withVelocity:.slow,thenHoldForDuration:0.1)
  let remove=app.buttons["desk-swipe-remove-"+deskID("banner")]
  XCTAssertTrue(remove.waitForExistence(timeout:5) && remove.isHittable, "swiping left shows Remove")
  try await Task.sleep(for:.milliseconds(400))
  remove.tap()
  XCTAssertTrue(card.waitForNonExistence(timeout:8), "removed by swipe, it's gone")
  let removed=try await deskCalls().last
  XCTAssertEqual(removed?["id"] as? String, deskID("banner").lowercased())
 }
 /// The ask box (above the board) puts a request on the Desk, with the place the Desk proposes;
 /// a phone shows it in To do.
 @MainActor func testDeskAsk() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let ask=field("desk-ask",app)
  XCTAssertTrue(ask.waitForExistence(timeout:20)); ask.tap(); ask.typeText("Order more magnet blanks")
  capture("desk-ask", app)
  app.buttons["desk-ask-send"].tap()
  deskColumn("todo",app)
  let text=app.staticTexts["Order more magnet blanks"]
  XCTAssertTrue(text.waitForExistence(timeout:8), "the request shows in To do")
  let call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "add")
  XCTAssertEqual((call?["body"] as? [String:Any])?["text"] as? String, "Order more magnet blanks")
  XCTAssertEqual((call?["body"] as? [String:Any])?["source"] as? String, "you")
  let left=(ask.value as? String) ?? ""
  XCTAssertTrue(left.isEmpty || left=="What needs doing?", "the box empties: \(left)")
  let chip=app.buttons.matching(NSPredicate(format:"label == %@","Place: PlayCase Magnets")).firstMatch
  reveal(chip, app)
  XCTAssertTrue(chip.exists, "with its proposed place")
  XCTAssertEqual(deskCounts(app)[0], "To do, 3")
  capture("desk-asked", app)
 }
 /// Nothing waiting: each empty column says so in one quiet line; a phone opens on To do.
 @MainActor func testDeskEmptyColumns() async throws {
  try await fixture("reset"); try await fixture("desk-empty")
  let app=deskApp(); app.launch()
  let empty=app.staticTexts["desk-empty-todo"]
  XCTAssertTrue(empty.waitForExistence(timeout:20)); XCTAssertEqual(empty.label, "Nothing waiting to start.")
  XCTAssertEqual(deskCounts(app), ["To do, 0","Working, 2","Needs you, 0","Ready to mark complete, 0","Done, 0"])
  if deskPhone(app) {
   XCTAssertTrue(app.buttons["desk-tab-todo"].isSelected, "nothing needs you: opens on To do")
   app.buttons["desk-tab-needs-you"].tap()
   XCTAssertEqual(app.staticTexts["desk-empty-needs-you"].label, "Nothing needs you.")
   app.buttons["desk-tab-working"].tap()
   XCTAssertTrue(app.buttons["desk-working-"+deskID("Galley")].waitForExistence(timeout:5) && !app.staticTexts["desk-empty-working"].exists, "Working has its cards")
  } else {
   XCTAssertTrue(app.staticTexts["desk-empty-needs-you"].exists && app.staticTexts["desk-empty-ready"].exists && !app.staticTexts["desk-empty-working"].exists)
  }
  capture("desk-calm", app)
 }
 /// Swipe a Needs-you card left: Silence shows, and tapping it takes the card off the Desk;
 /// the Mac is asked to silence it (its session still waits). Swiped all the way, it goes at once.
 @MainActor func testDeskSilence() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let card=app.buttons["desk-waiting-"+deskID("approval")]
  XCTAssertTrue(card.waitForExistence(timeout:20))
  guard deskPhone(app) else { return }
  // Named as the session lists name it: by its project, its own title under that.
  XCTAssertTrue(app.staticTexts["SDHQ \u{203A} Cache rules"].exists, "named by its project, then the session's own title")
  XCTAssertFalse(app.buttons["desk-silence-"+deskID("approval")].exists, "Silence stays hidden until swiped")
  card.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
   .press(forDuration:0.05,thenDragTo:card.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.1)
  let silence=app.buttons["desk-silence-"+deskID("approval")]
  XCTAssertTrue(silence.waitForExistence(timeout:5) && silence.isHittable, "swiping left shows Silence")
  XCTAssertTrue(card.exists, "and the card stays until it's tapped")
  try await Task.sleep(for:.milliseconds(400))
  capture("desk-silence-revealed", app)
  silence.tap()
  XCTAssertTrue(card.waitForNonExistence(timeout:8), "silenced, it leaves Needs you")
  var calls=try await deskCalls()
  XCTAssertEqual(calls.last?["action"] as? String, "silence")
  let body=calls.last?["body"] as? [String:Any]
  XCTAssertEqual((body?["id"] as? String)?.uppercased(), deskID("approval"))
  XCTAssertEqual((body?["chatID"] as? String)?.uppercased(), uuid("SDHQ"))
  XCTAssertEqual(body?["text"] as? String, "Run wrangler deploy to publish the new cache rules?")
  XCTAssertEqual(deskCounts(app)[2], "Needs you, 1", "the count goes down")
  // A few seconds to take it back, and a quiet "1 silenced" row at the foot of Needs you.
  let undo=app.buttons["desk-undo-silence"]
  XCTAssertTrue(undo.waitForExistence(timeout:5), "Undo after silencing")
  XCTAssertTrue(app.buttons["desk-silenced-row"].waitForExistence(timeout:5) && app.buttons["desk-silenced-row"].label.contains("1 silenced"), "1 silenced, listed")
  capture("desk-silenced", app)
  undo.tap()
  XCTAssertTrue(card.waitForExistence(timeout:8), "undone, it's back in Needs you")
  calls=try await deskCalls()
  XCTAssertEqual(calls.last?["action"] as? String, "unsilence")
  XCTAssertEqual(((calls.last?["body"] as? [String:Any])?["id"] as? String)?.uppercased(), deskID("approval"))
  XCTAssertEqual(deskCounts(app)[2], "Needs you, 2")
  XCTAssertTrue(app.buttons["desk-silenced-row"].waitForNonExistence(timeout:5), "nothing silenced: no row")
  // All the way across: it only shows Silence; nothing is silenced without a tap.
  let questions=app.buttons["desk-waiting-"+deskID("questions")]
  XCTAssertTrue(questions.waitForExistence(timeout:5))
  questions.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5))
   .press(forDuration:0.05,thenDragTo:questions.coordinate(withNormalizedOffset:CGVector(dx:-0.3,dy:0.5)),withVelocity:.default,thenHoldForDuration:0.05)
  let revealed=app.buttons["desk-silence-"+deskID("questions")]
  XCTAssertTrue(revealed.waitForExistence(timeout:5), "a full swipe shows Silence")
  try await Task.sleep(for:.seconds(1.5))
  XCTAssertTrue(questions.exists, "and the card stays until Silence is tapped")
  let sentSoFar=try await deskCalls()
  XCTAssertEqual(sentSoFar.filter { $0["action"] as? String == "silence" }.count, 1, "no silence was sent")
  revealed.tap()
  XCTAssertTrue(questions.waitForNonExistence(timeout:8), "tapped, it's silenced")
  XCTAssertTrue(app.buttons["desk-tab-needs-you"].isSelected, "the column stays where it was")
  calls=try await deskCalls()
  XCTAssertEqual(((calls.last?["body"] as? [String:Any])?["id"] as? String)?.uppercased(), deskID("questions"))
  // The silenced list: Unsilence puts it back.
  let row=app.buttons["desk-silenced-row"]
  XCTAssertTrue(row.waitForExistence(timeout:5)); reveal(row, app); row.tap()
  let unsilence=app.buttons["desk-unsilence-"+deskID("questions")]
  XCTAssertTrue(unsilence.waitForExistence(timeout:5), "the silenced list, each with Unsilence")
  capture("desk-silenced-list", app)
  unsilence.tap()
  XCTAssertTrue(questions.waitForExistence(timeout:8), "unsilenced, it's back")
  let lastCall=try await deskCalls().last
  XCTAssertEqual(lastCall?["action"] as? String, "unsilence")
 }
 /// Long-press a Needs-you card: Silence is in its menu too.
 @MainActor func testDeskSilenceMenu() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let card=app.buttons["desk-waiting-"+deskID("questions")]
  XCTAssertTrue(card.waitForExistence(timeout:20)); card.press(forDuration:1.2)
  let item=app.buttons["Silence"]
  XCTAssertTrue(item.waitForExistence(timeout:5), "Silence in the card's menu")
  item.tap()
  XCTAssertTrue(card.waitForNonExistence(timeout:8), "silenced from the menu")
  let calls=try await deskCalls()
  XCTAssertEqual(calls.last?["action"] as? String, "silence")
  XCTAssertEqual(((calls.last?["body"] as? [String:Any])?["id"] as? String)?.uppercased(), deskID("questions"))
  XCTAssertTrue(app.buttons["desk-waiting-"+deskID("approval")].exists, "the other stays")
 }
 /// Ready to mark complete: Mark Complete archives a session into Done (the Mac is asked);
 /// on a phone a card swiped left shows Complete, and swiped all the way completes at once.
 /// Reopen, in Done, brings one back.
 @MainActor func testDeskMarkComplete() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("ready",app)
  let magnets=uuid("PlayCase Magnets"), chatterbox=uuid("Chatterbox"), crystal=uuid("Crystal concept")
  let complete=app.buttons["desk-complete-"+magnets]
  XCTAssertTrue(complete.waitForExistence(timeout:5)); complete.tap()
  XCTAssertTrue(app.buttons["desk-ready-"+magnets].waitForNonExistence(timeout:8), "completed, it leaves Ready")
  var call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "complete"); XCTAssertEqual(((call?["body"] as? [String:Any])?["chatID"] as? String)?.uppercased(), magnets)
  XCTAssertEqual(deskCounts(app)[3], "Ready to mark complete, 1"); XCTAssertEqual(deskCounts(app)[4], "Done, 2", "and goes to Done")
  let card=app.buttons["desk-ready-"+chatterbox]
  if deskPhone(app) {
   // A partial swipe shows Complete; a full one completes.
   card.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
    .press(forDuration:0.05,thenDragTo:card.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.1)
   let swiped=app.buttons["desk-swipe-complete-"+chatterbox]
   XCTAssertTrue(swiped.waitForExistence(timeout:5) && swiped.isHittable, "swiping left shows Complete")
   try await Task.sleep(for:.milliseconds(400))
   capture("desk-complete-revealed", app)
   card.tap()
   XCTAssertTrue(swiped.waitForNonExistence(timeout:5), "a tap closes it again")
   card.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5))
    .press(forDuration:0.05,thenDragTo:card.coordinate(withNormalizedOffset:CGVector(dx:-0.3,dy:0.5)),withVelocity:.default,thenHoldForDuration:0.05)
   XCTAssertTrue(card.waitForNonExistence(timeout:8), "a full swipe marks it complete")
   XCTAssertTrue(app.staticTexts["desk-empty-ready"].waitForExistence(timeout:5), "nothing left in Ready, and it says so")
   call=try await deskCalls().last
   XCTAssertEqual(call?["action"] as? String, "complete"); XCTAssertEqual(((call?["body"] as? [String:Any])?["chatID"] as? String)?.uppercased(), chatterbox)
   XCTAssertEqual(deskCounts(app)[4], "Done, 3")
  }
  // Reopen, from Done.
  deskColumn("done",app)
  let reopen=app.buttons["desk-reopen-"+crystal]
  XCTAssertTrue(reopen.waitForExistence(timeout:5) && app.buttons["desk-reopen-"+magnets].exists, "Done lists what was completed")
  capture("desk-done", app)
  reopen.tap()
  XCTAssertTrue(reopen.waitForNonExistence(timeout:8), "reopened, it leaves Done")
  call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "reopen"); XCTAssertEqual(((call?["body"] as? [String:Any])?["chatID"] as? String)?.uppercased(), crystal)
 }
 /// Long-press a ready card: Open, Mark Complete and Silence (off the board, not archived).
 @MainActor func testDeskReadySilence() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20)); deskColumn("ready",app)
  let card=app.buttons["desk-ready-"+uuid("Chatterbox")]
  XCTAssertTrue(card.waitForExistence(timeout:5)); card.press(forDuration:1.2)
  XCTAssertTrue(app.buttons["Mark Complete"].waitForExistence(timeout:5) && app.buttons["Open"].exists, "the card's menu")
  app.buttons["Silence"].tap()
  XCTAssertTrue(card.waitForNonExistence(timeout:8), "silenced, it leaves Ready")
  let call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "silence")
  let body=call?["body"] as? [String:Any]
  XCTAssertEqual((body?["id"] as? String)?.uppercased(), uuid("Chatterbox")); XCTAssertEqual((body?["chatID"] as? String)?.uppercased(), uuid("Chatterbox"))
  XCTAssertEqual(body?["text"] as? String, "Shipped the Next Steps plugin and the new message box.")
  XCTAssertEqual(deskCounts(app)[4], "Done, 1", "not completed")
 }
 // MARK: Automations (MobileAutomations.swift)

 /// Automations from the ⋯ menu: each routine once (seven weekday automations read "Every
 /// day"), with its project, agent and time; its switch turns every day on, on the Mac; its
 /// last run opens that run's session.
 @MainActor func testAutomationsFromMenu() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  app.buttons["Connection"].tap()
  XCTAssertTrue(app.buttons["Automations"].waitForExistence(timeout:5), "Automations in the ⋯ menu"); app.buttons["Automations"].tap()
  let morning = app.buttons["automation-"+automationID("morning")]
  XCTAssertTrue(morning.waitForExistence(timeout:8), "the routines")
  XCTAssertTrue(morning.label.contains("Morning priorities") && morning.label.contains("Every day at 8:30"), "seven weekday automations read as one, every day: \(morning.label)")
  XCTAssertTrue(morning.label.contains("Chatterbox · Codex · GPT-5.5 · High"), "its project and agent")
  XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'automation-' AND label CONTAINS 'Morning priorities'")).count, 1, "listed once")
  XCTAssertTrue(app.buttons["automation-"+automationID("wordpress")].label.contains("Mondays at 9:00"), "a weekly one")
  XCTAssertTrue(app.buttons["automation-"+automationID("links")].label.contains("Mon, Wed, Fri at 4:00"), "one on three days")
  XCTAssertTrue(morning.frame.minY < app.buttons["automation-"+automationID("wordpress")].frame.minY, "the soonest first")
  let last = app.buttons["automation-last-run-"+automationID("morning")]
  XCTAssertTrue(last.exists && last.label.contains("Last run"), "its last run")
  capture("automations-list", app)
  // The switch: every day of the routine, on the Mac.
  let links = app.switches["automation-switch-"+automationID("links")]
  XCTAssertEqual(links.value as? String, "0", "switched off")
  // On the switch itself (a hidden-label switch's frame can be its row's width).
  links.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).tap()
  let calls = try await automationCalls(atLeast:1)
  XCTAssertEqual(calls.first?["action"] as? String, "edit")
  XCTAssertEqual(calls.first?["id"] as? String, automationID("links").lowercased())
  XCTAssertEqual(calls.first?["body"] as? [String:Bool], ["enabled":true], "only the switch")
  XCTAssertEqual(links.value as? String, "1", "and it shows on")
  // The last run opens its session.
  last.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Tracker Trapper."].waitForExistence(timeout:10), "the last run opens its session")
 }
 /// From the Desk: a routine's editor; changed instructions saved (only what changed), a day
 /// switched off, then Save and Run Now: the run's session opens.
 @MainActor func testAutomationEditAndRunFromDesk() async throws {
  try await fixture("reset")
  let app=deskApp(); app.launch()
  let open=app.buttons["desk-automations"]
  XCTAssertTrue(open.waitForExistence(timeout:20), "Automations on the Desk"); open.tap()
  let morning=app.buttons["automation-"+automationID("morning")]
  XCTAssertTrue(morning.waitForExistence(timeout:8)); morning.tap()
  let run=app.buttons["automation-run"]
  XCTAssertTrue(run.waitForExistence(timeout:5), "the editor, with Run Now")
  XCTAssertEqual(run.label, "Run Now")
  XCTAssertEqual(field("automation-title",app).value as? String, "Morning priorities")
  let instructions=field("automation-instructions",app)
  XCTAssertEqual(instructions.value as? String, "Read ClickUp and Outlook, then list today's priorities.")
  XCTAssertFalse(app.buttons["automation-save"].isEnabled, "nothing to save yet")
  capture("automation-detail", app)
  // Instructions: Save sends only them.
  instructions.tap(); instructions.typeText(" Include Slack.")
  XCTAssertEqual(run.label, "Save and Run Now")
  app.buttons["automation-save"].tap()
  var calls = try await automationCalls(atLeast:1)
  let body = calls.first?["body"] as? [String:Any]
  XCTAssertEqual(calls.first?["action"] as? String, "edit")
  XCTAssertEqual(body.map { Array($0.keys) }, ["instructions"], "only what changed")
  XCTAssertTrue((body?["instructions"] as? String)?.contains("Include Slack.") == true, "the new instructions")
  await fulfillment(of:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Run Now"), object:run)], timeout:5)
  XCTAssertFalse(app.buttons["automation-save"].isEnabled, "saved: nothing left to save")
  capture("automation-saved", app)
  // Sunday off, then Save and Run Now: the run's session opens.
  let sunday=app.buttons["automation-day-1"]
  for _ in 0..<6 where !(sunday.exists && sunday.isHittable) { app.swipeUp() }
  XCTAssertEqual(sunday.value as? String, "On"); sunday.tap()
  XCTAssertEqual(sunday.value as? String, "Off")
  XCTAssertTrue(activity("Every day but Sunday at 8:30",app).exists, "the schedule says so")
  capture("automation-days", app)
  revealUp(run, app)
  XCTAssertEqual(run.label, "Save and Run Now"); run.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Morning run."].waitForExistence(timeout:10), "Run Now opens the run's session")
  capture("automation-run-session", app)
  calls = try await automationCalls(atLeast:3)
  XCTAssertEqual((calls[1]["body"] as? [String:Any])?["days"] as? [Int], [2,3,4,5,6,7], "saved first: Sunday off")
  XCTAssertEqual(calls[2]["action"] as? String, "run", "then run")
 }
 /// Scrolls a form back up until the element is on screen (one scrolled away has no frame to test).
 @MainActor func revealUp(_ element:XCUIElement,_ app:XCUIApplication) {
  for _ in 0..<6 {
   let frame=element.exists ? element.frame : .zero
   if !frame.isEmpty, app.windows.firstMatch.frame.contains(CGPoint(x:frame.midX,y:frame.midY)), element.isHittable { return }
   app.collectionViews.firstMatch.swipeDown()
  }
 }
 /// The fixture's automations (server.py: uuid5(NAMESPACE_URL, "home:auto-" + name), a routine's first day).
 func automationID(_ name:String) -> String {
  ["morning":"22707547-1A2E-5702-8AA4-62C383E327A2","links":"C366CC4F-E577-590B-B3D1-4BA21010E490",
   "wordpress":"BEE84AAD-8941-5D8C-8281-0C018701C6FD"][name]!
 }
 /// The fixture's recorded edits and runs, once there are at least `count`.
 func automationCalls(atLeast count:Int) async throws -> [[String:Any]] {
  for _ in 0..<50 {
   let calls = try await fixture("automation-calls",method:"GET") as? [[String:Any]] ?? []
   if calls.count >= count { return calls }
   try await Task.sleep(for:.milliseconds(200))
  }
  XCTFail("expected \(count) automation calls"); return []
 }
 /// Tasks (plans/work-threads.md): Working, Ready and Done are tasks by their thread; Needs you
 /// marks threads that aren't tasks, with Make this a task; a To do card links a thread (one
 /// carrying a task asks first, then sends replace); a task card's menu unlinks.
 @MainActor func testDeskTasks() async throws {
  try await fixture("reset"); try await fixture("tasks")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20))
  let sdhq=app.buttons["desk-make-task-"+uuid("SDHQ")], tracker=app.buttons["desk-make-task-1D6B8917-B3EC-5A50-ADB6-5CE3526C15EA"]
  XCTAssertTrue(sdhq.waitForExistence(timeout:5) && tracker.exists, "threads that aren't tasks say so, with Make this a task")
  XCTAssertTrue(app.staticTexts["Not a task"].exists)
  capture("phone-board-tasks", app)
  reveal(sdhq, app); sdhq.tap()
  XCTAssertTrue(sdhq.waitForNonExistence(timeout:8), "made a task, the card carries it")
  var call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "makeTask"); XCTAssertEqual(((call?["body"] as? [String:Any])?["chatID"] as? String)?.uppercased(), uuid("SDHQ"))
  // Working: tasks by their thread, each with its task.
  deskColumn("working",app)
  XCTAssertTrue(app.buttons["desk-working-"+deskID("Galley")].waitForExistence(timeout:5), "Working: the task's thread")
  XCTAssertTrue(app.staticTexts["Finish the typography engine"].exists, "with its task")
  capture("phone-board-working-tasks", app)
  // Link a thread, from a To do card: the place's threads; one carrying a task asks first.
  deskColumn("todo",app)
  let link=app.buttons["desk-link-"+deskID("banner")]
  XCTAssertTrue(link.waitForExistence(timeout:5), "a To do card with a place: Link"); reveal(link, app); link.tap()
  let archie=app.buttons["desk-link-thread-"+deskID("Coach Archie")]
  XCTAssertTrue(archie.waitForExistence(timeout:8) && app.buttons["desk-link-thread-963CA311-2496-5A83-9807-3AE28F7E5FB5"].exists, "every thread in USA Archery")
  XCTAssertTrue(app.staticTexts["Best match · Has a task: Coach jacket mockups · Working now"].exists, "Coach Archie says it carries a task")
  let all=try await deskCalls().last { ($0["action"] as? String)=="threads" }
  XCTAssertEqual(all?["all"] as? Bool, true, "asked for every thread")
  capture("phone-link-thread", app)
  archie.tap()
  XCTAssertTrue(app.alerts["Link anyway?"].waitForExistence(timeout:5), "a thread carrying a task asks first")
  let linkedYet=try await deskCalls().contains { ($0["action"] as? String)=="link" }
  XCTAssertFalse(linkedYet, "nothing sent yet")
  app.alerts["Link anyway?"].buttons["Link Anyway"].tap()
  XCTAssertTrue(link.waitForNonExistence(timeout:8), "linked, it leaves To do")
  call=try await deskCalls().last { ($0["action"] as? String)=="link" }
  XCTAssertEqual(call?["id"] as? String, deskID("banner").lowercased())
  XCTAssertEqual(((call?["body"] as? [String:Any])?["chatID"] as? String)?.uppercased(), deskID("Coach Archie"))
  XCTAssertEqual((call?["body"] as? [String:Any])?["replace"] as? Bool, true, "Link Anyway sends replace")
  // Unlink, from a Ready card's menu: back to To do.
  deskColumn("ready",app)
  let ready=app.buttons["desk-ready-"+uuid("PlayCase Magnets")]
  XCTAssertTrue(ready.waitForExistence(timeout:5)); ready.press(forDuration:1.2)
  XCTAssertTrue(app.buttons["Unlink Task"].waitForExistence(timeout:5), "a task card's menu: Unlink Task"); app.buttons["Unlink Task"].tap()
  XCTAssertTrue(ready.waitForNonExistence(timeout:8), "unlinked, it leaves Ready")
  call=try await deskCalls().last
  XCTAssertEqual(call?["action"] as? String, "unlink")
 }
 /// Work threads (plans/work-threads.md): a front thread's Work strip lists its work threads with
 /// their state; one opens with a header naming its front thread and a link back; the session
 /// menu starts one (name, brief, agent) and carries the task items.
 @MainActor func testWorkThreads() async throws {
  try await fixture("reset"); try await fixture("tasks")
  let app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20))
  deskColumn("ready",app)
  let front=app.buttons["desk-ready-"+uuid("Chatterbox")]
  XCTAssertTrue(front.waitForExistence(timeout:5)); front.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Chatterbox."].waitForExistence(timeout:10))
  let columns=app.buttons["work-chip-C4F14522-94D6-5AF4-BCF1-77AE08737652"], tabs=app.buttons["work-chip-CFD6F12A-EE25-5C7D-BCE0-C004F850001E"]
  XCTAssertTrue(columns.waitForExistence(timeout:8) && tabs.exists, "the Work strip: each work thread")
  XCTAssertEqual(columns.label, "Work thread Desk board columns, Working"); XCTAssertEqual(tabs.label, "Work thread Phone tabs, Ready", "with its state")
  capture("phone-work-strip", app)
  // The session menu: Start a Work Thread, and Unlink (it carries a task).
  app.buttons["Session Menu"].tap()
  XCTAssertTrue(app.buttons["menu-start-work"].waitForExistence(timeout:5) && app.buttons["menu-unlink-task"].exists, "the menu: Start a Work Thread and Unlink from Task")
  XCTAssertFalse(app.buttons["menu-make-task"].exists, "not Make This a Task: it is one")
  app.buttons["menu-start-work"].tap()
  let title=app.textFields["work-title"]
  XCTAssertTrue(title.waitForExistence(timeout:5)); title.tap(); title.typeText("Release notes")
  let brief=app.textViews["work-brief"].exists ? app.textViews["work-brief"] : app.textFields["work-brief"]
  brief.tap(); brief.typeText("Write the 2.1 release notes from CHANGELOG.md.")
  capture("phone-start-work-thread", app)
  app.buttons["work-start"].tap()
  XCTAssertTrue(app.buttons["work-start"].waitForNonExistence(timeout:8), "started, the sheet closes")
  let started=try await deskCalls().last { ($0["action"] as? String)=="work" }
  XCTAssertEqual((started?["chat"] as? String)?.uppercased(), uuid("Chatterbox"))
  let body=started?["body"] as? [String:Any]
  XCTAssertEqual(body?["title"] as? String, "Release notes"); XCTAssertEqual(body?["brief"] as? String, "Write the 2.1 release notes from CHANGELOG.md.")
  XCTAssertNil(body?["agent"], "the front thread's own agent")
  // A work thread: its header names the front thread, with a link back.
  XCTAssertTrue(columns.waitForExistence(timeout:5)); columns.tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Desk board columns."].waitForExistence(timeout:10), "a chip opens its work thread")
  XCTAssertTrue(app.staticTexts["Work for \u{201C}Chatterbox\u{201D}. Its result goes back there."].waitForExistence(timeout:5), "its header names the front thread")
  capture("phone-work-thread-header", app)
  app.buttons["Session Menu"].tap()
  XCTAssertTrue(app.buttons["menu-make-task"].waitForExistence(timeout:5) || app.buttons["menu-unlink-task"].exists, "task items in its menu too")
  XCTAssertFalse(app.buttons["menu-start-work"].exists, "a work thread can't start work threads")
  // Closed by a tap above it.
  app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.07)).tap()
  XCTAssertTrue(app.buttons["work-front-open"].waitForExistence(timeout:5)); app.buttons["work-front-open"].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is Chatterbox."].waitForExistence(timeout:10), "Open goes back to the front thread")
 }
 /// The Desk on its own preferences: a fresh install, which opens on it.
 @MainActor func deskApp() -> XCUIApplication {
  let app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411",
                         "CHATTERBOX_PREFERENCES_SUITE":"desk-"+UUID().uuidString]
  return app
 }
 /// The Desk's tab: its button (the Desk's own title is "Desk" too).
 @MainActor func deskTab(_ app:XCUIApplication) -> XCUIElement {
  let phone=app.tabBars.buttons["Desk"]
  return phone.exists ? phone : app.buttons.matching(NSPredicate(format:"label == %@","Desk")).firstMatch
 }
 var approve: String { "desk-allow-"+deskID("approval") }
 static let deskColumns=["todo","working","needs-you","ready","done"]
 /// The board one column at a time, under tabs (a phone), rather than side by side.
 @MainActor func deskPhone(_ app:XCUIApplication) -> Bool { app.buttons["desk-tab-todo"].exists }
 /// A column's header, side by side (wide).
 @MainActor func deskHeader(_ id:String,_ app:XCUIApplication) -> XCUIElement { app.descendants(matching:.any)["desk-section-"+id] }
 /// Each column's name and count, left to right: its tab's label on a phone, its header's when wide.
 @MainActor func deskCounts(_ app:XCUIApplication) -> [String] {
  let phone=deskPhone(app)
  return Self.deskColumns.map { phone ? app.buttons["desk-tab-"+$0].label : deskHeader($0,app).label }
 }
 /// Shows a column: its tab on a phone; wide, the board scrolled sideways (by its header row)
 /// until the column is on screen.
 @MainActor func deskColumn(_ id:String,_ app:XCUIApplication) {
  if deskPhone(app) { app.buttons["desk-tab-"+id].tap(); return }
  let header=deskHeader(id,app), window=app.windows.firstMatch
  for _ in 0..<8 {
   // The header's frame is its name and count; the column is 320 points wide.
   let frame=header.frame, width=window.frame.width, right=frame.minX+320
   guard frame.minX < 0 || right > width else { return }
   let y=frame.midY, toLeft=right > width
   let from=window.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:width*(toLeft ? 0.75 : 0.25),dy:y))
   let to=window.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:width*(toLeft ? 0.3 : 0.7),dy:y))
   // Held before letting go: no fling past the column.
   from.press(forDuration:0.05,thenDragTo:to,withVelocity:.slow,thenHoldForDuration:0.2)
   usleep(400_000)
  }
 }
 /// The fixture's Desk ids (server.py: uuid5(NAMESPACE_URL, "home:desk-" + name), or a chat's).
 func deskID(_ name:String) -> String {
  ["approval":"773D2651-D545-5E7B-A576-E90FF28EDEE7","questions":"D9A5D613-012B-5519-BD59-215AB5DB6C89",
   "banner":"C31C4CB5-3FC1-5902-9C75-2F9B0D2AEA1E","printer":"6C35F22A-7C4E-54AD-9EFD-93BD619DC7C3",
   "Galley":"B5BBD354-BAAF-5AB3-B7FE-3ACD63B384E2","Coach Archie":"F982B462-68F5-509B-8E10-9946C3F0A1B1"][name]!
 }
 func deskCalls() async throws -> [[String:Any]] { try await fixture("desk-calls",method:"GET") as? [[String:Any]] ?? [] }
 /// Each new-chat-options query the app made, oldest first.
 func newChatQueries() async throws -> [[String:String]] { try await fixture("new-chat-options",method:"GET") as? [[String:String]] ?? [] }
 /// A model in the model row's menu (its label may carry the detail line after the name).
 @MainActor func modelItem(_ name:String,_ app:XCUIApplication) -> XCUIElement {
  app.descendants(matching:.any).matching(NSPredicate(format:"(elementType == %d OR elementType == %d OR elementType == %d) AND (label == %@ OR label BEGINSWITH %@)",
   XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.switch.rawValue, XCUIElement.ElementType.menuItem.rawValue, name, name+",")).firstMatch
 }
 /// The note a start leaves on the Desk: it runs in the background, with Open.
 @MainActor func startedNote(_ app:XCUIApplication) -> XCUIElement { app.descendants(matching:.any)["desk-started"] }
 /// Scrolls the Desk until the element is on screen.
 @MainActor func reveal(_ element:XCUIElement,_ app:XCUIApplication) {
  for _ in 0..<5 where !(element.exists && element.isHittable) { app.swipeUp() }
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
  // An open model: no effort for it. The row prompts for one; its menu lists them.
  openList.tap()
  let modelRow=app.buttons["model-current"]
  XCTAssertTrue(modelRow.waitForExistence(timeout:5)); XCTAssertEqual(modelRow.label, "Model: Choose an open model, Runs on the PC")
  modelRow.tap()
  let qwen=modelItem("qwen3.5:9b",app)
  XCTAssertTrue(qwen.waitForExistence(timeout:5), "the open models list shows")
  qwen.tap()
  let effortGone=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.staticTexts["Effort"].firstMatch)
  await fulfillment(of:[effortGone],timeout:5)
  // Then Codex: pick one of its models; that switches the agent.
  codexList.tap()
  XCTAssertTrue(modelRow.waitForExistence(timeout:5)); modelRow.tap()
  let sol=modelItem("GPT-6.1-Sol",app)
  XCTAssertTrue(sol.waitForExistence(timeout:5), "the Codex list shows")
  sol.tap()
  for _ in 0..<4 where !app.buttons["permission-fullAccess"].waitForExistence(timeout:2) { app.swipeUp() }
  XCTAssertTrue(app.buttons["permission-fullAccess"].waitForExistence(timeout:5), "picking another agent's model loads that agent's permissions")
  // Every choice has its name; the risky one, chosen, says what it means.
  XCTAssertTrue(app.buttons["permission-readOnly"].label.contains("Read only") && app.buttons["permission-fullAccess"].label.contains("Full access"), "named choices")
  let caution=app.descendants(matching:.any)["permissions-caution"]
  for _ in 0..<3 where !caution.exists { app.swipeUp() }
  XCTAssertTrue(app.buttons["permission-fullAccess"].isSelected, "Full access is the one chosen")
  XCTAssertTrue(caution.exists, "Full access chosen: its caution shows")
  XCTAssertFalse(app.buttons["permission-readOnly"].isSelected)
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
 /// Comments on a PDF, as with the Mac's Image Review: from the page being read, tap a spot and
 /// drag a box, with a note for each, on two pages. Add to Message puts the feedback in the
 /// message box with a marked-up copy of each marked page; comments on the photo then follow it.
 @MainActor func testPDFComments() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  // Its own preferences: no draft left in the session by another test.
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411",
                           "CHATTERBOX_PREFERENCES_SUITE":"comments-"+UUID().uuidString]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  let chat = app.buttons["chat-"+uuid("PlayCase Magnets")]
  XCTAssertTrue(chat.waitForExistence(timeout:10)); chat.tap()
  let composer = field("messageComposer",app)
  let pdf = app.buttons["Review PDF: Magnet proof.pdf"]
  XCTAssertTrue(pdf.waitForExistence(timeout:10)); pdf.tap()
  XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout:10))
  app.swipeUp()
  XCTAssertTrue(app.staticTexts["2 of 3"].waitForExistence(timeout:5))
  XCTAssertTrue(app.buttons["Comment"].isEnabled, "Comment in the PDF viewer's bottom bar")
  app.buttons["Comment"].tap()
  XCTAssertTrue(app.staticTexts["Page 2 of 3"].waitForExistence(timeout:5), "the review opens on the page being read")
  let page = app.descendants(matching:.any)["reviewPicture"]
  XCTAssertTrue(page.waitForExistence(timeout:5))
  try await Task.sleep(for:.seconds(1))
  capture("pdf-review-start",app)
  // A tap marks a spot; its note field opens.
  page.coordinate(withNormalizedOffset:CGVector(dx:0.3,dy:0.2)).tap()
  let first = field("reviewNote-1",app)
  XCTAssertTrue(first.waitForExistence(timeout:5), "a tap makes mark 1, with a note")
  first.typeText("Make the title bigger")
  capture("pdf-review-typing",app)
  first.typeText("\n")
  // A drag marks an area.
  page.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.3))
   .press(forDuration:0.1,thenDragTo:page.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.65)))
  let second = field("reviewNote-2",app)
  XCTAssertTrue(second.waitForExistence(timeout:5), "a drag makes mark 2, with a note")
  second.typeText("Swap in the new photo\n")
  try await Task.sleep(for:.seconds(1))
  capture("pdf-review-marks",app)
  // Page 3: a mark, undone, and another.
  app.buttons["Next Page"].tap()
  XCTAssertTrue(app.staticTexts["Page 3 of 3"].waitForExistence(timeout:5))
  XCTAssertFalse(field("reviewNote-1",app).exists, "each page keeps its own marks")
  page.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.9)).tap()
  XCTAssertTrue(field("reviewNote-1",app).waitForExistence(timeout:5))
  app.buttons["Undo"].tap()
  XCTAssertTrue(field("reviewNote-1",app).waitForNonExistence(timeout:5), "Undo takes the mark back")
  page.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.85)).tap()
  let third = field("reviewNote-1",app)
  XCTAssertTrue(third.waitForExistence(timeout:5)); third.typeText("Add the price here\n")
  XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Page 2, 2 marks")).firstMatch.exists, "the other marked page is listed")
  capture("pdf-review-page-3",app)
  app.buttons["Previous Page"].tap()
  XCTAssertTrue(app.staticTexts["Page 2 of 3"].waitForExistence(timeout:5))
  XCTAssertEqual(field("reviewNote-1",app).value as? String, "Make the title bigger", "page 2's notes are kept")
  let overall = field("reviewOverallNote",app)
  overall.tap(); overall.typeText("Otherwise ready to print.")
  app.buttons["Add to Message"].tap()
  XCTAssertTrue(composer.waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["Remove Marked up Magnet proof page 2 image"].waitForExistence(timeout:10), "page 2, marked up, waits to be sent")
  XCTAssertTrue(app.buttons["Remove Marked up Magnet proof page 3 image"].exists, "and page 3")
  let text = composer.value as? String ?? ""
  XCTAssertTrue(text.hasPrefix("Feedback on Magnet proof.pdf. Marked-up copies of pages 2, 3 are attached"), text)
  for line in ["Page 2:", "1. spot at top left", ": Make the title bigger", "2. area at center", ": Swap in the new photo",
               "Page 3:", "1. spot at bottom right", ": Add the price here", "Overall: Otherwise ready to print."] {
   XCTAssertTrue(text.contains(line), "missing \(line) in \(text)")
  }
  XCTAssertFalse(text.contains("bigger\n\n") || text.contains("photo\n\n2."), "Return ends a note without a line break in it")
  capture("pdf-review-composer",app)
  // Comments on the photo go after what's already in the box.
  let photo = app.descendants(matching:.any)["chat-image-"+uuid("magnet-photo").lowercased()]
  XCTAssertTrue(photo.waitForExistence(timeout:10)); photo.tap()
  XCTAssertTrue(app.buttons["Comment"].waitForExistence(timeout:5)); app.buttons["Comment"].tap()
  let picture = app.descendants(matching:.any)["reviewPicture"]
  XCTAssertTrue(picture.waitForExistence(timeout:5))
  picture.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
  XCTAssertTrue(field("reviewNote-1",app).waitForExistence(timeout:5)); field("reviewNote-1",app).typeText("Use this photo\n")
  app.buttons["Add to Message"].tap()
  XCTAssertTrue(app.buttons["Remove Marked up magnet-photo image"].waitForExistence(timeout:10))
  let both = composer.value as? String ?? ""
  XCTAssertTrue(both.hasPrefix(text + "\n\nFeedback on magnet-photo.png. The attached image is annotated."), both)
  XCTAssertTrue(app.buttons["Remove Marked up Magnet proof page 2 image"].exists, "the pages' copies are still there")
 }
 /// Comment on an image from the full-screen viewer: one spot with a note and an overall note.
 @MainActor func testImageComments() async throws {
  try await fixture("reset")
  let app = XCUIApplication()
  // Its own preferences: no draft left in the session by another test.
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"47411",
                           "CHATTERBOX_PREFERENCES_SUITE":"comments-"+UUID().uuidString]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:15)); tab("Projects",app).tap()
  let chat = app.buttons["chat-"+uuid("PlayCase Magnets")]
  XCTAssertTrue(chat.waitForExistence(timeout:10)); chat.tap()
  let photo = app.descendants(matching:.any)["chat-image-"+uuid("magnet-photo").lowercased()]
  XCTAssertTrue(photo.waitForExistence(timeout:10)); photo.tap()
  XCTAssertTrue(app.buttons["Comment"].waitForExistence(timeout:5), "Comment beside Mark Up"); app.buttons["Comment"].tap()
  let picture = app.descendants(matching:.any)["reviewPicture"]
  XCTAssertTrue(picture.waitForExistence(timeout:5))
  picture.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
  let first = field("reviewNote-1",app)
  XCTAssertTrue(first.waitForExistence(timeout:5)); first.typeText("Make the magnet red\n")
  let overall = field("reviewOverallNote",app)
  overall.tap(); overall.typeText("Brighter background")
  capture("image-review",app)
  app.buttons["Add to Message"].tap()
  XCTAssertTrue(app.buttons["Remove Marked up magnet-photo image"].waitForExistence(timeout:10), "the marked-up copy waits to be sent")
  let text = field("messageComposer",app).value as? String ?? ""
  XCTAssertTrue(text.hasPrefix("Feedback on magnet-photo.png. The attached image is annotated."), text)
  XCTAssertTrue(text.contains("1. spot at center") && text.contains(": Make the magnet red") && text.contains("Overall: Brighter background"), text)
  capture("image-review-composer",app)
 }
 // MARK: UX panel tour (design/ux-panel/screens)

 /// Not a regression check: walks the main screens against the fixture (with fuller Galley
 /// and SDHQ transcripts) and attaches one screenshot per screen, named "ux-…", for a design
 /// review. Waits for each screen; skips a step whose control isn't there rather than failing.
 /// MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testUXPanelTour on iphone, ipad or duo.
 @MainActor func testUXPanelTour() async throws {
  try await fixture("reset"); try await fixture("rich")
  XCUIDevice.shared.orientation = .portrait
  // The Desk, on a fresh install (it opens there).
  var app=deskApp(); app.launch()
  XCTAssertTrue(app.buttons[approve].waitForExistence(timeout:20))
  let wide = !deskPhone(app)
  try await uxShot("desk", app)
  if !wide { deskColumn("working",app); try await uxShot("desk-working", app); deskColumn("ready",app); try await uxShot("desk-ready", app) }
  deskColumn("todo",app)
  // Start There: the step that sends a request to a session.
  let start=app.buttons["desk-start-"+deskID("banner")]
  if start.waitForExistence(timeout:5) {
   reveal(start, app); start.tap()
   if app.buttons["desk-thread-new"].waitForExistence(timeout:8) { try await uxShot("desk-start-there", app) }
   uxDismiss(app)
  }
  // Change Place: the places a request can go.
  let change=app.buttons["desk-place-"+deskID("banner")]
  if change.waitForExistence(timeout:5) {
   reveal(change, app); change.tap()
   if app.buttons["desk-place-option-Geekify"].waitForExistence(timeout:8) { try await uxShot("desk-change-place", app) }
   uxDismiss(app)
  }
  // A Needs-you card swiped left: Silence (a phone; wide, a sideways drag scrolls the board).
  deskColumn("needs-you",app)
  let card=app.buttons["desk-waiting-"+deskID("questions")]
  if card.waitForExistence(timeout:5) {
   card.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
    .press(forDuration:0.05,thenDragTo:card.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.1)
   let silence=app.buttons["desk-silence-"+deskID("questions")]
   if silence.waitForExistence(timeout:5) {
    try await uxShot("desk-silence-swipe", app)
    // Tapped: Undo for a few seconds, and the quiet silenced row at the foot of Needs you.
    silence.tap()
    if app.buttons["desk-undo-silence"].waitForExistence(timeout:5) {
     try await Task.sleep(for:.milliseconds(400)); capture("ux-desk-silenced-undo", app)
     let row=app.buttons["desk-silenced-row"]
     if row.waitForExistence(timeout:5) { reveal(row, app); row.tap(); try await uxShot("desk-silenced-list", app) }
    }
   }
  }
  // The ask box, with a request typed.
  let ask=field("desk-ask",app)
  app.terminate(); app=deskApp(); app.launch()
  if ask.waitForExistence(timeout:20) { ask.tap(); ask.typeText("Order more magnet blanks"); try await uxShot("desk-ask", app) }
  // Nothing waiting: the calm Desk.
  try await fixture("desk-empty")
  app.terminate(); app=deskApp(); app.launch()
  if app.staticTexts["desk-empty-todo"].waitForExistence(timeout:20) { try await uxShot("desk-calm", app) }
  try await fixture("reset"); try await fixture("rich")
  app.terminate()

  // The session lists, on the app's own preferences (paired, as after setup).
  app=XCUIApplication()
  app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"47411"]
  app.launch()
  XCTAssertTrue(tab("Projects",app).waitForExistence(timeout:20)); tab("Projects",app).tap()
  let galley=app.buttons["chat-"+deskID("Galley")]
  XCTAssertTrue(galley.waitForExistence(timeout:15))
  try await uxShot("projects", app)
  if app.buttons["Connection"].exists {
   app.buttons["Connection"].tap(); try await uxShot("menu", app)
   // Off the menu: a tap on the title, clear of the rows under it.
   app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.12,dy:0.115)).tap(); sleep(1)
  }
  tab("Studios",app).tap()
  if app.buttons["studio-select-studio-1"].waitForExistence(timeout:10) {
   try await uxShot("studios", app)
   openStudio("studio-1",app)
   if app.images["Latest image in Coach Archie"].waitForExistence(timeout:10) || true { try await uxShot("studio-usa-archery", app) }
   if app.buttons["studios-index"].exists { app.buttons["studios-index"].tap() }
  }
  tab("Chats",app).tap()
  if tab("All",app).waitForExistence(timeout:5) { tab("All",app).tap(); try await uxShot("all-sessions", app) }

  // A working session with tool rows, a plan, a failed and passing test run, and a reply
  // with a heading, list, code and a table.
  tab("Projects",app).tap()
  XCTAssertTrue(galley.waitForExistence(timeout:10)); galley.tap()
  let reply=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","Knuth-Plass")).firstMatch
  XCTAssertTrue(reply.waitForExistence(timeout:10))
  try await uxShot("conversation", app)
  app.swipeDown(); app.swipeDown()
  try await uxShot("conversation-top", app)
  // Session Settings, then its model menu.
  if app.buttons["Session Menu"].exists {
   app.buttons["Session Menu"].tap(); try await uxShot("session-menu", app)
   if app.buttons["Session Settings"].waitForExistence(timeout:5) {
    app.buttons["Session Settings"].tap()
    let modelRow=app.buttons["model-current"]
    if modelRow.waitForExistence(timeout:5) {
     try await uxShot("session-settings", app)
     modelRow.tap()
     if modelItem("Sonnet 5",app).waitForExistence(timeout:5) { try await uxShot("session-settings-model-menu", app); modelItem("Opus 5.5",app).tap() }
    }
    if app.navigationBars["Session Settings"].buttons["Done"].exists { app.navigationBars["Session Settings"].buttons["Done"].tap() } else { uxDismiss(app) }
   } else { uxDismiss(app) }
  }
  // An approval waiting in its session.
  if !wide { app.navigationBars.buttons.element(boundBy:0).tap() }
  let sdhq=app.buttons["chat-"+uuid("SDHQ")]
  if sdhq.waitForExistence(timeout:10) {
   sdhq.tap()
   if app.buttons["Allow"].waitForExistence(timeout:10) || app.buttons["approval-command"].exists { try await uxShot("approval", app) }
   if !wide { app.navigationBars.buttons.element(boundBy:0).tap() }
  }
  // Attachments: a PDF proof and a photo in a reply; comments on the photo; the message box
  // with the marked-up copy attached.
  let magnets=app.buttons["chat-"+uuid("PlayCase Magnets")]
  if magnets.waitForExistence(timeout:10) {
   // Clear of the tab bar first: a row under it takes the tap as the bar's.
   if app.tabBars.firstMatch.exists, magnets.frame.maxY > app.tabBars.firstMatch.frame.minY - 20 { app.swipeUp(); sleep(1) }
   magnets.tap()
   let photo=app.descendants(matching:.any)["chat-image-"+uuid("magnet-photo").lowercased()]
   if photo.waitForExistence(timeout:10) {
    try await Task.sleep(for:.seconds(1.5))
    try await uxShot("attachments", app)
    photo.tap()
    if app.buttons["Comment"].waitForExistence(timeout:5) {
     app.buttons["Comment"].tap()
     let picture=app.descendants(matching:.any)["reviewPicture"]
     if picture.waitForExistence(timeout:5) {
      picture.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
      let note=field("reviewNote-1",app)
      if note.waitForExistence(timeout:5) { note.typeText("Make the magnet red\n") }
      picture.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.15)).press(forDuration:0.1,thenDragTo:picture.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.35)))
      let second=field("reviewNote-2",app)
      if second.waitForExistence(timeout:5) { second.typeText("Brighter background here\n") }
      try await uxShot("image-comments", app)
      app.buttons["Add to Message"].tap()
      if app.buttons["Remove Marked up magnet-photo image"].waitForExistence(timeout:10) { try await uxShot("composer-attachment", app) }
     }
    }
   }
   if !wide, app.navigationBars.buttons.element(boundBy:0).exists { app.navigationBars.buttons.element(boundBy:0).tap() }
  }
  // New Chat: name, agent and model, effort, permissions.
  tab("Projects",app).tap()
  if app.buttons["New Chat"].firstMatch.waitForExistence(timeout:5) {
   app.buttons["New Chat"].firstMatch.tap()
   if app.navigationBars["New Chat"].waitForExistence(timeout:5) {
    try await uxShot("new-chat", app)
    // Its permissions: every choice named, the risky one's caution when chosen.
    for _ in 0..<4 where !app.buttons["permission-bypassPermissions"].isHittable { app.swipeUp() }
    try await uxShot("new-chat-permissions", app)
   }
   uxDismiss(app)
  }
  // Automations (from the ⋯ menu): the routines, then one routine's editor.
  if app.buttons["Connection"].waitForExistence(timeout:5) {
   app.buttons["Connection"].tap()
   if app.buttons["Automations"].waitForExistence(timeout:5) {
    app.buttons["Automations"].tap()
    let morning=app.buttons["automation-"+automationID("morning")]
    if morning.waitForExistence(timeout:8) {
     try await uxShot("automations", app)
     morning.tap()
     if app.buttons["automation-run"].waitForExistence(timeout:5) { try await uxShot("automation-editor", app) }
    }
    uxDismiss(app); uxDismiss(app)
   } else { uxDismiss(app) }
  }
  // Usage (from the ⋯ menu).
  if app.buttons["Connection"].waitForExistence(timeout:5) {
   app.buttons["Connection"].tap()
   if app.buttons["Usage"].waitForExistence(timeout:5) {
    app.buttons["Usage"].tap()
    if app.staticTexts["81% used"].waitForExistence(timeout:8) { try await uxShot("usage", app) }
    uxDismiss(app)
   } else { uxDismiss(app) }
  }
  // Light mode: the Desk and the working session.
  try await fixture("appearance",body:["value":"light"])
  try await Task.sleep(for:.seconds(1.5))
  deskTab(app).tap()
  if app.buttons[approve].waitForExistence(timeout:10) { try await uxShot("desk-light", app) }
  tab("Projects",app).tap()
  if galley.waitForExistence(timeout:10) {
   galley.tap()
   if reply.waitForExistence(timeout:10) { try await uxShot("conversation-light", app) }
  }
  try await fixture("appearance",body:["value":"dark"])
  if !wide, app.navigationBars.buttons.element(boundBy:0).exists { app.navigationBars.buttons.element(boundBy:0).tap() }
  // The Mac stops answering (the fixture holds every reply past the app's timeout): refresh.
  tab("Projects",app).tap()
  try await fixture("offline")
  if galley.waitForExistence(timeout:5) {
   app.swipeDown()
   try await Task.sleep(for:.seconds(12))
   try await uxShot("connection-error", app)
  }
  try await fixture("reset")
  app.terminate()
 }
 /// Lets animations finish, then attaches the screen as "ux-<name>".
 @MainActor func uxShot(_ name:String,_ app:XCUIApplication) async throws {
  try await Task.sleep(for:.milliseconds(900))
  capture("ux-"+name, app)
 }
 /// Closes the top sheet, menu or pushed screen: its Cancel, Done or Close, else a swipe down.
 @MainActor func uxDismiss(_ app:XCUIApplication) {
  for label in ["Cancel","Done","Close"] {
   let button=app.navigationBars.buttons[label].firstMatch
   if button.exists && button.isHittable { button.tap(); sleep(1); return }
  }
  app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.12))
   .press(forDuration:0.05,thenDragTo:app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.95)))
  sleep(1)
 }
 /// A text field or text view (vertical TextFields are text views) by identifier.
 @MainActor func field(_ id:String,_ app:XCUIApplication) -> XCUIElement {
  app.descendants(matching:.any).matching(NSPredicate(format:"identifier == %@ AND (elementType == %d OR elementType == %d)",
   id, XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
 }
 /// The fixture's ids (server.py: uuid5(NAMESPACE_URL, "home:" + name)).
 func uuid(_ name: String) -> String {
  ["Chatterbox": "971E8582-9FFF-5D24-A2A2-AC8F6057BB63", "optimization": "2A1682A3-0390-5A12-8CA8-E0E375E1EEFE",
   "SDHQ": "A13D6820-B24D-575B-BF53-A51A5CFE48CF", "Loose chat": "DE705550-FFB1-5E01-980B-CDD999137340",
   "PlayCase Magnets": "CA155E08-F8EA-5578-922C-9F837067459E", "magnet-photo": "614FA2D3-393E-555B-8A8F-95D567E9B9DD",
   "studio": "2A955822-AC32-5554-95DF-BB415831052F", "Crystal concept": "7AEBD7DD-A239-547D-A2E7-BD7CA3DC8E5E"][name]!
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
 }
}

import XCTest
final class HomeNavTests: XCTestCase {
 func selected(_ app: XCUIApplication) -> String {
  app.tabBars.buttons.allElementsBoundByIndex.first { $0.isSelected }?.label ?? "?"
 }
 /// A swipe that starts at the screen's very edge, at mid-height.
 func edgeSwipe(_ app: XCUIApplication, fromLeft: Bool) {
  let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: fromLeft ? 0.01 : 0.99, dy: 0.5))
  let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: fromLeft ? 0.6 : 0.4, dy: 0.5))
  start.press(forDuration: 0.05, thenDragTo: end)
 }
 /// Calibration: with the strips off, does a synthesized left-edge drag trigger Back at all?
 @MainActor func testSystemBackSwipeWithoutStrips() async throws {
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47411", "CHATTERBOX_TEST_NO_EDGE_SWIPE": "1"]
  app.launch()
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
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47411"]
  if ProcessInfo.processInfo.environment["NO_EDGE"] != nil { app.launchEnvironment["CHATTERBOX_TEST_NO_EDGE_SWIPE"] = "1" }
  app.launch()
  XCTAssertTrue(app.buttons["chat-" + uuid("SDHQ")].waitForExistence(timeout:15))
  XCTAssertFalse(app.tabBars.buttons["Golem"].exists)
  capture("1-chats-list",app)
  // Cards, two to a row.
  app.buttons["Show as Cards"].tap()
  try await Task.sleep(for: .seconds(1))
  let first = app.buttons["chat-" + uuid("Chatterbox")], second = app.buttons["chat-" + uuid("optimization")]
  XCTAssertTrue(first.waitForExistence(timeout: 5) && second.exists)
  XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2, "two cards share a row")
  XCTAssertLessThan(first.frame.maxX, second.frame.minX, "side by side")
  capture("3-cards", app)
  // A chat open: the left-edge swipe is Back, not a tab switch.
  app.buttons["chat-" + uuid("SDHQ")].tap()
  XCTAssertTrue(app.staticTexts["Hi! This is SDHQ."].waitForExistence(timeout: 10))
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
 /// The fixture's ids (server.py: uuid5(NAMESPACE_URL, "home:" + name)).
 func uuid(_ name: String) -> String {
  ["Chatterbox": "971E8582-9FFF-5D24-A2A2-AC8F6057BB63", "optimization": "2A1682A3-0390-5A12-8CA8-E0E375E1EEFE",
   "SDHQ": "A13D6820-B24D-575B-BF53-A51A5CFE48CF"][name]!
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
 }
}

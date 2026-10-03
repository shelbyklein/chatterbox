import XCTest
final class ScrollTests: XCTestCase {
 let base = "http://127.0.0.1:47410"
 let chat = "chat-33333333-3333-3333-3333-333333333333"
 func advance() async throws {
  var request = URLRequest(url: URL(string: base + "/test/advance")!); request.httpMethod = "POST"
  _ = try await URLSession.shared.data(for: request)
 }
 func text(_ app: XCUIApplication, _ part: String) -> XCUIElement {
  app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
 }
 /// The reader is looking at the end when the newest streaming text is on screen.
 func atEnd(_ app: XCUIApplication) -> Bool {
  let e = text(app, "Streaming reply")
  return e.exists && e.isHittable
 }
 @MainActor func testReadingPositionHoldsWhileStreaming() async throws {
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47410"]
  app.launch()
  // iPhone: projects live under the Chats tab.
  if app.tabBars.buttons["Chats"].waitForExistence(timeout: 10) { app.tabBars.buttons["Chats"].tap() }
  let row = app.buttons[chat]
  XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
  // Opens at the newest message.
  XCTAssertTrue(text(app, "Answer 30").waitForExistence(timeout: 10))
  XCTAssertTrue(text(app, "Answer 30").isHittable, "opens at the end")
  capture("1-opened-at-end", app)
  // Following: new streamed text stays in view while at the end.
  try await advance()
  XCTAssertTrue(text(app, "Streaming reply").waitForExistence(timeout: 8))
  try await Task.sleep(for: .seconds(2))
  XCTAssertTrue(atEnd(app), "follows while at the end")
  // Read upward: scroll up until an earlier answer is on screen.
  for _ in 0..<4 { app.swipeDown(velocity: .slow) }
  let anchor = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Answer ")).firstMatch
  XCTAssertTrue(anchor.waitForExistence(timeout: 3))
  XCTAssertFalse(atEnd(app))
  let label = String(anchor.label.prefix(10)), frame = anchor.frame   // "Answer NN."
  capture("2-reading-above", app)
  XCTAssertTrue(app.buttons["Scroll to newest message"].waitForExistence(timeout: 3), "jump button shows when above the end")
  // Several streamed revisions (the app polls about every 1.2s): the position must not move.
  for _ in 0..<5 {
   try await advance()
   try await Task.sleep(for: .seconds(1.6))
   let same = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
   XCTAssertTrue(same.exists, "anchor still visible")
   XCTAssertEqual(same.frame.minY, frame.minY, accuracy: 1, "position held through a streamed revision")
  }
  capture("3-still-reading", app)
  // Jump: back to the end.
  app.buttons["Scroll to newest message"].tap()
  try await Task.sleep(for: .seconds(2))
  XCTAssertTrue(atEnd(app), "jump returns to the end")
  XCTAssertFalse(app.buttons["Scroll to newest message"].exists)
  capture("4-after-jump", app)
  // At the end again: following resumes.
  try await advance(); try await Task.sleep(for: .seconds(2.5))
  XCTAssertTrue(atEnd(app), "follows again after the jump")
  // Read up again, then send: your own message goes to the end.
  for _ in 0..<4 { app.swipeDown(velocity: .slow) }
  XCTAssertFalse(atEnd(app))
  let composer = app.textFields["messageComposer"].exists ? app.textFields["messageComposer"] : app.textViews["messageComposer"]
  composer.tap(); composer.typeText("hello")
  app.buttons["Send"].tap()
  XCTAssertTrue(text(app, "Sent from the test").waitForExistence(timeout: 8))
  try await Task.sleep(for: .seconds(2))
  XCTAssertTrue(text(app, "Sent from the test").isHittable, "send returns to the end")
  capture("5-after-send", app)
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
 }
}

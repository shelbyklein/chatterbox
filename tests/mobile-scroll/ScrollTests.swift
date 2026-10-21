import XCTest
final class ScrollTests: XCTestCase {
 override func setUp() { continueAfterFailure = false }
 let base = "http://127.0.0.1:47410"
 let chat = "chat-33333333-3333-3333-3333-333333333333"
 func control(_ path: String, body: [String: Any] = [:]) async throws {
  var request = URLRequest(url: URL(string: base + "/test/" + path)!)
  request.httpMethod = "POST"
  request.httpBody = try JSONSerialization.data(withJSONObject: body)
  _ = try await URLSession.shared.data(for: request)
 }
 @MainActor func openChat() -> XCUIApplication {
  let app = XCUIApplication()
  app.launchArguments = ["-mobileChatListPage", "projects", "-drafts", "{}"]
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47410"]
  app.launch()
  let row = app.buttons[chat]
  XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
  XCTAssertTrue(text(app, "Answer 30").waitForExistence(timeout: 10))
  return app
 }
 @MainActor func composer(_ app: XCUIApplication) -> XCUIElement {
  app.textViews["messageComposer"].exists ? app.textViews["messageComposer"] : app.textFields["messageComposer"]
 }
 func advance() async throws {
  var request = URLRequest(url: URL(string: base + "/test/advance")!); request.httpMethod = "POST"
  _ = try await URLSession.shared.data(for: request)
 }
 func text(_ app: XCUIApplication, _ part: String) -> XCUIElement {
  app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
 }
 @MainActor func readingAnchor(_ app: XCUIApplication) throws -> XCUIElement {
  // Lazy rows can be in accessibility before they are visible.
  let visible = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Answer "))
   .allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > app.navigationBars.firstMatch.frame.maxY }
  return try XCTUnwrap(visible)
 }
 @MainActor func readOlder(_ app: XCUIApplication) {
  let transcript = app.scrollViews["chatTranscript"]
  let top = max(transcript.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 40
  let origin = app.coordinate(withNormalizedOffset: .zero)
  let start = origin.withOffset(CGVector(dx: transcript.frame.midX, dy: top))
  let end = origin.withOffset(CGVector(dx: transcript.frame.midX, dy: top + 200))
  start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
 }
 @MainActor func testReadingPositionSurvivesImagePreview() async throws {
  try await control("reset")
  try await control("image")
  let app = openChat()
  let image = app.images["chat-image-22222222-2222-2222-2222-222222222222"]
  // Move deliberately toward older replies, including when the image starts in view on iPad.
  readOlder(app)
  for _ in 0..<8 {
   if image.exists && image.isHittable && image.frame.minY > app.navigationBars.firstMatch.frame.maxY { break }
   readOlder(app)
  }
  XCTAssertTrue(image.isHittable)
  XCTAssertTrue(app.buttons["Scroll to newest message"].exists)
  let before = image.frame
  capture("reading-before-image-preview", app)
  image.tap()
  XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
  app.buttons["Done"].tap()
  try await Task.sleep(for: .seconds(2))
  XCTAssertTrue(image.isHittable, "Closing an image preview pulled the reader away")
  XCTAssertEqual(image.frame.minY, before.minY, accuracy: 1, "Closing an image preview moved the reading position")
  XCTAssertTrue(app.buttons["Scroll to newest message"].exists)
  capture("reading-after-image-preview", app)
 }
 @MainActor func testReadingPositionSurvivesReactivation() async throws {
  try await control("reset")
  let app = openChat()
  for _ in 0..<3 { app.scrollViews["chatTranscript"].swipeDown(velocity: .slow) }
  let anchor = try readingAnchor(app)
  let label = String(anchor.label.prefix(10)), before = anchor.frame
  capture("reading-before-app-return", app)
  XCUIDevice.shared.press(.home)
  try await Task.sleep(for: .seconds(1))
  app.activate()
  try await Task.sleep(for: .seconds(2))
  let same = text(app, label)
  XCTAssertTrue(same.isHittable, "Returning to the app pulled the reader to the bottom")
  XCTAssertEqual(same.frame.minY, before.minY, accuracy: 1, "Returning to the app moved the reading position")
  XCTAssertTrue(app.buttons["Scroll to newest message"].exists)
  capture("reading-after-app-return", app)
  // New content and explicit refresh still must not take over.
  try await advance()
  try await Task.sleep(for: .seconds(2))
  app.buttons["Session Menu"].tap(); app.buttons["Refresh Session"].tap()
  try await Task.sleep(for: .seconds(1))
  XCTAssertTrue(same.isHittable)
  XCTAssertEqual(same.frame.minY, before.minY, accuracy: 1)
  capture("reading-after-return-and-refresh", app)
  // An intentional jump resumes following, including after another app return.
  app.buttons["Scroll to newest message"].tap()
  XCTAssertTrue(text(app, "Streaming reply").waitForExistence(timeout: 5))
  XCUIDevice.shared.press(.home); app.activate()
  try await advance(); try await Task.sleep(for: .seconds(2))
  XCTAssertTrue(atEnd(app))
 }
 /// The reader is looking at the end when the newest streaming text is on screen.
 func atEnd(_ app: XCUIApplication) -> Bool {
  let e = text(app, "Streaming reply")
  return e.exists && e.isHittable
 }
 @MainActor func testReadingPositionHoldsWhileStreaming() async throws {
  try await control("reset")
  let app = openChat()
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
  let anchor = try readingAnchor(app)
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

 /// A tall draft collapses before the Mac replies. The text must stay in the
 /// visible transcript throughout that resize, rather than scrolling into blank space.
 @MainActor func testMultilineSendKeepsTranscriptVisible() async throws {
  try await control("reset")
  try await control("delay", body: ["seconds": 3])
  let app = openChat()
  let field = composer(app)
  field.tap()
  field.typeText((1...6).map { "Line \($0) of my longer message." }.joined(separator: "\n"))
  capture("6-multiline-before-send", app)
  XCTAssertTrue(text(app, "Answer 30").isHittable, "growing the draft hid the newest reply before sending")
  app.buttons["Send"].tap()
  // Keep sampling through the resize and queued scroll operations, before acknowledgment.
  for _ in 0..<3 {
   let latest = text(app, "Answer 30")
   XCTAssertTrue(latest.isHittable, "latest transcript text left the viewport while clearing the composer")
  }
  let sent = text(app, "Sent from the test")
  XCTAssertTrue(sent.waitForExistence(timeout: 10))
  for _ in 0..<4 {
   XCTAssertTrue(sent.isHittable, "acknowledgment or queued scroll displaced the sent message")
   XCTAssertLessThan(sent.frame.maxY, field.frame.minY + 1, "sent message is covered by the composer")
   try await Task.sleep(for: .milliseconds(400))
  }
  capture("7-multiline-after-send", app)
 }

 /// A user reading elsewhere during a slow send takes over from the send's follow request.
 @MainActor func testReadingDuringSendWinsOverAcknowledgment() async throws {
  try await control("reset")
  try await control("hold")
  let app = openChat()
  let field = composer(app)
  field.tap(); field.typeText("Send while I read")
  app.buttons["Send"].tap()
  // Drag inside the transcript and hold before releasing, so the acknowledgment is tested
  // against a settled reading position rather than a fling still decelerating.
  let transcript = app.scrollViews["chatTranscript"]
  XCTAssertTrue(transcript.exists)
  let origin = app.coordinate(withNormalizedOffset: .zero)
  let top = max(transcript.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 30
  let start = origin.withOffset(CGVector(dx: field.frame.midX, dy: top))
  let end = origin.withOffset(CGVector(dx: field.frame.midX, dy: min(top + 300, field.frame.minY - 30)))
  start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
  let anchor = try XCTUnwrap(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Answer ")).allElementsBoundByIndex.first { $0.isHittable })
  let label = String(anchor.label.prefix(10)), before = anchor.frame
  try await control("release")
  try await Task.sleep(for: .seconds(3))
  let same = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
  XCTAssertTrue(same.isHittable, "send response pulled the reader away")
  XCTAssertEqual(same.frame.minY, before.minY, accuracy: 1, "send response moved the reading position")
  XCTAssertFalse(text(app, "The Mac may have applied").exists, "fixture exceeded the client's request timeout")
  capture("8-reading-during-send", app)
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
 }
}

import XCTest
import UIKit
/// The fixture server's port: each run has its own (start_test_server, scripts/lib/test-hygiene.sh,
/// through TEST_RUNNER_CHATTERBOX_TEST_PORT); 19646 when run by hand against a server on it.
let fixturePort = ProcessInfo.processInfo.environment["CHATTERBOX_TEST_PORT"] ?? "19646"
final class ConversationTests: XCTestCase {
 override func setUp(){continueAfterFailure=false}
 @MainActor func testConversationLayoutAndControls() async throws {
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":fixturePort]
  app.launch()
  // Sessions are on their tabs: the plain one on Chats, the project on Projects.
  let chatsTab = app.tabBars.buttons["Chats"]
  XCTAssertTrue(chatsTab.waitForExistence(timeout: 15)); chatsTab.tap()
  let codex = app.buttons["chat-11111111-1111-1111-1111-111111111111"]
  XCTAssertTrue(codex.waitForExistence(timeout: 15)); codex.tap()
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "The mobile layout is ready")).firstMatch.waitForExistence(timeout: 10))
  capture("codex-dark", app)
  XCTAssertTrue(app.buttons["Copy"].exists)
  XCTAssertTrue(app.buttons["Send"].exists)
  do {
   app.buttons["chat-title"].tap()
   let cog = app.buttons["about-settings"]
   XCTAssertTrue(cog.waitForExistence(timeout: 5)); cog.tap()
   XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 3)); capture("codex-settings", app)
   app.navigationBars["Session Settings"].buttons["Done"].tap()
   XCTAssertTrue(app.staticTexts["Reading the mobile layout"].exists)
   _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:\(fixturePort)/test/light")!)
   try await Task.sleep(for: .seconds(1))
   capture("codex-light", app)
   let composer = app.textFields["messageComposer"].exists ? app.textFields["messageComposer"] : app.textViews["messageComposer"]
   composer.tap(); composer.typeText("Draft for Codex")
   XCTAssertTrue(app.buttons["Send"].isEnabled)
   app.swipeDown()
   _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:\(fixturePort)/test/structured")!)
   let ready = app.staticTexts["Ready"]
   XCTAssertTrue(ready.waitForExistence(timeout: 8))
   capture("codex-structured", app)
  }
  // Back to the list, then the Projects tab.
  app.navigationBars.buttons.element(boundBy: 0).tap()
  app.tabBars.buttons["Projects"].tap()
  let claude = app.buttons["chat-33333333-3333-3333-3333-333333333333"]
  XCTAssertTrue(claude.waitForExistence(timeout: 10)); claude.tap()
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "I reviewed the layout")).firstMatch.waitForExistence(timeout: 5))
  capture("claude-light", app)
  let (data, _) = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:\(fixturePort)/test/log")!)
  let calls = try JSONSerialization.jsonObject(with: data) as! [[String:Any]]
  XCTAssertFalse(calls.contains { ($0["method"] as? String) == "POST" })
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
 }
}

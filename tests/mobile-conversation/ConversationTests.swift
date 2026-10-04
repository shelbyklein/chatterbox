import XCTest
import UIKit
final class ConversationTests: XCTestCase {
 override func setUp(){continueAfterFailure=false}
 @MainActor func testConversationLayoutAndControls() async throws {
  let app = XCUIApplication()
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"19646"]
  app.launch()
  #if GOLEM_APP
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "The mobile layout is ready")).firstMatch.waitForExistence(timeout:15))
  app.buttons["Message Codex fixture"].tap()
  #else
  let golem = app.buttons["chat-11111111-1111-1111-1111-111111111111"]
  XCTAssertTrue(golem.waitForExistence(timeout: 15)); golem.tap()
  #endif
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "The mobile layout is ready")).firstMatch.waitForExistence(timeout: 10))
  capture("golem-dark", app)
  XCTAssertTrue(app.buttons["Copy"].exists)
  XCTAssertTrue(app.buttons["Dictate"].exists)
  XCTAssertTrue(app.buttons["Send"].exists)
  do {
   #if GOLEM_APP
   XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format:"identifier BEGINSWITH %@", "reply-bubble-")).count, 3)
   #endif
   #if !GOLEM_APP
   app.buttons["Chat Menu"].tap()
   #endif
   let cog = app.buttons["Chat Settings"]
   XCTAssertTrue(cog.exists); cog.tap()
   XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 3)); capture("golem-settings", app)
   app.navigationBars["Chat Settings"].buttons["Done"].tap()
   #if GOLEM_APP
   let steps = app.descendants(matching: .any).matching(identifier: "1 step").firstMatch
   XCTAssertTrue(steps.exists); steps.tap()
   XCTAssertTrue(app.staticTexts["Reading the mobile layout"].waitForExistence(timeout: 3))
   steps.tap()
   #else
   XCTAssertTrue(app.staticTexts["Reading the mobile layout"].exists)
   #endif
   _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:19646/test/light")!)
   try await Task.sleep(for: .seconds(1))
   capture("golem-light", app)
   let composer = app.textFields["messageComposer"].exists ? app.textFields["messageComposer"] : app.textViews["messageComposer"]
   composer.tap(); composer.typeText("Draft for Golem")
   XCTAssertTrue(app.buttons["Send"].isEnabled)
   app.swipeDown()
   _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:19646/test/structured")!)
   let ready = app.staticTexts["Ready"]
   XCTAssertTrue(ready.waitForExistence(timeout: 8))
   #if GOLEM_APP
   XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format:"identifier BEGINSWITH %@", "reply-bubble-")).count, 3)
   #endif
   capture("golem-structured", app)
  }
  #if !GOLEM_APP
  let back = app.navigationBars.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Regression Mac")).firstMatch
  if back.exists { back.tap() }
  let claude = app.buttons["chat-33333333-3333-3333-3333-333333333333"]
  XCTAssertTrue(claude.waitForExistence(timeout: 3)); claude.tap()
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "I reviewed the layout")).firstMatch.waitForExistence(timeout: 5))
  capture("claude-light", app)
  #endif
  let (data, _) = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:19646/test/log")!)
  let calls = try JSONSerialization.jsonObject(with: data) as! [[String:Any]]
  #if GOLEM_APP
  XCTAssertFalse(calls.contains { ($0["method"] as? String) == "POST" && ($0["path"] as? String) != "/v1/golem/read" })
  #else
  XCTAssertFalse(calls.contains { ($0["method"] as? String) == "POST" })
  #endif
 }
 @MainActor func capture(_ name: String, _ app: XCUIApplication) {
  let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
 }
}

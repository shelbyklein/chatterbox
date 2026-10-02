import XCTest
import UIKit
final class ComposerTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
  func control(_ path: String, post: Bool = true) async throws -> [String:Any] {
    var r = URLRequest(url: URL(string:"http://127.0.0.1:19645/test/"+path)!)
    if post { r.httpMethod = "POST" }
    return try JSONSerialization.jsonObject(with: await URLSession.shared.data(for:r).0) as! [String:Any]
  }
  @MainActor func open(_ regular: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-drafts", "{}", "-mobileHomeTab", "golem"]
    app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":"19645"]
    app.launch()
    if UIDevice.current.userInterfaceIdiom == .pad {
      let row = app.buttons["chat-" + (regular ? "33333333-3333-3333-3333-333333333333" : "11111111-1111-1111-1111-111111111111")]
      XCTAssertTrue(row.waitForExistence(timeout:15)); row.tap()
    } else if regular {
      let tabs = app.tabBars.buttons["Chats"]
      XCTAssertTrue(tabs.waitForExistence(timeout:15)); tabs.tap()
      let row = app.buttons["chat-33333333-3333-3333-3333-333333333333"]
      XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
    } else {
      let golem = app.buttons["Message Regression Golem"]
      XCTAssertTrue(golem.waitForExistence(timeout:15));golem.tap()
    }
    XCTAssertTrue(field(app).waitForExistence(timeout:5))
    return app
  }
  @MainActor func field(_ app:XCUIApplication) -> XCUIElement {
    app.textViews["messageComposer"].exists ? app.textViews["messageComposer"] : app.textFields["messageComposer"]
  }
  @MainActor func empty(_ app:XCUIApplication) -> Bool {
    let text = field(app).value as? String ?? ""
    return text.isEmpty || text == "Message" || text == "Message Regression Golem"
  }
  @MainActor func capture(_ app:XCUIApplication,_ name:String) {
    let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
  }
  @MainActor func exercise(_ regular:Bool) async throws {
    _ = try await control("reset")
    let app=open(regular)
    field(app).tap();field(app).typeText("First send")
    _ = try await control("hold")
    app.buttons["Send"].tap()
    // The authoritative user item exists while the response is held.
    XCTAssertTrue(empty(app), "Submitted text remained in the composer pending acknowledgment")
    field(app).tap();field(app).typeText("Next draft")
    _ = try await control("release")
    let send=app.buttons["Send"]
    XCTAssertTrue(send.waitForExistence(timeout:3))
    await fulfillment(of:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:send)],timeout:5)
    XCTAssertEqual(field(app).value as? String,"Next draft", "Acknowledgment erased the new draft")
    XCTAssertEqual(app.staticTexts.matching(identifier:"First send").count, 1, "User message was rendered more than once")
    capture(app, regular ? "project-new-draft-after-ack" : "golem-new-draft-after-ack")
    let log=try await control("log",post:false)
    XCTAssertEqual((log["requests"] as! [[String:Any]]).count,1)
    XCTAssertEqual((log["counts"] as! [Int])[regular ? 1:0],1)
    // Reopening restores only the new draft, never the consumed text.
    app.terminate();app.launchArguments = ["-mobileHomeTab", "golem"];app.launch()
    if UIDevice.current.userInterfaceIdiom == .pad {
      let row = app.buttons["chat-" + (regular ? "33333333-3333-3333-3333-333333333333" : "11111111-1111-1111-1111-111111111111")]
      XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
    } else if regular {
      app.tabBars.buttons["Chats"].tap()
      let row=app.buttons["chat-33333333-3333-3333-3333-333333333333"]
      XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
    } else {
      let golem=app.buttons["Message Regression Golem"]
      XCTAssertTrue(golem.waitForExistence(timeout:10));golem.tap()
    }
    XCTAssertEqual(field(app).value as? String,"Next draft")
  }
  @MainActor func testGolemDelayedAcknowledgment() async throws { try await exercise(false) }
  @MainActor func testRegularDelayedAcknowledgment() async throws { try await exercise(true) }
  @MainActor func testSuccessfulAndFailedRepeatedSends() async throws {
    _ = try await control("reset")
    let app=open(true)
    for _ in 0..<2 {
      field(app).tap();field(app).typeText("Intentional repeat")
      app.buttons["Send"].tap()
      XCTAssertTrue(empty(app))
      // Wait for completion, not just an optimistic clear.
      XCTAssertTrue(app.buttons["Send"].exists)
      try await Task.sleep(for:.seconds(1))
    }
    let log=try await control("log",post:false)
    XCTAssertEqual((log["requests"] as! [[String:Any]]).count,2)
    XCTAssertEqual((log["counts"] as! [Int])[1],2)
    _ = try await control("fail")
    field(app).tap();field(app).typeText("Recover this failed draft")
    app.buttons["Send"].tap()
    XCTAssertTrue(app.staticTexts["Fixture rejected send"].waitForExistence(timeout:5))
    XCTAssertEqual(field(app).value as? String,"Recover this failed draft")
    capture(app,"failed-send-recovered")
  }
}

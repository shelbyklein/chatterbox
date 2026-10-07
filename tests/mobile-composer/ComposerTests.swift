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
    #if GOLEM_APP
    let golem=app.buttons["Message Regression Golem"]
    XCTAssertTrue(golem.waitForExistence(timeout:15));golem.tap()
    #else
    let row=app.buttons["chat-33333333-3333-3333-3333-333333333333"]
    XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
    #endif
    XCTAssertTrue(field(app).waitForExistence(timeout:5))
    return app
  }
  @MainActor func testSessionControls() async throws {
    _ = try await control("reset"); _ = try await control("running")
    let app = open(true)
    field(app).tap(); field(app).typeText("Keep this draft")
    app.buttons["Chat Menu"].tap()
    XCTAssertTrue(app.buttons["Stop Reply"].waitForExistence(timeout:5))
    XCTAssertTrue(app.buttons["Restart Thread"].exists)
    capture(app,"session-controls-menu")
    app.buttons["Stop Reply"].tap()
    let stopped = NSPredicate { _,_ in !app.buttons["Stop"].exists }
    let check=expectation(for:stopped,evaluatedWith:nil);await fulfillment(of:[check],timeout:8)
    app.buttons["Chat Menu"].tap();app.buttons["Restart Thread"].tap()
    XCTAssertTrue(app.alerts["Restart Thread?"].waitForExistence(timeout:5))
    capture(app,"restart-confirmation")
    app.alerts.buttons["Cancel"].tap()
    app.buttons["Chat Menu"].tap();app.buttons["Restart Thread"].tap()
    app.alerts.buttons["Restart Thread"].tap()
    try await Task.sleep(for:.seconds(1))
    XCTAssertTrue((field(app).value as? String ?? "").contains("Keep this draft"))
    let log = try await control("log",post:false)
    let actions=(log["requests"] as? [[String:Any]] ?? []).compactMap { $0["action"] as? String }
    XCTAssertEqual(actions,["stop","restart"])
    capture(app,"session-restarted-draft-kept")
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
    #if GOLEM_APP
    let golem=app.buttons["Message Regression Golem"]
    XCTAssertTrue(golem.waitForExistence(timeout:15));golem.tap()
    #else
    let row=app.buttons["chat-33333333-3333-3333-3333-333333333333"]
    XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
    #endif
    XCTAssertEqual(field(app).value as? String,"Next draft")
  }
  #if GOLEM_APP
  @MainActor func testGolemDelayedAcknowledgment() async throws { try await exercise(false) }
  #else
  @MainActor func testActivityTimeline() async throws {
    _ = try await control("reset")
    let app=XCUIApplication()
    app.launchArguments=["-drafts","{}","-mobileChatListPage","activity"]
    app.launchEnvironment=["CHATTERBOX_TEST_HOST":"127.0.0.1","CHATTERBOX_TEST_CODE":"123456","CHATTERBOX_TEST_PORT":"19645"]
    app.launch()
    let entries=app.buttons.matching(identifier:"Regression Project, turn ended")
    XCTAssertTrue(entries.firstMatch.waitForExistence(timeout:15))
    XCTAssertEqual(entries.count,2)
    capture(app,"activity-timeline")
    entries.firstMatch.tap()
    XCTAssertTrue(field(app).waitForExistence(timeout:10))
    capture(app,"activity-opened-chat")
  }
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
  #endif
}

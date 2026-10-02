import XCTest

final class HistoryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }
  @MainActor func capture(_ name: String, _ app: XCUIApplication) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
  func control(_ path: String, post: Bool = false) async throws -> Any {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:19645" + path)!)
    if post { r.httpMethod = "POST" }
    let (data, _) = try await URLSession.shared.data(for: r)
    return try JSONSerialization.jsonObject(with: data)
  }
  @MainActor func testOpenReopenAndForegroundWithoutSending() async throws {
    let app = XCUIApplication()
    app.launchEnvironment = [
      "CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456",
      "CHATTERBOX_TEST_PORT": "19645",
    ]
    app.launch()
    let row = app.buttons["chat-11111111-1111-1111-1111-111111111111"]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    row.tap()
    let ready = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "History ready 0")
    ).firstMatch
    XCTAssertTrue(
      ready.waitForExistence(timeout: 10), "No history after opening: \(app.debugDescription)")
    let before = try await control("/test/log") as! [[String: Any]]
    let count = before.filter {
      ($0["path"] as? String) == "/v1/chats/11111111-1111-1111-1111-111111111111"
    }.count
    XCUIDevice.shared.press(.home)
    let state = try await control("/test/advance", post: true) as! [String: Any]
    let version = state["revision"] as! Int
    app.activate()
    let fresh = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "History ready 0 version \(version)")
    ).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 3), "Foreground did not refresh immediately")
    let after = try await control("/test/log") as! [[String: Any]]
    XCTAssertGreaterThan(
      after.filter { ($0["path"] as? String) == "/v1/chats/11111111-1111-1111-1111-111111111111" }
        .count, count, "Foreground never forced a full refresh")
    capture("golem-foreground", app)
    // Return to the list and reopen, without sending anything.
    let back = app.navigationBars.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Regression Mac")
    ).firstMatch
    if back.exists { back.tap() }
    let next = try await control("/test/advance", post: true) as! [String: Any]
    let version2 = next["revision"] as! Int
    if row.exists { row.tap() }
    let reopened = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "History ready 0 version \(version2)")
    ).firstMatch
    XCTAssertTrue(reopened.waitForExistence(timeout: 3), "Reopening did not refresh")
    capture("golem-reopened", app)
    let calls = try await control("/test/log") as! [[String: Any]]
    XCTAssertFalse(
      calls.contains { ($0["method"] as? String) == "POST" }, "A chat mutation was sent")
  }

  @MainActor func testInterruptedLoadRecoversAndKeepsDraft() async throws {
    let app = XCUIApplication()
    app.launchEnvironment = [
      "CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456",
      "CHATTERBOX_TEST_PORT": "19645",
    ]
    app.launch()
    let row = app.buttons["chat-11111111-1111-1111-1111-111111111111"]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    _ = try await control("/test/delay", post: true)
    row.tap()
    // The fixture holds the first history request for eight seconds.
    let field =
      app.textViews["messageComposer"].exists
      ? app.textViews["messageComposer"] : app.textFields["messageComposer"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    if field.value as? String != "Keep my unsent draft" {
      field.tap()
      field.typeText("Keep my unsent draft")
    }
    let calls = try await control("/test/log") as! [[String: Any]]
    XCTAssertTrue(calls.contains { ($0["delayed"] as? Bool) == true })
    let back = app.navigationBars.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Regression Mac")
    ).firstMatch
    if back.exists { back.tap() }
    let other = app.buttons["chat-33333333-3333-3333-3333-333333333333"]
    XCTAssertTrue(other.waitForExistence(timeout: 3))
    other.tap()
    capture("opened-project", app)
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "History ready 1"))
        .firstMatch.waitForExistence(timeout: 3), app.debugDescription)
    if back.exists { back.tap() }
    let state = try await control("/test/advance", post: true) as! [String: Any]
    row.tap()
    let ready = app.staticTexts.containing(
      NSPredicate(
        format: "label CONTAINS %@", "History ready 0 version \(state["revision"] as! Int)")
    ).firstMatch
    XCTAssertTrue(ready.waitForExistence(timeout: 3), "Cancelled request stranded the new load")
    let restored =
      app.textViews["messageComposer"].exists
      ? app.textViews["messageComposer"] : app.textFields["messageComposer"]
    XCTAssertEqual(restored.value as? String, "Keep my unsent draft")
    capture("interrupted-load-recovered", app)
    let final = try await control("/test/log") as! [[String: Any]]
    XCTAssertFalse(final.contains { ($0["method"] as? String) == "POST" })
  }
}

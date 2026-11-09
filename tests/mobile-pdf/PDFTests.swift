import XCTest
/// The fixture server's port: each run has its own (start_test_server, scripts/lib/test-hygiene.sh,
/// through TEST_RUNNER_CHATTERBOX_TEST_PORT); 19647 when run by hand against a server on it.
let fixturePort = ProcessInfo.processInfo.environment["CHATTERBOX_TEST_PORT"] ?? "19647"
final class PDFTests: XCTestCase {
 @MainActor func testReviewExportAndOfflineReopen() async throws {
  let app = XCUIApplication()
  // A fresh install opens on the Desk; this session is on Projects.
  app.launchArguments = ["-mobileChatListPage", "projects"]
  app.launchEnvironment = ["CHATTERBOX_TEST_HOST":"127.0.0.1", "CHATTERBOX_TEST_CODE":"123456", "CHATTERBOX_TEST_PORT":fixturePort]
  app.launch()
  let chat = app.buttons["chat-11111111-1111-1111-1111-111111111111"]
  XCTAssertTrue(chat.waitForExistence(timeout:15));chat.tap()
  let tile = app.buttons["Review PDF: Review proof.pdf"]
  XCTAssertTrue(tile.waitForExistence(timeout:10));app.links["Review PDF"].tap()
  XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout:10));try await Task.sleep(for:.seconds(3));capture("pdf-review",app)
  app.swipeUp()
  XCTAssertTrue(app.staticTexts["2 of 3"].waitForExistence(timeout:5))
  app.pinch(withScale:1.3,velocity:1)
  app.buttons["Done"].tap();tile.tap()
  XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout:5))
  app.buttons["Save to Files"].tap()
  XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout:5));capture("pdf-export",app);app.buttons["Save"].tap()
  XCTAssertTrue(app.buttons["Refresh PDF"].waitForExistence(timeout:5))
  XCTAssertTrue(app.buttons["Share"].exists)
  app.buttons["Share"].tap()
  XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout:5));capture("pdf-share",app)
  if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown() }
  app.buttons["Refresh PDF"].tap()
  XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout:5))
  try await Task.sleep(for:.seconds(1))
  XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "saved copy")).firstMatch.exists)
  _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:\(fixturePort)/test/mode/slow")!)
  app.buttons["Refresh PDF"].tap()
  XCTAssertTrue(app.buttons["Cancel Download"].waitForExistence(timeout:5));capture("pdf-download",app)
  app.buttons["Cancel Download"].tap()
  XCTAssertTrue(app.staticTexts["Download cancelled. Showing the saved copy."].waitForExistence(timeout:5))
  _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:\(fixturePort)/test/mode/bad")!)
  app.buttons["Try Again"].tap()
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "readable PDF")).firstMatch.waitForExistence(timeout:5))
  XCTAssertTrue(app.staticTexts["1 of 3"].exists)
  _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:\(fixturePort)/test/mode/normal")!)
  app.buttons["Try Again"].tap()
  try await Task.sleep(for:.seconds(2))
  XCTAssertFalse(app.buttons["Try Again"].exists)
  app.buttons["Done"].tap()
  // Saved PDFs left the ⋯ menu (Shelby, 2026-11-09), so the offline reopen from that list is gone.
 }
 @MainActor func capture(_ name:String,_ app:XCUIApplication){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}

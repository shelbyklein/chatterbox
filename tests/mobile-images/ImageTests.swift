import XCTest

final class ImageTests: XCTestCase {
    let base = "http://127.0.0.1:47410"
    let imageID = "22222222-2222-2222-2222-222222222222"
    let olderID = "11111111-1111-1111-1111-111111111111"

    func control(_ path: String, mode: String = "") async throws {
        var request = URLRequest(url: URL(string: base + "/test/" + path)!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
        _ = try await URLSession.shared.data(for: request)
    }

    func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/test/counts")!)
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    @MainActor func open(_ mode: String) async throws -> XCUIApplication {
        try await control("reset", mode: mode)
        let app = XCUIApplication()
        app.launchArguments = ["-mobileChatListPage", "projects", "-drafts", "{}"]
        app.launchEnvironment = ["CHATTERBOX_TEST_HOST": "127.0.0.1", "CHATTERBOX_TEST_CODE": "123456", "CHATTERBOX_TEST_PORT": "47410"]
        app.launch()
        let chat = app.buttons["chat-33333333-3333-3333-3333-333333333333"]
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.tap()
        XCTAssertTrue(app.staticTexts["Visible image retry proof."].waitForExistence(timeout: 10))
        return app
    }

    @MainActor func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func scrollAway(_ app: XCUIApplication) {
        let transcript = app.scrollViews["chatTranscript"]
        for _ in 0..<2 { transcript.swipeDown(velocity: .slow) }
        XCTAssertFalse(app.images["chat-image-" + imageID].isHittable)
    }

    @MainActor func testVisibleImageRecoversAutomaticallyAndUsesCache() async throws {
        let app = try await open("transient")
        try await Task.sleep(for: .seconds(5))
        let requests = try await counts()
        XCTAssertEqual(requests[imageID], 2, "First HTTP failure must recover without a tap")
        XCTAssertNil(requests[olderID], "Offscreen images must not load just because the lazy row exists")
        let image = app.images["chat-image-" + imageID]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(image.isHittable)
        capture("image-recovered-without-tapping", app)
        scrollAway(app)
        app.buttons["Scroll to newest message"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        try await Task.sleep(for: .seconds(1))
        let after = try await counts()
        XCTAssertEqual(after[imageID], 2, "Already loaded image should use its cache")
    }

    @MainActor func testPersistentFailureStopsAndRetriesOnReentry() async throws {
        let app = try await open("permanent")
        let retry = app.buttons["retry-image-" + imageID]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        capture("image-manual-fallback", app)
        let before = try await counts()
        XCTAssertEqual(before[imageID], 3)
        try await Task.sleep(for: .seconds(3))
        let settled = try await counts()
        XCTAssertEqual(settled[imageID], 3, "Persistent failures must not loop indefinitely")
        scrollAway(app)
        try await control("recover")
        app.buttons["Scroll to newest message"].tap()
        XCTAssertTrue(app.images["chat-image-" + imageID].waitForExistence(timeout: 8))
        let after = try await counts()
        XCTAssertEqual(after[imageID], 4, "Returning to a failed image should retry immediately")
        capture("image-recovered-on-reentry", app)
    }

    @MainActor func testManualRetryRemainsAvailable() async throws {
        let app = try await open("manual")
        let retry = app.buttons["retry-image-" + imageID]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        try await control("recover")
        retry.tap()
        XCTAssertTrue(app.images["chat-image-" + imageID].waitForExistence(timeout: 8))
        let after = try await counts()
        XCTAssertEqual(after[imageID], 4)
    }

    @MainActor func testLeavingCancelsDownloadAndReturnLoadsWithoutTap() async throws {
        let app = try await open("slow")
        try await Task.sleep(for: .seconds(1))
        let before = try await counts()
        XCTAssertEqual(before[imageID], 1)
        scrollAway(app)
        try await control("release")
        try await Task.sleep(for: .seconds(1))
        let away = try await counts()
        XCTAssertEqual(away[imageID], 1, "No retries while offscreen")
        app.buttons["Scroll to newest message"].tap()
        XCTAssertTrue(app.images["chat-image-" + imageID].waitForExistence(timeout: 8))
        let after = try await counts()
        XCTAssertEqual(after[imageID], 2, "A cancelled offscreen load should restart when visible")
        XCTAssertFalse(app.buttons["retry-image-" + imageID].exists)
        capture("image-after-cancelled-load", app)
    }
}

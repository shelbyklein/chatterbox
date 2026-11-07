import XCTest

final class WidgetTests: XCTestCase {
    @MainActor func testBefore() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["SDHQ"].waitForExistence(timeout: 10))
        capture("before-medium", app)
    }

    @MainActor func testUsageSizes() {
        for size in ["small", "medium", "large"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_SIZE": size]
            app.launch()
            let claude = app.descendants(matching: .any)["widget-usage-claude"].firstMatch
            let codex = app.descendants(matching: .any)["widget-usage-codex"].firstMatch
            XCTAssertTrue(claude.waitForExistence(timeout: 10))
            XCTAssertTrue(codex.exists)
            XCTAssertTrue(claude.label.contains("5h 42%") && claude.label.contains("7d 81%"))
            XCTAssertTrue(codex.label.contains("5h 12%"))
            XCTAssertTrue(app.staticTexts["SDHQ"].exists)
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            for provider in [claude, codex] {
                XCTAssertTrue(widget.frame.contains(provider.frame), "\(size): \(provider.label) fits")
            }
            capture("usage-" + size, app)
            app.terminate()
        }
    }

    @MainActor func testMissingAndStale() {
        for state in ["empty", "stale"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_STATE": state, "WIDGET_LIGHT": "1"]
            app.launch()
            let claude = app.descendants(matching: .any)["widget-usage-claude"].firstMatch
            XCTAssertTrue(claude.waitForExistence(timeout: 10))
            if state == "empty" {
                XCTAssertTrue(app.staticTexts["Open Chatterbox to sync usage"].exists)
                XCTAssertTrue(claude.label.contains("Not reported"))
                XCTAssertTrue(app.descendants(matching: .any)["widget-usage-codex"].firstMatch.label.contains("Not reported"))
            } else {
                XCTAssertTrue(app.staticTexts["Last synced"].exists)
            }
            capture("usage-" + state, app)
            app.terminate()
        }
    }

    @MainActor func testUsageBoundaries() {
        for size in ["small", "medium", "large"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_SIZE": size, "WIDGET_STATE": "boundaries", "WIDGET_LIGHT": "1"]
            app.launch()
            let claude = app.descendants(matching: .any)["widget-usage-claude"].firstMatch
            let codex = app.descendants(matching: .any)["widget-usage-codex"].firstMatch
            XCTAssertTrue(claude.waitForExistence(timeout: 10))
            XCTAssertTrue(claude.label.contains("5h 0%") && claude.label.contains("7d 100%"))
            XCTAssertTrue(codex.label.contains("5h —") && codex.label.contains("7d —"))
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            XCTAssertTrue(widget.frame.contains(claude.frame), "\(size): full and zero usage fit")
            XCTAssertTrue(widget.frame.contains(codex.frame), "\(size): unknown and expired usage fit")
            capture("usage-boundaries-" + size, app)
            app.terminate()
        }
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

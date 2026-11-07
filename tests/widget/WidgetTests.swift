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

    @MainActor func testDedicatedUsageSizes() {
        for size in ["small", "medium", "large"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_KIND": "usage", "WIDGET_SIZE": size]
            app.launch()
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            XCTAssertTrue(widget.waitForExistence(timeout: 10))
            capture("dedicated-" + size, app)
            if size == "small" {
                let claude = app.descendants(matching: .any)["usage-summary-claude"].firstMatch
                let codex = app.descendants(matching: .any)["usage-summary-codex"].firstMatch
                XCTAssertTrue(claude.label.contains("100%") && claude.label.contains("2 of 2"))
                XCTAssertTrue(codex.label.contains("35%") && codex.label.contains("1 of 3"))
                XCTAssertTrue(widget.frame.contains(claude.frame) && widget.frame.contains(codex.frame))
            } else {
                for (provider, count) in [("claude", 2), ("codex", 3)] {
                    for index in 0..<count {
                        let account = app.descendants(matching: .any)["usage-account-\(provider)-\(index)"].firstMatch
                        XCTAssertTrue(account.exists, "\(size): every account is visible")
                        XCTAssertTrue(widget.frame.contains(account.frame), "\(size): account fits")
                    }
                }
                let unavailable = app.descendants(matching: .any)["usage-account-codex-0"].firstMatch
                XCTAssertTrue(unavailable.label.contains("Unavailable"))
                XCTAssertTrue(app.descendants(matching: .any)["usage-direct-codex"].firstMatch.label.contains("Chat reported"))
                XCTAssertFalse(app.descendants(matching: .any)["usage-direct-claude"].firstMatch.exists)
                if size == "large" {
                    let work = app.descendants(matching: .any)["usage-account-claude-1"].firstMatch
                    XCTAssertTrue(work.label.contains("7d Sonnet 10%"), "third quota window is retained")
                }
            }
            let age = app.descendants(matching: .any)["usage-freshness"].firstMatch
            XCTAssertTrue(age.label.contains("Quota checked"))
            XCTAssertTrue(widget.frame.contains(age.frame))
            app.terminate()
        }
    }

    @MainActor func testDedicatedUsageStates() {
        for state in ["empty", "checking", "legacy", "stale", "overflow"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_KIND": "usage", "WIDGET_SIZE": "large", "WIDGET_STATE": state, "WIDGET_LIGHT": "1"]
            app.launch()
            let age = app.descendants(matching: .any)["usage-freshness"].firstMatch
            XCTAssertTrue(age.waitForExistence(timeout: 10))
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            XCTAssertTrue(widget.frame.contains(age.frame))
            switch state {
            case "empty": XCTAssertTrue(age.label.contains("Open Chatterbox"))
            case "checking": XCTAssertTrue(age.label.contains("Checking quotas"))
            case "legacy":
                let direct = app.descendants(matching: .any)["usage-direct-claude"].firstMatch
                XCTAssertTrue(direct.label.contains("5h 42%") || direct.label.contains("42%"))
                XCTAssertTrue(age.label.contains("Synced"))
            case "overflow": XCTAssertTrue(app.descendants(matching: .any)["usage-overflow"].firstMatch.exists)
            default: XCTAssertTrue(age.label.contains("Quota checked"))
            }
            capture("dedicated-" + state, app)
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

import XCTest

final class WidgetTests: XCTestCase {
    @MainActor func testNewChatWidget() {
        for variant in ["dark", "light", "large-text"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_KIND": "new-chat", "WIDGET_SIZE": "medium",
                                     "WIDGET_LIGHT": variant == "light" ? "1" : "0",
                                     "WIDGET_LARGE_TEXT": variant == "large-text" ? "1" : "0"]
            app.launch()
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            XCTAssertTrue(widget.waitForExistence(timeout: 10))
            capture("new-chat-" + variant, app)
            for (agent, model) in [("codex", "Sol"), ("claude", "Opus 5.5")] {
                let link = app.descendants(matching: .any)["new-chat-widget-" + agent].firstMatch
                XCTAssertTrue(link.exists && link.isHittable)
                XCTAssertTrue(link.label.contains(model) && link.label.contains("Medium"))
                XCTAssertTrue(widget.frame.contains(link.frame))
                XCTAssertGreaterThanOrEqual(link.frame.height, 44)
                link.tap()
                XCTAssertEqual(app.staticTexts["opened-widget-link"].label, "chatterbox://new-chat/" + agent)
            }
            app.terminate()
        }
    }
    @MainActor func testBefore() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["SDHQ"].waitForExistence(timeout: 10))
        capture("before-medium", app)
    }

    @MainActor func testActivitySizes() {
        for size in ["small", "medium", "large"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_SIZE": size]
            app.launch()
            XCTAssertTrue(app.staticTexts["SDHQ"].waitForExistence(timeout: 10))
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            XCTAssertTrue(widget.frame.contains(app.staticTexts["SDHQ"].frame))
            assertActivityOnly(app)
            capture("activity-" + size, app)
            app.terminate()
        }
    }

    @MainActor func testActivityStates() {
        for state in ["empty", "stale", "working-only"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_STATE": state, "WIDGET_LIGHT": "1"]
            app.launch()
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            XCTAssertTrue(widget.waitForExistence(timeout: 10))
            if state == "empty" {
                XCTAssertTrue(app.staticTexts["All caught up"].exists)
            } else if state == "working-only" {
                XCTAssertTrue(app.staticTexts["1 working"].exists)
                let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Working Playcase Arcade")).firstMatch
                XCTAssertTrue(row.exists && row.isHittable)
                XCTAssertTrue(widget.frame.contains(row.frame))
            } else {
                XCTAssertTrue(app.staticTexts["SDHQ"].exists)
                XCTAssertFalse(app.staticTexts["Working Vispix"].exists, "stale work is not shown as currently working")
            }
            assertActivityOnly(app)
            capture("activity-" + state, app)
            if state == "working-only" {
                app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Working Playcase Arcade")).firstMatch.tap()
                XCTAssertEqual(app.staticTexts["opened-widget-link"].label, "chatterbox://chat/11111111-1111-1111-1111-111111111111")
            }
            app.terminate()
        }
    }

    @MainActor private func assertActivityOnly(_ app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["Usage (% used)"].exists)
        XCTAssertFalse(app.staticTexts["Open Chatterbox to sync usage"].exists)
        for provider in ["claude", "codex"] {
            XCTAssertFalse(app.descendants(matching: .any)["widget-usage-" + provider].firstMatch.exists)
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

import XCTest

final class WidgetTests: XCTestCase {
    @MainActor func testNewChatWidget() {
        for size in ["medium", "small"] {
          for variant in ["dark", "light", "large-text"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["WIDGET_KIND": "new-chat", "WIDGET_SIZE": size, "WIDGET_RESET_SELECTION": "1",
                                     "WIDGET_LIGHT": variant == "light" ? "1" : "0",
                                     "WIDGET_LARGE_TEXT": variant == "large-text" ? "1" : "0"]
            app.launch()
            let widget = app.descendants(matching: .any)["widget-preview"].firstMatch
            let field = app.descendants(matching: .any)["widget-new-chat-field"].firstMatch
            let claude = app.buttons["widget-provider-claude"]
            let codex = app.buttons["widget-provider-codex"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            XCTAssertTrue(codex.isSelected && !claude.isSelected)
            XCTAssertEqual(app.textFields.count, 0, "the widget offers a tap target, not text input")
            claude.tap() // The actual App Intent button, not a fixture action.
            XCTAssertTrue(app.staticTexts["Opus 5.5 · Medium"].waitForExistence(timeout: 10))
            XCTAssertTrue(claude.isSelected && !codex.isSelected)
            let opened = app.staticTexts["opened-widget-link"]
            XCTAssertTrue(!opened.exists || opened.label.isEmpty, "selection must not open the app/chat URL")
            for target in [field, claude, codex] {
                XCTAssertTrue(target.isHittable && widget.frame.contains(target.frame))
                XCTAssertGreaterThanOrEqual(target.frame.height, 44)
            }
            let model = app.staticTexts["widget-selected-model"]
            XCTAssertTrue(widget.frame.contains(model.frame), "selected model caption fits")
            capture("quick-actions-" + size + "-" + variant, app)
            if size == "medium", variant == "dark" {
                app.terminate()
                app.launchEnvironment["WIDGET_RESET_SELECTION"] = "0"
                app.launch()
                XCTAssertTrue(app.staticTexts["Opus 5.5 · Medium"].waitForExistence(timeout: 10), "intent choice survives process relaunch")
                XCTAssertTrue(app.buttons["widget-provider-claude"].isSelected)
                app.buttons["widget-provider-codex"].tap()
                XCTAssertTrue(app.staticTexts["Sol · Medium"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["widget-provider-codex"].isSelected)
                capture("quick-actions-codex", app)
            }
            app.descendants(matching: .any)["widget-new-chat-field"].firstMatch.tap()
            XCTAssertEqual(app.staticTexts["opened-widget-link"].label, "chatterbox://new-chat", "the app resolves the latest shared selection at tap time")
            app.terminate()
          }
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

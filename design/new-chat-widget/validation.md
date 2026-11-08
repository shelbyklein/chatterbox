# New Chat widget verification

Baseline parent `ed50e42`, Core `4a5b948`. Separate `ChatterboxNewChat` medium widget; existing Activity and Usage kinds are preserved. Fixed shared shortcut values: Codex `gpt-6.1-sol`, Claude `claude-opus-5-5`, both `medium`. No messages, agent turns, Desk tasks or project/Studio context are created. Ordinary new-chat permission defaults remain unchanged. A pending shortcut waits for pairing; in-flight duplicate URLs are ignored. Loading, failed creation, retry and sheet-dismissal-before-navigation use the existing create API.

## Tests

- `scripts/test-widget.sh`: **6 native tests passed in 91.879 seconds**, plus model/cache checks. Artifact `build/widget-test.mTGqAo`, log `build/new-chat-widget-native.log`. Includes both links with exact destinations, hit target bounds, light/dark/xxxLarge type, and all existing Activity/Usage sizes and boundary states. Shared checks verify shortcut model/effort, URL round trip and rejection of altered scheme, unknown path, trailing slash, settings query, fragment, credentials and port.
- Focused native phone flow: `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testWidgetNewChats,HomeNavTests/HomeNavTests/testUsage,HomeNavTests/HomeNavTests/testNewChatPicksSettingsFirst MOBILE_TEST_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-2 scripts/test-mobile-home-nav.sh iphone`: **3 tests passed in 111.541 seconds**. Artifact `build/mobile-home-nav.reyq3X`, log `build/new-chat-widget-navigation.log`. Both actions create unique ordinary chat IDs with exact model and Medium payload, no messages or place/preset/permission overrides. Tests cover replacing an open Usage sheet, cold launch, failed creation and retry, existing new-chat choices and Usage URL/cold-quota follow-up.
- `scripts/test-tests-for.sh`: **10 passed**. Source check, Python fixture syntax and parent/Core diff checks passed. Selector reasoning saved in `build/new-chat-widget-selection.log`. App entry point is also compiled by seven other mobile suites; their broad unrelated flows were not rerun for this focused change. No full-release-green claim; full release check deferred to Ship with known chat-switch mismatch/incomplete coverage retained.

## Visual review

First native batch inspected: widget light/dark/xxxLarge, new Codex/Claude blank composers, error retry and Usage. Both targets fit, and blank chats/error flow render correctly. Found weak colored text in the light widget. Batched correction switches labels to system foreground and confines agent colors to compose icons with darker light-mode accents. Final confirmation passed in **16.447 seconds** (`build/widget-test.wGYNq5`, `build/new-chat-widget-confirm.log`). Inspected the final three native renders: high-contrast labels, distinct compose icons, readable model/Medium text and bounded targets at xxxLarge. Two visual rounds complete; no further polish or reruns. The pressure queue held new builds while overloaded and resumed without overrides. No target source files added; project regeneration unnecessary.

## Delivery

Pending confirmation, commits and phone Dev installation. Dev embeds no Home Screen widget; activation requires Ship. No Mac installation/restart or TestFlight.

## Native evidence

[Dark widget](new-chat-dark.png), [light widget](new-chat-light.png), [larger text](new-chat-large-text.png), [new Codex chat](widget-new-codex.png), [new Claude chat](widget-new-claude.png), [retry](widget-new-chat-error.png), [retained Usage entry](usage.png). Original simulator screenshots from isolated synthetic fixtures, iPhone17Pro/iOS26.2.

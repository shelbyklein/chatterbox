<!-- quick-actions-widget-2026-11-08 -->
# New Chat quick actions

Replace the two launch tiles with a field-shaped full-width “New chat…” target and persistent Claude/Codex provider chips below it, following Shelby’s attached reference. A provider chip performs an App Intent in the widget, highlights the selection and stores it in the existing app group without starting a chat. The field opens a blank chat using the latest saved provider and raises the keyboard.

## Work preparation

Shelby's explicit request confirms implementation now and Dev phone delivery. Prerequisite issue66 implementation/verification/Dev delivery is complete (parent8d8570c, Coreb170c98); its separate real shipment remains pending. Baseline is that same source. Mode: linear, because persistence/intent, widget and navigation/focus form one flow; current session, exact model/effort unavailable. R1-R13 pass. No blocking questions. Tracking: [issue67](https://github.com/shelbyklein/chatterbox/issues/67). No real install or issue closure authorized.

Current UI: [two-tile native widget](../design/new-chat-widget/new-chat-dark.png). Target, inheriting the native widget surface/type/accent palette:

```text
[ compose   New chat…                         ]
[ Claude ]  [ Codex •selected ]
Sol · Medium
```

Medium uses the full-width target and two highlighted provider chips. Small keeps the same compact controls and a widgetURL fallback for the field/background. Keep the established Codex/Sol/Medium and Claude/Opus5.5/Medium profiles, default Codex when no valid selection exists. Selection is app-group shared across New Chat widgets, not per-widget configuration. Generic field URL resolves preferences at tap handling, so a stale timeline cannot choose an old provider. Preserve older /codex and /claude URLs. No text input is attempted in WidgetKit.

## Success and deliverables

1. Real Button(intent:) controls change/highlight the selected provider without opening a chat; new process/widget timeline reads it from the existing app group. Native tests tap the actual intent buttons in an isolated SwiftUI fixture, verify highlight, unchanged opened URL, persistence across relaunch, and generic field destination. Model checks cover fresh readers, invalid values, generic/legacy URL resolution and exact fixed models.
2. Medium/small native renders are readable in light/dark and larger type. Existing activity (without usage), dedicated Usage and New Chat identities remain intact. Original native screenshots and bounded visual review are committed.
3. Native phone URL tests open fresh ordinary chats for both providers with an already-focused composer and keyboard, type an unsent draft without tapping the field, and verify no messages sent. Existing Usage/new-chat settings and failure/retry remain covered.
4. Core first and parent committed/pushed, Xcode project regenerated for the shared intent source, signed device extension/intent metadata verified and phone Dev installed. Dev has no widgets: physical Home Screen interactivity/appearance and real installation remain pending Ship. No Mac install/restart or TestFlight.

## Tasks

- [x] Q1 Persist provider choice and implement the interactive field/chips widget. Acceptance: app-group store/model checks, actual App Intent selection/persistence checks, generic field link, native medium/small bounds and preserved incumbent widgets pass.
- [x] Q2 Focus the new widget chat’s composer once after navigation. Acceptance: warm/cold URL entry and retry show a keyboard, allow typing without a focus tap, preserve previous drafts and send no messages; ordinary chat navigation does not gain autofocus.
- [ ] Q3 Verify, inspect, commit/push and deliver Dev. Acceptance: scripts/test-widget.sh and focused native phone flows pass; two visual rounds maximum; project/source/signature/intent checks and actual phone install result recorded. Keep issue open pending Ship/physical acceptance.

## Tests, scope and rollback

Run scripts/tests-for.sh --why --since 8d8570c; scripts/test-widget.sh (including actual App Intent buttons) and MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testWidgetNewChats,HomeNavTests/HomeNavTests/testUsage,HomeNavTests/HomeNavTests/testNewChatPicksSettingsFirst MOBILE_TEST_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-2 scripts/test-mobile-home-nav.sh iphone. Keep focused keyboard/render checks for ChatDetailView; do not substitute compilation for these flows. Include model persistence/URL checks, Xcode source/intent metadata and parent/Core diff checks. Inspect one native batch, fix findings together and confirm at most once. Full release checks deferred to Ship; known chat-switch mismatch/incomplete coverage remains recorded.

Use Apple's AppIntent pattern, registered in app and widget targets: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities. Widget timeline reads the saved selection after intent completion; no LiveActivityIntent or openAppWhenRun. No widget networking, model/provider account routing changes, sends, project/Studio/Desk tasks, existing chat settings, permission defaults, credentials, pairing or schedule changes. New preference key only in the existing app group (Dev fallback is its own standard preferences); no migration or deletion. Roll back commits and reinstall using repo scripts; older code ignores the optional preference, and legacy links still work. Open questions: none.

<!-- new-chat-widget-2026-11-07 -->
# New Chat widget

Add a separate Home Screen widget with two quick actions: Codex using GPT-6.1-Sol at Medium, and Claude using Opus 5.5 at Medium. Today the activity and Usage widgets only open existing threads or Usage; new chats require the in-app settings flow. Each action should create an ordinary blank chat and open its composer, without sending a message or launching an agent turn.

## Work preparation

Shelby's direct request specifies the widget, agents and effort and authorizes implementation now. Sol maps to the app's current GPT-6.1-Sol (existing native model fixtures); Claude's explicit model is claude-opus-5-5. Mode: linear because shared shortcuts, app routing and widget depend on each other; current session, exact model/effort unavailable. Baseline parent ed50e42, Core 4a5b948. Readiness R1-R13 pass; scope settled, no blocking questions. Tracking: [issue 65](https://github.com/shelbyklein/chatterbox/issues/65). Dev delivery standing-approved; real Ship and closure require Shelby.

Current native widget: [Usage](../design/dedicated-usage-widget/dedicated-medium.png). Existing new chat sheet: Core/ChatterboxMobile/MobileNewChat.swift; existing URL router: ChatterboxMobile/ChatterboxMobileApp.swift; create API: MobileStore.newChat. New medium widget (two independently tappable links, supported on medium):

```text
New Chat
[ compose   Codex        ] [ compose   Claude          ]
[           Sol         ] [           Opus 5.5        ]
[           Medium      ] [           Medium          ]
```

Direction: Operate; extend existing native widget surface, system type and blue/orange agent accents. Two large compose targets with explicit model/effort, no extra metrics. Pair/connect if necessary; preserve the requested shortcut until paired. Create exactly once while a request is in flight; show loading and recoverable errors. A tap opens a fresh ordinary Chats conversation with explicit model/effort; it never changes existing chats or sends a prompt.

## Outcomes and deliverables

1. Every shortcut URL deterministically selects the requested backend/model/medium effort. Only known shortcut paths/schemes are accepted; arbitrary URL settings are rejected. Shared model checks verify round trip and malformed links.
2. Native URL tests open both fresh chats, assert exact creation payload, ordinary destination and zero sent messages; duplicate in-flight delivery is guarded and failed creation can retry.
3. Native medium-widget captures in light/dark and large text show two readable, bounded hit targets. Existing activity/Usage widget tests remain green. Original screenshots and test results are committed.
4. Core first and parent committed/pushed; phone Dev installed, signed widget extension built. Dev embeds no widget; actual Home Screen activation awaits Ship. No Mac or service restart, TestFlight, credential/config changes.

## Tasks

- [x] N1 Add shared fixed shortcuts and app URL lifecycle. Acceptance: strict URL parsing/model checks and native create/error/pairing flow using existing create endpoint with no message POSTs.
- [x] N2 Add New Chat medium widget. Acceptance: two independent links, correct labels/settings, accessible targets fit light/dark/large text; preserve incumbent kinds.
- [x] N3 Run focused checks, inspect bounded native screenshots, commit/push and deliver Dev. Acceptance: model/widget and native URL flow pass, device extension verified, phone install result recorded. Keep issue open pending Ship/acceptance.

## Tests, boundaries and rollback

Use scripts/tests-for.sh --why --since ed50e42 and run its focused scripts: scripts/test-widget.sh plus native HomeNavTests/HomeNavTests/testWidgetNewChats (MOBILE_TEST_ONLY and iPhone/iOS26.2), retaining existing new-chat and Usage entry tests if route changes affect them. Model checks cover fixed URLs, scheme/path/query rejection. Native tests exercise Home Screen URL entry for both actions and observe creation/sent requests; render widget links with true system SwiftUI at medium size, light/dark/larger type. Inspect one batch, fix findings together, confirm at most once. Full release suite deferred to Ship; known chat-switch mismatch/incomplete coverage remain disclosed.

No schema migration or wire/service change, no changes to presets/defaults, existing chat settings/history, Desk, Studio/project placement or pairing credentials. URL has a fixed shortcut only, not user-supplied model/mode/permission settings. Permission mode stays the ordinary new-chat default. No network in widget itself. Revert this task's commits and reinstall through repo scripts to roll back; no user data is deleted and older widgets keep their identities. Open questions: none.

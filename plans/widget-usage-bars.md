# Usage bars in the iOS widget

The Home Screen widget currently lists Claude and Codex usage as percentages. Shelby requested bars so relative usage is visible at a glance. Add one determinate bar per displayed limit window, alongside the existing labels and percentages; retain the widget's native styling, activity rows and links.

## Work preparation

Scope and implementation timing are authorized by Shelby's direct request to add usage bars. Linear execution because the shared validity rule, widget rendering and native fixtures depend on each other; current session, exact model/effort unavailable. Baseline parent `8b62317`, Core `368b1c2`. Readiness: R1–R13 pass; no blocking questions. Dev installation has standing approval; real activation requires a new Ship. Tracking: [issue 63](https://github.com/shelbyklein/chatterbox/issues/63).

Current code: `Core/ChatterboxWidget/ChatterboxWidget.swift` usageRow/usageColumn render text only. `Core/Shared/WidgetSnapshot.swift` Window.text already rejects unknown/nonfinite/expired readings. [Current medium widget](../design/widget-usage/usage-medium.png), [current small widget](../design/widget-usage/usage-small.png). Captures match the current widget source.

Target sketch (each bracket is a separate usage bar):

```text
Medium / large
Usage · Last synced 2m ago
Claude  5h 42% [####------]  7d 81% [########--]
Codex   5h 12% [#-----------------------------]

Small
Usage (% used)
Claude             Codex
5h 42%             5h 12%
[####------]       [#---------]
7d 81%
[########--]
```

## Success and delivery

- Each displayed window has its own accurate bar from zero to full, while labels/percentages and usage links remain intact. Shared data normalization is exercised by model checks.
- Unknown/nonfinite/reset readings retain their existing unavailable text and never show a misleading filled or animated bar. No new provider requests or snapshot schema fields.
- Small, medium and large native renders fit activity plus usage without clipping; low/high/full/empty readings and light/dark appearances are inspected. Native fixture tests and screenshots verify layout and accessibility text.
- Commit/push Core then parent; build the real widget target and install the phone Dev app. Dev intentionally contains no widget, so widget activation on the physical phone remains pending Ship. No Mac installation or service restart is needed.

## Tasks

- [x] B1 Add bars with the same validity/clamping rule as text. Acceptance: finite live readings map to [0,1], unknown/expired readings have no bar, current labels and navigation remain.
- [x] B2 Run focused widget checks and inspect native captures. Acceptance: all three sizes, missing/stale readings and boundary values render clearly; selector/source/diff checks pass.
- [x] B3 Commit/push and deliver phone Dev; record actual installed state and real-widget activation boundary. Acceptance: widget device extension built, Dev installed, evidence and issue updated; real app unchanged.

## Boundaries, tests and rollback

No activity sorting/count changes, Lock Screen changes, refresh timing, account/proxy changes, network calls, migrations or model calls. Preserve the two displayed windows per provider and the established native colors; normal usage uses the app accent, 75% uses orange and 90% red, matching Usage screen meters. Percentages remain readable without color. No new target sources; project regeneration is not needed.

Run `scripts/tests-for.sh --why Core/ChatterboxWidget/ChatterboxWidget.swift Core/Shared/WidgetSnapshot.swift tests/widget` then the selected focused tests via `scripts/tests-for.sh --run --fail-fast` with the same paths. Use `scripts/test-widget.sh` native fixtures for actual SwiftUI widget rendering at widget dimensions, not mockups. Inspect one batch of captures; correct all observed defects in one batch and confirm once at most. Use the repository build/simulator locks and existing fixed build folders. Run `scripts/check-sources.sh` and diff checks. Full release suite is deferred to Ship, with the existing chat-switch baseline failure and incomplete coverage retained.

Rollback: revert only this task's source commits and reinstall the appropriate phone flavor through its repository script. This change adds no saved fields or data migration; snapshot/app-group identity remains the same. Open questions: none.

## Dev delivery

Core `ed603d0`, parent source `1d60ba6` committed/pushed to main. Phone Dev installed and opened on Shelby's Duo. The device widget extension built and its signature verified; Dev does not embed it. Real app/service/configuration hashes stayed unchanged. [Delivery evidence](../design/widget-usage-bars/dev-delivery.json). Real widget activation awaits Ship; issue 63 remains open.

## Real shipment

Shipped the phone/widget November 7 from parent `b383c9f`, Core `ed603d0`. Final release run: 11 passed, the same approved chat-switch failure, 101 unrun; source and assertion unchanged. Retained Shelby's explicit approval for that known limitation. Installed on Shelby's Duo with widget extension; opening requires unlocking the phone. No Mac install/service restart or TestFlight. [Real delivery evidence](../design/widget-usage-bars/real-delivery.json). Physical widget appearance and user acceptance remain pending.

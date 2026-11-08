# Activity-only widget verification

Baseline parent `e3ab4cf`, Core `e56b645`. Removed usage from the activity widget’s small/list layouts and deleted its now-unused footer, row/column and bar helpers. Gallery description now names activity only. Activity kind, chat links, row limits, attention/working ordering, stale-work behavior and Lock Screen rendering remain unchanged. Dedicated Usage/New Chat, usage data and refresh/cache logic are unchanged.

## Checks and visual review

- `scripts/tests-for.sh --why --since e3ab4cf` selected the widget suite plus source checks (new documentation). Source check passed. Final `scripts/tests-for.sh --run --fail-fast Core/ChatterboxWidget/ChatterboxWidget.swift`: **1 passed, 0 failed, 0 not run** (`build/activity-widget-only-confirm.log`).
- `scripts/test-widget.sh` final native run: **5 tests passed in 81.353 seconds**, plus all model/cache checks. iPhone17Pro/iOS26.2, artifact `build/widget-test.ss35PJ`, copied log `build/activity-widget-only-final-native.log`. Covers activity small/medium/large, empty/stale/one-working state, absence of usage labels/rows, actual working-row tap to the expected chat URL, dedicated Usage sizes/all-account states, and both New Chat links/light/dark/larger type.
- First run: activity sizes and the two dedicated widgets passed; the state test made an incorrect assumption that SwiftUI exposed its row as an AX Link. Corrected the query to its visible label and strengthened it with an exact tapped-URL assertion using a stable synthetic chat ID. No product navigation defect was found. First log `build/activity-widget-only-first-native.log`, artifact `build/widget-test.kGc4IY`.
- Two bounded visual rounds: inspected five first-round activity renders, then all six final activity captures. Footer and usage bars are absent, activity rows/caught-up/age remain readable and within bounds. The working-only capture reproduces Shelby’s reported state. No further polish or reruns.
- Parent/Core diff checks passed. No new target files; project regeneration unnecessary. Full release checks are deferred to Ship; known chat-switch mismatch/incomplete coverage remains recorded, no full-green claim. Shared pressure safeguards held the confirmation build while overloaded and resumed without overrides.

## Native evidence

[Small](activity-small.png), [medium](activity-medium.png), [large](activity-large.png), [empty](activity-empty.png), [stale](activity-stale.png), [one working thread](activity-working-only.png). Original native screenshots from isolated synthetic fixtures.

## Delivery

Core `b170c98` and parent source `87e8448` committed and pushed. Phone Dev installed on Shelby’s Duo; launch was denied because the device is locked (CoreDevice10002/FBS Locked). Signed device extension built and verified, with Usage and New Chat retained. Dev embeds no widgets, so real Home Screen activation requires Ship. Real Mac app/service/host and automation hashes unchanged. No Mac install/service restart or TestFlight. [Delivery metadata](dev-delivery.json).

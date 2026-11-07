# Widget usage validation

Baseline: parent `04c9936`, Core `72ab7d1`. The widget keeps its existing activity identity and adds Claude/Codex limit windows beneath it. Small uses two narrow provider columns; medium reserves two activity rows including working chats; large retains six activity rows. Lock Screen views are unchanged. The small widget keeps its single chat-opening action; medium/large usage links open the app's Usage sheet.

Data comes from the existing read-only companion usage route. Successful chat refreshes schedule a nonblocking, once-a-minute usage read; no provider refresh or new background task is requested. The Usage sheet also writes the cache. Usage has its own sync timestamp, separate from activity. Missing windows say Not reported, and expired/unknown percentages show a dash. A passed reset never fabricates zero usage. Proxy accounts and account identities are not copied into the widget.

## Evidence

- `scripts/test-widget.sh`: native fixture render plus behavioral checks. Snapshot tests cover legacy decode, correct units, nil/nonfinite/expired readings, bounds, atomic reload, unchanged-content writes, usage-only timeline reload, usage retention across chat refreshes and pairing cleanup. Sync tests use the real MobileWidgetSync implementation, redirecting only disk storage and WidgetCenter reload notification to isolated fixtures; seen-reply filtering is a fixture stub with no activity.
- The native harness compiles the actual widget source, removes its WidgetBundle entrypoint and substitutes an injected family for WidgetKit's read-only environment. It renders inside a normal app at small/medium/large widget dimensions. This verifies native layout, not SpringBoard hosting, app-group entitlements or physical widget refresh budgets.
- The first harness build failed because widgetFamily is read-only; the harness now injects that family. The first rendered run reported containment failures because the fixture identifier attached to its header text; a proper accessibility container corrected the assertion. No product-layout defect was hidden by dropping a check.
- Final widget run `build/widget-usage-native-final.log`: behavioral checks pass; two native tests pass (five states), covering small/medium/large dark and empty/stale light. All five captures were inspected: usage is legible and contained; empty readings show Not reported; stale readings show a two-hour sync age. Existing compact activity summaries retain their truncation behavior.
- Existing Usage flow, `build/widget-usage-phone-flow.log`: native iPhone 17 Pro/iOS 26.2 test passes in 19.468s. Claude 81% used, Codex 12% used and proxy 65% left remain correct. The same test opens `chatterbox://usage` through the iOS URL entrypoint and verifies Usage opens again.
- `scripts/check-sources.sh`, parent/Core diff checks pass. No new target source files, project generation or Mac build is required.
- Final selector run: `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testUsage scripts/tests-for.sh --run --fail-fast tests/widget/ModelChecks.swift tests/mobile-home-nav/HomeNavTests.swift` reports **2 passed, 0 failed, 0 not run** (`build/widget-usage-focused-final.log`). This repeats the Usage URL flow on iPhone/iOS 27.0 and widget renders on iOS 26.2.
- Final cache review found subsecond phone sync dates would differ after ISO8601 persistence, which stores seconds, causing needless timeline reloads on unchanged chat polls. Sync dates now use storage precision. The fractional-date regression and persistence/sync checks pass via `WIDGET_MODEL_ONLY=1 scripts/tests-for.sh --run --fail-fast tests/widget/ModelChecks.swift` (**1 passed, 0 failed**, `build/widget-usage-cache-final.log`). No visual source changed after the rendered checks.
- Both final passes waited for the shared Mac pressure guard; it was not bypassed. These are focused checks, not a full release-suite result.

## Captures

[Before](before-medium.png), [small](usage-small.png), [medium](usage-medium.png), [large](usage-large.png), [no readings](usage-empty.png), [stale sync](usage-stale.png).

All values are synthetic. Real app/service/data/pairings have not been changed. Dev has no widget or App Group, so direct Dev phone delivery cannot activate this footer in the real widget. Ship remains required for that activation.

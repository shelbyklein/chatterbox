# iOS widget usage

The existing iOS widget shows waiting chats, new replies and work in progress, but no account usage. Add the same Claude and Codex limit percentages already available in the phone's Usage screen underneath the Home Screen widget's activity. Usage must remain clearly labelled as used, distinguish missing/expired readings, and carry its own last-sync time.

## Work preparation

Tracking: [issue 61](https://github.com/shelbyklein/chatterbox/issues/61). Shelby's direct request authorizes implementation now. Mode: linear, because snapshot, sync and rendering share the same files. Executor: current session; exact model/effort unavailable. Readiness: R1–R13 pass. No blocking questions. The incumbent native widget styling is the visual authority; this is an additive footer. Baseline: parent `04c9936`, Core `72ab7d1`.

Current: `Core/ChatterboxWidget/ChatterboxWidget.swift` renders activity only; `MobileWidgetSync.swift` writes chat-only snapshots. The app fetches limits through the read-only `/v1/usage` API.

[Current native capture](../design/widget-usage/before-medium.png), [small target](../design/widget-usage/usage-small.png), [medium target](../design/widget-usage/usage-medium.png), [large target](../design/widget-usage/usage-large.png). These are native fixture renders, not physical installed-widget screenshots.

```text
Current Home Screen           Target Home Screen
2 waiting · 2 new             2 waiting · 2 new
Activity rows                 Activity rows
                              Usage · synced 2m ago
                              Claude  5h 42% · 7d 81% used
                              Codex   5h 12% used
```

## Success and deliverables

- Small, medium and large widget fixtures show readable Claude/Codex limits, without displacing all activity. Lock Screen widgets retain their existing compact activity display.
- Existing snapshots decode with no usage; unknown/expired values never appear as zero usage. Usage-only changes reload timelines and chat changes preserve usage. Verify behavioral tests plus native rendered captures.
- Usage refreshes at most once a minute while the app loads chats, without requesting a provider refresh. Usage screen loads update the same cache. Forgetting a Mac clears its widget data and in-flight usage cannot repopulate it.
- Commit/push Core then parent, install the phone Dev app, and report that Dev intentionally has no widget. Widget activation in the real phone app requires a subsequent Ship; no TestFlight upload or Mac install is needed.

## Tasks

- [x] W1 Implement additive snapshot, safe phone sync and native usage footer. Acceptance: old data and activity navigation remain valid; percentages, unknown/reset states and freshness have behavioral coverage.
- [x] W2 Run focused native widget and existing Usage flows; inspect small/medium/large and empty/stale captures. Acceptance: native screenshots show readable unclipped content; focused tests and source checks pass.
- [ ] W3 Commit/push, install phone Dev and record delivery. Acceptance: source revisions and actual install result recorded; real app/widget untouched, activation pending Ship.

## Boundaries, tests and rollback

No quota estimates, summed provider accounts, token/cost tracking, provider API requests, new background networking, changes to account routing or Lock Screen density. Keep widget identity, App Group, chat links and Dev isolation unchanged. Proxy account quotas remain in the existing Usage screen; do not combine their remaining quotas with direct agent usage.

Run `scripts/test-widget.sh`, focused `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testUsage scripts/test-mobile-home-nav.sh iphone`, `scripts/tests-for.sh --why` and `scripts/check-sources.sh`. Native fixtures use the actual widget view at widget dimensions, with synthetic values and isolated test state. Inspect the resulting screenshots; a fixture is not installed-widget proof.

Rollback: revert this task's source commits and reinstall the appropriate flavor with the repository script. Snapshot changes are optional/additive, so older code ignores usage; no migration or real data rewrite is required. Dev has no App Group and cannot overwrite the real widget cache. Real delivery and issue closure remain gated by Shelby.

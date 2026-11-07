# Dedicated account Usage widget

The current activity widget shows only chat-process Claude/Codex limits and caps each provider at two windows. It discards proxy accounts, so Claude can appear unreported while valid proxy quotas are available. Shelby chose a dedicated Usage widget to include all account sources and limits without crowding activity.

## Work preparation

Shelby's direct request and choice of the dedicated widget confirm scope and authorize implementation now. Mode: linear because snapshot, refresh and presentation depend on each other; current session, exact model/effort unavailable. Baseline parent `7a117b9`, Core `ed603d0`. Readiness R1–R13 pass. No blocking questions. Dev phone delivery has standing approval; real widget activation and closure remain gated by Shelby. Tracking: [issue 64](https://github.com/shelbyklein/chatterbox/issues/64).

Evidence: `MobileWidgetSync.updateUsage` copies only direct arrays; activity usageRow/usageColumn/summary prefix two windows. Read-only live `scripts/test-proxy-quota.sh --live` found two Claude accounts (Limited with two windows, Available with three), three Codex accounts (two unavailable, one reporting one window). No names/credentials were exported. Log: `build/widget-all-usage-live-proxy.log`. [Current activity widget](../design/widget-usage-bars/usage-medium.png). Quotas on the wire are remaining fractions, while direct limits are used fractions; they must not be summed or conflated.

Target large widget, same native surface and usage colors:

```text
Usage · % used                       Quota checked 2m ago
Claude · 2 accounts                  Codex · 3 accounts
Personal                 Limited     Account One       Unavailable
5h          100% [##########]         Account Two       Unavailable
7d           60% [######----]         Account Three
Work                                 5h          35% [###-------]
5h           30% [###-------]         Chat reported
7d           20% [##--------]         5h          22% [##--------]
7d Sonnet    10% [#---------]
```

Small summarizes the highest used limit and reported-account counts per provider, explicitly labelled as highest, not total quota. Medium shows every account's tightest limit/status. Large shows all windows per account, plus separately labelled direct readings. All sizes open the existing full Usage screen; unusually large lists use an explicit overflow count/link instead of clipping or silently dropping readings. Existing activity/Lock Screen widgets retain their behavior and identity.

## Success and deliverables

1. The snapshot preserves every proxy account, window, status and quota-check timestamp. Convert remaining to used exactly once; retain unknown, expired, disabled/unavailable states. Old snapshots still decode. Verify model persistence and normalization checks.
2. Initial async quota refresh is represented as checking, preserves old readings with their real check time, and receives one bounded follow-up read. Pairing cancellation guards and existing service refresh policy stay intact. Verify pure pending-state tests and the native Usage flow.
3. New gallery widget `Usage` offers small, medium and large. Native renders show both Claude accounts (including the third model-specific window), all three Codex accounts, direct limits labelled separately, unknown/expired and overflow states without clipping. No totals across accounts or fictional zeroes.
4. Core and parent committed/pushed; real widget target built for device; phone Dev installed/reopened and actual result recorded. Dev embeds no widget, so physical activation awaits Ship. No Mac install/restart or TestFlight.

## Tasks

- [x] U1 Preserve all usage sources and handle cold proxy refresh. Acceptance: backward-compatible data, six synthetic proxy windows across five accounts and statuses survive sync/cache/clear; normalized used readings are correct; pending/cancel guards hold.
- [x] U2 Add dedicated widget and representative native fixtures. Acceptance: all sizes, large full list, unavailable/reset, long labels and explicit overflow render with readable bounds, source/freshness labels and correct usage link.
- [ ] U3 Run selected focused tests, inspect bounded native captures, commit/push and deliver phone Dev. Acceptance: widget and native Usage flows pass; device extension built; Dev install state and real-data isolation recorded; issue remains open pending Ship/acceptance.

## Tests, scope and rollback

Run `scripts/tests-for.sh --why` and `--run --fail-fast` for changed widget/shared/sync/store sources; retain the existing focused Usage navigation flow (`MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testUsage`, iPhone/iOS 26.2). Use `scripts/test-widget.sh` for model/cache checks and actual native SwiftUI fixtures at all three widget sizes. Inspect one batch of synthetic captures, fix any findings together, then confirm once at most. Run source/diff checks. No new target sources are expected, so no project regeneration is needed unless that changes. Full release suite is deferred to Ship; known chat-switch mismatch and incomplete coverage remain disclosed.

No account routing, credentials, proxy settings, provider refresh cadence, model calls, live source checks, activity ordering or real installation changes. The widget reads the app-group cache and does no networking. A bounded phone follow-up uses the existing read-only service endpoint, not a new provider API. Quota timestamps remain distinct from phone sync time. Account display names exist only in the same protected on-device cache; all fixtures and committed screenshots use invented names/values.

Rollback: revert this task's source commits and reinstall through repository scripts. Snapshot fields are optional/additive; there is no migration, data deletion or identity change. Existing widgets remain registered. Unknown fields are ignored by older builds. Open questions: none.

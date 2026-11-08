<!-- archived-center-2026-11-08 -->
# Browse archived threads in the center pane

The Mac Archived button currently opens a narrow popover of sidebar cards, as shown in [the current screenshot](../design/archived-view/before.png). It also filters the archive through the active sidebar search, tags and Studio. Replace that popover with an Archived page in the main/center pane, with every archived thread and a dedicated search.

## Work preparation

Shelby directly requested this change; scope is clear and implementation is requested now. Linear execution: one native navigation/search surface with shared state, current session; exact model/effort unavailable. Baseline parent `8a65585`, Core `5d43157`. Isolated checkout `/Users/shelbyklein/Vibes/Chatterbox-archived-view` preserves concurrent main Core/MacPressure work. R1-R13 pass. No blocking questions. Tracking: [issue68](https://github.com/shelbyklein/chatterbox/issues/68). Dev install/reopen and idle-safe Dev service restart have standing approval; real shipment and issue closure require Shelby.

Target, preserving native app typography, surfaces and thread cards:

```text
Sidebar                         Center pane
…                               Archived                 364 threads
[Archived 364]                  [ Search archived threads…        ]
                                [thread card] [thread card] …
                                scroll through all archived threads
```

## Success and deliverables

1. The actual Archived dock button opens the full center-pane browser with the sidebar retained, no archive popover, and an accurate global count. Native entry-point test and inspected wide/narrow Mac screenshots verify it.
2. All archived threads appear newest-archived first, independent of sidebar section/tag/search filters. Dedicated case-insensitive, multiword search matches title, project, Studio, tags and available preview; blank query shows all, no-match/empty states are clear. Behavioral fixture covers more than a screenful and cross-section results.
3. Opening a result selects the existing archived thread without copying, sending or unarchiving it. Returning to Archived preserves the in-window query. Projects/Studios/Chats, Desk, Settings, Command Center and Automations leave Archive correctly, and the native toolbar reflects Archive rather than the previously selected chat.
4. Core then parent changes committed/pushed, required Xcode project regeneration recorded, focused behavior/native rendered checks passed, Mac Dev installed/reopened, service restart queued only if needed. Real app, phone and config remain untouched; installed runtime acceptance reported separately from fixture evidence.

## Tasks

- [x] AR1 Implement the global archive query and navigation state. Verify complete inventory/order/search and transitions with `scripts/test-view-memory.sh`.
- [x] AR2 Replace the popover with the center-pane card browser and toolbar state. Native test clicks the real entry, exercises search/open/return, renders wide/narrow/empty/no-match and checks bounds. Inspect once, fix findings together, confirm at most once.
- [x] AR3 Regenerate project if adding source, run source/flavor/mapped focused checks, commit/push Core then parent and install Mac Dev. Record exact results and revision-pinned proof; keep issue open pending real Ship and user acceptance.

## Tests and boundaries

Use `scripts/tests-for.sh --why --since 8a65585` and the mapped focused tests. Extend `scripts/test-view-memory.sh` for navigation and real center-pane/search rendering; preserve its existing section memory, Sidechat, empty-section and narrow-sidebar checks. Add selector mapping for the new view. Run `scripts/check-sources.sh`, `scripts/test-flavor.sh`, and diff checks. All builds use shared locks/fixed build folders; no phone build needed. Full release run deferred until Ship.

No data migration, transcript preload for search, archive/delete/restore semantics, iOS, Desk, provider, service protocol, unrelated Mac pressure changes or real install. Opening a result remains read-only; existing send-to-unarchive behavior stays. Rollback: revert these commits and reinstall Dev with repo scripts; no user data or archive records are changed, so no data backup/migration needed. Open questions: none.

## Verified Dev delivery

Core implementation50eaf47, parentac1fe3a; integrated Core-first with concurrent completed pressure work into Core348dfbc/parent47825f1 and pushed main. Archive and view-memory fixtures passed again on the combined source. Ten selector checks, source regeneration/checks and real/Dev flavor checks passed. Two bounded visual rounds: native fixtures, then installed Dev.

Mac Dev installed and reopened; idle restart at10:15:32 and health ok at10:15:34. Actual Archived entry opened the center page with4 existing Dev threads; preview search narrowed to1 and Clear returned to4. No messages sent, no archive status changed. Real Mac app/service/host and Automations hashes unchanged. [Validation](../design/archived-view/validation.md), [installed capture](../design/archived-view/dev-installed.png), [delivery](../design/archived-view/dev-delivery.json). Real Ship and user acceptance pending; keep issue open.

## Real shipment — November 8

Shelby authorized “ship archived view.” `scripts/ship.sh` installed/reopened parent1c0360b/Core348dfbc; installed app/service/host match built binaries and strict signature checks pass. Normal between-turn restart at10:37:44; service healthy10:37:55. Actual native Archived button opened the main center pane. Search found the requested logo thread, and Clear restored the full archive. Count changed364→365 during live verification. The app is left on Archived with search cleared; no archive/send/restore action was invoked. Original real-app screenshot remains local at `build/archived-view-real-installed.png`. Automations.json hash unchanged. No phone build or TestFlight.

Release run: **12 passed, 1 failed, 101 not run**. Same unchanged `test-chat-switch.sh` policy assertion Coordinator.swift:11, exit133; shipped under Shelby’s earlier explicit approval for that known failure and incomplete coverage. Full suite is not green. [Real delivery](../design/archived-view/real-delivery.json). Keep issue open for user acceptance/closure approval.

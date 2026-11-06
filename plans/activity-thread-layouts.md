<!-- activity-thread-layouts-2026-11-06 -->
# Full thread cards and list rows in iOS Activity

Activity now has its own destination but still renders the compact embedded-activity table. Shelby requested the same card/list presentation as the thread browsers, with space for titles and latest messages. Reuse ChatCard and ChatRow rather than designing another visual style.

Current proof: [Activity](../design/activity-tab-only/duo-dedicated-tab.png). Incumbent components: [cards](../design/activity-tab-only/duo-projects-cards.png), [list](../design/activity-tab-only/duo-projects-list.png). Source: Core/ChatterboxMobile/ChatListView.swift activityPage/menu and MobileNewReplies.swift dedicated rendering.

## Target sketch and behavior

```
Activity                 … > Show as Cards / Show as List
4 active · 1 new                          Mac pressure
Cards: [provider/status | title | latest message | status/time]
       [same existing ChatCard grid as thread browsing]
List:  provider | title / latest message / status/time
       [same existing ChatRow, with native swipe actions]
```

Activity uses the existing shared card/list preference, keeps its current waiting-first/working/new filtering and reply deduplication, searches within Activity, opens the same detail pane, and retains pressure, stale/error/Retry, nested work requests and dismissal/rename/archive/delete behavior. Cards expose the existing Activity management commands through their context menu and accessibility actions; list rows retain native left/right swipes. This matches the normal card/list affordances. Activity does not return to other browsing tabs. No new sort or data model, read-state changes, task changes, connector/source review or real installation.

## Success criteria and tasks

- [x] A1 Reuse thread card/list components with Activity status and expose the existing layout choice. Acceptance: titles/latest messages visible, both modes show the same Activity entries, stale status honest, native list swipes and card menus operate on the intended session.
- [ ] A2 Add focused UI coverage and inspect iPhone/Duo captures in both modes. Acceptance: layout switch, navigation/back, dismissal, management, nested requests and error recovery covered; no source or agent calls in fixtures. Run scripts/test-mobile-activity.sh and the required broad attempt, disclose failures.
- [x] A3 Commit/push scoped changes, install the affected Dev phone app directly when reachable; retain the unchanged Mac Dev service. Acceptance: installed/runtime health and phone installation reported separately, fresh inspected simulator proofs saved. Real shipment awaits a new Ship instruction; TestFlight only on request.

## Verification, delivery and rollback

Use scripts/tests-for.sh --why for changed files; focused scripts/test-mobile-home-nav.sh iphone/duo selectors for Activity layout/navigation/dismissal/management/rename/error, plus scripts/test-mobile-activity.sh. Run scripts/tests-for.sh --run --all once before final reporting and disclose the known unrelated chat-switch/chat-rendering baseline blockers rather than claiming a green suite. Build/simulator locks and fixed derived-data folders apply. New files are docs only; no source/project regeneration required.

Deliver code/tests and inspected PNGs committed and pushed; Dev install verified, issue open pending remaining validation/acceptance. No stored-data migration: roll back only scoped commits and reinstall Dev with compatible General support, preserving current data/preferences. No silent preference reset. Existing scores, automation migration, source inventory and unrelated work are untouched.

## Work preparation

Scope and now: Shelby's direct request to use existing full thread card/list views in Activity supplies the requested outcome and implementation authority. Mode: linear, because two shared mobile files and their UI tests overlap; no agents. Model: current session, exact model/effort unavailable. Readiness: pass R1–R13, with before/target/incumbent visuals above and no blocking questions. Tracking: https://github.com/shelbyklein/chatterbox/issues/55


First verification pass: iPhone 17 Pro / iOS 26.2 passed Activity layout switching/navigation/dismissal (36.6s), dedicated dismissal/persistence (54.4s), management confirmation/error handling (42.8s), and offline/Retry recovery (18.7s). Duo passed tab navigation (34.2s) and full card/list switching/dismissal (43.5s). Engine activity checks pass. Fresh card/list captures on both devices and the iPhone error/swipe captures were inspected under design/activity-thread-layouts/. No layout defects observed. Two targeted rename/nested-family checks are running to cover shared renderer use outside Activity and front-thread requests.

Broad attempt: scripts/tests-for.sh --run --all started. The known chat-switch policy gate was checked out of order and reproduced exit 133 at unchanged Coordinator.swift:11 (old fade expectation). Stopped the remaining broad run safely after its initial script pass; remaining full coverage is incomplete, not green. Logs: build/activity-thread-layouts-full-suite.log and activity-thread-layouts-baseline-gate.log.

Platform scope: product changes are only in Core/ChatterboxMobile, so no Mac app rebuild or service restart is needed. Direct Dev phone install is the delivery target; real app/phone remain unchanged until Ship.


Final focused results: two additional iPhone scenarios pass: nested project/work-thread families including requests in Activity (30.4s), and rename in Activity/browser/session menu (41.1s). Eight focused UI scenarios pass in total, plus the Activity engine checks. No agent or connector call was triggered by these fixtures.

Delivery: Core ca6880a and parent d46b952 pushed. Direct Dev install succeeded on Shelby's Duo. Verified bundle com.shelbyklein.Chatterbox.mobile.dev, Dev flavor and no widget. Launch is not verified: iOS explicitly denied it because the device is locked; no unlock or further launch attempts were made. Unlock/open Chatterbox Dev manually. The existing Mac Dev service is ready with General support, unchanged; no Mac rebuild/restart, real app installation, source review or TestFlight upload was needed. Proof: build/activity-thread-layouts-dev-proof.json.

A2 stays open for incomplete broad validation (known unrelated chat-switch baseline gate); this is not a green full-suite claim. UI/source delivery and simulator inspection are complete, while physical UI acceptance awaits opening the installed Dev app. Real shipment remains gated on a new Ship instruction.

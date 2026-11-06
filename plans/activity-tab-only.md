<!-- activity-tab-only-2026-11-06 -->
# Keep Activity in its own tab

The phone now has a dedicated Activity tab, but Projects, Studios and list layouts still repeat the Activity panel above their content. Remove these embedded panels so each browsing view starts with its own content. Preserve the dedicated Activity destination and its working/new reply lists, search, dismissals, pressure display, history and chat-opening behavior.

Evidence: Core/ChatterboxMobile/ChatListView.swift uses MobileNewReplies in activityPage (dedicated: true), chatCards, studioWorkspace and chatList. Only the last three are removed. Existing tests/mobile-home-nav/HomeNavTests.swift assertions expect Activity in browsing views and need to move to the dedicated tab. Shelby supplied the current phone screenshot.

Visuals: [current phone](assets/activity-tab-only/before.png), [target layout schematic](assets/activity-tab-only/after.svg). Target flow: Projects / Studios / Chats → browsing content; Activity tab → activity list → same chat detail pane.

## Success criteria

1. Projects and Studios, including their card and list modes, contain no embedded Activity header or rows; verify focused simulator UI assertions and fresh inspected screenshots.
2. Activity tab retains working/new reply content, Mac pressure, dismissals, search and chat navigation; verify existing Activity scenarios migrated to the dedicated tab.
3. Activity stays responsive when a connection error appears; stale working labels and Retry recover to live state in testConnectionErrorIsHonest.
4. No changes to task/source data, reply unread state, pins, project/studio cards, navigation rail or Mac UI; check scoped diff and navigation regression tests.

## Workflow and deliverables

- [x] T1 Remove only the three embedded MobileNewReplies call sites; keep dedicated activityPage. Update Activity-related navigation expectations. Acceptance: focused test-mobile-home-nav scenarios pass and dedicated Activity tests pass.
- [ ] T2 Build and capture iPhone and Duo simulator Projects/Studios and Activity views through test harnesses; inspect that browsing content begins below the heading and Activity works in its tab. Acceptance: new screenshots saved under design/activity-tab-only/ and inspected, no overlapping or orphan spacing.
- [ ] T3 Run scripts/tests-for.sh --run for affected files, then the required full suite once. The preceding Desk full-suite attempt stopped after reaching chat-switch-perf; it recorded a chat-rendering assertion failure (No manual report). Record that partial coverage, run the full suite once for this work without overlapping full runs, and disclose failures and mixed-tree coverage. Commit/push scoped Core and parent changes. Install Dev with normal service restart; upload/distribute updated iOS build to the existing internal TestFlight group per standing delivery rules. Acceptance: committed/pushed source, installed Dev, service health and TestFlight processing/tester availability reported separately. Real Mac shipment awaits Ship.

Execution mode: linear, one small shared mobile layout file and its UI expectations. Model: current session; exact model/effort unavailable. No agents or work threads.

Boundaries: phone navigation cleanup only. No Mac redesign, Activity feature removal, saved-state reset, task cleanup, automation changes or production Mac installation. Preserve unrelated general-automations plans and other sessions' changes.

Test plan: inspect scripts/test-mobile-home-nav.sh and its selector options; run focused browsing/Activity cases on iPhone and Duo through shared build/simulator locks. Run scripts/test-mobile-activity.sh and scripts/tests-for.sh --run for changed files; reconcile the existing full run as above. Use permitted persistent build folders only. Before implementation read mobilebuildmcp-cli and Impeccable craft-floor/native guidance. No source files are added, so project regeneration is not expected.

Rollback: no data/schema migration. Revert only the scoped commits and reinstall Dev; keep its pre-install desk.json backup and do not overwrite newer task data. Existing TestFlight builds remain available; redistribute the previous build if needed without expanding tester access.

Open questions: none blocking. The screenshot and explicit request settle the removal; the dedicated tab is retained.

Tracking: https://github.com/shelbyklein/chatterbox/issues/52

## Work preparation

Scope: confirmed by Shelby's explicit request to remove Activity from other views now that it has its own tab. Mode: linear. Models: current session; exact model/effort unavailable. Recipient: this session. Now/later: now, explicitly authorized by Shelby. T1 complete; T2 and T3 in progress. Readiness: pass, 2026-11-06, R1–R13 covered by this document and linked before/after assets. Product change committed and pushed; remaining device verification and delivery pending.

Verification progress: Activity engine checks pass. First iPhone run passed dismissal, management and Activity-only browsing checks. Its saved-Pinned navigation test failed while retaining a launch-time tab override; corrected the test to relaunch without that override before switching tabs. Stopped its subsequent busy connection fixture through safe_stop; no app/service hosts were stopped. Corrected test build passes; simulator run is queued under Mac pressure limits. Superseded queued Duo run was stopped before launch, to rebuild with the corrected tests. TestFlight Shelby group verified internal with automatic distribution enabled.

Current results: Core 1b6f8bb pushed. Nine focused iPhone scenarios passed across the runs (Activity-only browsing, saved-Pinned migration/navigation and pin preservation, card/list navigation, Studio thumbnails/list switching, pressure, work-thread nesting, rename, dismissal and management swipes). Test setup now explicitly selects Chats scope and switches card/list modes through the visible menus; inherited preferences and launch overrides caused the intermediate fixture failures. Fresh iPhone proofs saved and inspected under design/activity-tab-only/. Duo test build succeeds; its run is queued by the overload guard. Isolated connection-state test is queued separately. No Dev install or TestFlight upload yet for this change.

Duo: both focused tests pass (Activity-only card/list browsing plus Activity navigation/migration/pins). Duo Projects list, Studios list and dedicated Activity screenshots inspected. A clean card capture is being repeated because a successful already-selected menu path left the menu open in its screenshot; the fixture helper now dismisses outside the menu. Isolated connection-state coverage remains pending behind resource limits. Dev installation and TestFlight upload scripts started with the normal pressure guards; no success claimed yet.

Scope refinement within the selected Activity destination: the isolated offline scenario reproduced a live table-measurement loop (100 percent main-thread CPU; sample in build/activity-tab-only-connection-sample.txt shows MobileActivityRows.sizeThatFits repeatedly laying out its own UITableView). Stabilize row measurement without mutating the live table during SwiftUI sizing; keep native swipes, single-line rows and Dynamic Type. The error-state test is the regression check. Paused only this task's queued Dev/TestFlight scripts and stopped its stuck fixture runner with safe_stop before editing; no installed app/service was stopped. This is required reliability for the retained destination; no user-visible feature expansion or new decision. Readiness rechecked: pass, existing linear mode and authorized scope retained.

Measurement regression result: Core a58ea21 pushed. testActivityDismissalSwipes passes (54s) and testConnectionErrorIsHonest passes (22s), including stale labels, visible Retry and recovery to live status. Fresh error-state screenshot inspected at design/activity-tab-only/iphone-connection-error.png. Dev and TestFlight scripts restarted for this verified revision; both currently wait under the overload guard.

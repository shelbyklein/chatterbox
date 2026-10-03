# Preserve mobile reading position (#7)
Mobile chats now condition following on a bottom marker, but queued layout-settling scroll calls still execute after the reader scrolls away. The marker uses lazy-row appearance, which can also mean prefetched rather than visible. Replace that approximation with viewport geometry and make reader interaction cancel queued scroll work.

Issue: https://github.com/shelbyklein/chatterbox/issues/7
Tracker plan: 1556650C-AF53-4F90-A173-06C66CD410C2
Baseline: 5d0cff5; ChatDetailView revision observer, bottom onAppear/onDisappear and pin delayed closures are current evidence.
[Following/reading flow](assets/mobile-scroll/flow.mmd)

## Success and deliverables
1. Above-bottom reading survives streamed revisions and question/settings changes (real swipe UI tests on iPhone/iPad simulator).
2. A user drag invalidates delayed scroll callbacks and a near-bottom marker is measured geometrically (policy and UI regressions).
3. Opening, delayed first loading, sends and explicit jump still settle reliably at newest; jump button remains accessible (policy and UI checks).
Ship scoped code, plan and regression tests committed/pushed; signed mobile app installed on reachable authorized iPhone/iPad. Mac protocol stays unchanged, no Mac restart needed. Report actual install/launch results. Issue remains open until final verified acceptance and authorized closure; progress may update issue checklist/comment as implementation work now requested.

## Tasks (issue acceptance criteria)
| ID | Acceptance |
|---|---|
| CB7-1 | Follow updates only when already near the bottom, on initial load, or when the user explicitly sends/jumps. |
| CB7-2 | Keep position stable while inspecting older content. |
| CB7-3 | Show a jump-to-latest affordance for new content. |
| CB7-4 | Verify long streaming replies on iPhone/iPad and preservation of position through question/settings updates. |

## Design and checks
Use a small observable follow policy with callback generation, user-interaction latch and force-vs-layout pin requests. Vertical transcript drag cancels pending work immediately. Measure bottom marker relative to the actual scroll viewport, using a small near-bottom tolerance. Layout changes do not force older readers down; deliberate send/jump/open does. Initial late loading follows unless there was actual loaded-history reading. Preserve newest-on-open and the jump button.
Run `scripts/test-mobile-scroll.sh iphone` and `scripts/test-mobile-scroll.sh ipad`: policy checks and real swipes/taps against an isolated streaming long-chat server, then check anchor frames through revisions and jump action. Run the signed iOS build, existing composer tests if shared send paths change, and inspect saved screenshots. No paid agent requests. Record a before-run when practical; don't change live transcripts.

## Boundaries / rollback / preparation
No transcript deletion, text dedupe, account/model/access changes, Mac restart, or unrelated worktree edits. Roll back scoped commit and reinstall prior mobile package; no stored-data/schema migration. No blocking questions. Shelby requested #7 now; standing commit/push/mobile install authorization applies. Linear, gpt-6.1-sol / medium (verified session runtime): tightly coupled mobile behavior and tests. R1–R13 pass, 2026-10-02; task IDs match issue acceptance. Tracker progress is required by supplied workspace instructions.

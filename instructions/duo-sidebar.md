# Persistent Duo sidebar

Chatterbox keeps sessions beside the conversation while the Duo is open. Partly folded around a vertical hinge, the sidebar fills the left screen and the conversation fills the right. Shelby confirmed the previous flat-screen width is fine; its sizing formula stays unchanged.

The first device builds exposed two additional problems: keyboard-reduced height could select phone navigation, and sidebar content stopped before its pane edge. UIKit's division frame also includes interactive margins, which the first implementation incorrectly left as a blank strip. Current device evidence: [folded](</Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/12A571E2-E611-4753-B728-59651798F6B9/Photo.jpeg>) and [flat](</Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/13DA0945-2029-415C-B84D-76769C8E4E10/Photo.jpeg>). [Target sketch](../design/duo-sidebar/target.svg).

## Work preparation

Tracking: `local:instructions/duo-sidebar.md`; no GitHub issue created or closed. User confirmed this is for Chatterbox and requested implementation. Readiness passes R1–R13 for this scoped layout correction. Linear: source, UI checks, and delivery depend on each other; current session, exact model/effort unavailable. No blocking implementation decisions. Device acceptance remains pending and is not inferred from silence.

Deliverables: scoped mobile source, native regression tests and inspected captures, device install, existing internal TestFlight delivery, and this plan, committed/pushed. Preserve history ownership, selection/drafts, pins, data, Mac Screen, ordinary phone navigation, and the flat sidebar width. Horizontal folds retain normal side-by-side navigation. No Mac install, daemon restart, host interruption, tester expansion, or public release.

## Success criteria

1. Open-screen session selection and archive keep the sidebar visible; archive clears the conversation (native UI tests).
2. A vertical fold sizes panes to the physical hinge without treating its touch margins as a blank strip (native asymmetric division fixture; physical device acceptance separately).
3. Keyboard/obscured height does not select phone navigation or lose the draft (native short-viewport fixture plus actual software keyboard).
4. Search content stays within and fills its sidebar pane; the outer camera/rail inset is not repeated at its internal edge (native containment check; actual Duo camera behavior separately).
5. Closed Duo navigation still opens full-screen and returns to the same list after archive; verified source is pushed, installed and available to existing internal testers.

## Work checklist

- [x] D1 Replace collapsible wide navigation with persistent panes and read the active vertical division.
- [x] D2 Run focused tablet/phone checks, inspect captures, and check source integration.
- [x] D3 Commit/push Core and root, install on Duo, upload and verify TestFlight availability, report tidy without applying cleanup.
- [x] D4 Base tablet eligibility on actual UIWindow bounds rather than keyboard-reduced GeometryReader height; preserve keyboard avoidance and draft. Reinstall corrected source.
- [x] D5 Ignore the sidebar's container trailing inset at its internal edge; remove the division region's documented interactive margins before reserving hinge space. Run containment, fold-margin, keyboard and closed-Duo regressions and install.
- [ ] D6 Physical review: confirm the latest install fills the left screen when folded and keeps the usual width when flat, without the internal gap. An optional device-feedback question is pending. Simulator results do not close this check.

## Implementation

- Core `ChatListView.swift`: wide views use two persistent navigation stacks; closed phones retain the existing split-view navigation. The sidebar ignores the container's trailing safe area at its internal edge; the detail retains its outer camera/rail clearance. The active division probe removes `UIView.ReservedRegion.margins` from its frame, following the local UIKit SDK contract that the frame includes these margins.
- `ChatterboxMobileApp.swift`: a window-size probe keeps tablet eligibility independent of keyboard height while respecting closed phones and narrow iPad windows. Content still avoids the keyboard.
- DEBUG-only fixtures simulate compact traits, reduced usable height, outer trailing occlusion, and an asymmetric hinge with interactive margins. Release builds use real window and UIKit division data.

No source files were added; `scripts/check-sources.sh` passes without project regeneration. No stored data or schemas change. Rollback: revert the scoped source commits, rebuild, and reinstall; Git retains the prior implementation.

## Verification

Current Core implementation: `7aa2ecb`; root integration: `74623ea` (both pushed).

| Check | Result / evidence |
| --- | --- |
| Fold sizing with 40-point interactive margins on each side | Pass, `build/duo-insets-after.log`; asymmetric 68% hinge fixture checks exact physical gap and width beyond the old cap |
| Keyboard / shortened viewport | Pass, same log; both panes remain, width unchanged, draft preserved with actual software keyboard |
| Internal search bounds under outer safe area | Pass, same log; search remains inside its pane and within 36 points of its edge |
| Closed Duo navigation and archive | Pass, `build/duo-insets-closed.log`; iOS 27.1 |
| Source integration / scoped diffs | `scripts/check-sources.sh`, `git diff --check`, Core diff check pass |

Four targeted checks pass on the latest source. The earlier flat-open and tablet archive checks also passed before the final inset adjustment. No clean full-suite claim: the unrelated New Chat test remains unresolved on the Duo's system rail and was left unchanged.

Inspected native simulator evidence: [content bounds](../design/duo-sidebar/content-insets.png), [keyboard](../design/duo-sidebar/keyboard.png), [fold margins](../design/duo-sidebar/fold-margins.png). The 68% fold is deliberately asymmetric to catch hard-coded equal splits; it is not the real Duo's geometry.

Evidence limits: the shortened-viewport test fails on the previous root sizing code (`build/duo-keyboard-before.log`), establishing the keyboard bug. Xcode stalled after recording that failure; only that run's verified xcodebuild was stopped through `safe_stop`, and the fixture cleaned up. The generic outer-safe-area test also passed before the inset correction (`build/duo-insets-before.log`), so it does not reproduce the Duo-specific camera behavior. Physical bending and landscape transitions cannot be established by this simulator. The user's device screenshots remain the reference for D6.

## Delivery

The latest Release app installed and opened on Shelby's Duo (`build/duo-insets-install.log`). TestFlight **202610261618** uploaded successfully (`build/duo-insets-testflight.log`); Apple reports **VALID / IN_BETA_TESTING**; the build is explicitly listed in the existing **Shelby** internal group (which retains access to all builds). Verified in `build/duo-insets-tester-availability.json`. It supersedes 202610261556 and 202610261608, which reached VALID / IN_BETA_TESTING but precede the final inset correction.

Latest tidy report: **56 removable, 0 kept** (`build/duo-insets-tidy.log`). No cleanup applied. No scratch worktree/clone created. Tests clean their own disposable simulators and app bundles.

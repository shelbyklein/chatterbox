<!-- compact-card-header-2026-11-08 -->
# Compact iOS text-card headers

The Projects screenshot shows a provider icon in a separate row above each card title, spending vertical space before the text starts. Move the icon to the top right and start title/preview at the top left. Apply to the shared text cards used by Projects, Chats and Activity/Recent; retain Studio image cards, status semantics, cards/list behavior, nested thread actions and sizing.

## Work preparation

Direct user instruction authorizes implementation now. Baseline parent47f4551, Core348dfbc; both checkouts clean. Linear, one shared SwiftUI header; current session, exact model/effort unavailable. R1-R13 pass. No blocking questions. Tracking: [issue69](https://github.com/shelbyklein/chatterbox/issues/69). Dev phone delivery has standing approval; real shipment and issue closure require Shelby.

[Current screenshot](../design/compact-card-header/before.png). Target, using the existing native font, spacing, color and card surface:

```text
[ Title begins here        status · provider ]
[ Preview begins here                       ]
```

## Success and deliverables

1. Titles begin at the upper left of text cards; the model/provider or branch icon sits at the upper right on the same header row, with visible waiting/working/new-reply status. Native screenshots verify compact and long titles without overlap.
2. Existing project-family nesting, card navigation and Activity/Recent card/list flows pass their focused native tests. No data, provider setting, navigation, thumbnail or non-card row changes.
3. Code, plan and inspected native captures committed/pushed Core-first; signed Dev phone build installed directly on Shelby’s Duo. Report actual install/launch separately; no Mac install or TestFlight. Real Ship remains pending.

## Tasks

- [x] CH1 Move the shared text-card header icon to the trailing side of the title, retaining status and branch icon behavior. Acceptance: native Projects and Activity/Recent card captures place content correctly, nested and list navigation still work.
- [x] CH2 Run focused native checks, inspect once (one optional batched correction/confirmation maximum), commit/push and install phone Dev. Record evidence and keep issue open pending Ship and acceptance.

## Verification and rollback

Use `scripts/tests-for.sh --why --since 47f4551`, then `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testProjectsNestWorkThreads,HomeNavTests/HomeNavTests/testActivityThreadLayouts,HomeNavTests/HomeNavTests/testActivityRecentThreads MOBILE_TEST_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-2 scripts/test-mobile-home-nav.sh iphone`. Preserve those native flow checks; no new test mirroring layout implementation. Xcode target membership is unchanged, so regeneration is not needed. Check parent/Core diff whitespace. Install with `scripts/install-phone.sh --dev "Shelby's Duo"`. Rollback: revert the header commit and reinstall Dev with the same script; no stored data changes or migration/backup needed. Exclusions: Studio image cards, list rows, Desk, widget, Mac, service/configuration and real delivery. Full release checks deferred to Ship; known baseline chat-switch failure remains recorded. Open questions: none.

## Validation progress

Coree0c601a implements the header. Native iPhone17Pro/iOS26.2 Activity/Recent tests passed in `build/mobile-home-nav.2FayYi`; Projects nesting, list/cards, thread open and Show-more/less passed in `build/mobile-home-nav.86R85d`. The pre-existing list hit-frame gap assertion was reproduced against unchanged Core348dfbc, then corrected to test non-overlapping tap targets; native screenshots verify the visible gap. [Evidence](../design/compact-card-header/validation.md). Source and whitespace checks passed. CH2 complete: signed Dev build installed and opened directly on Shelby’s Duo. [Delivery record](../design/compact-card-header/dev-delivery.json). Physical-user acceptance and real Ship remain pending.

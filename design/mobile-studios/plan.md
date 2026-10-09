# Mobile Studios redesign

local: design/mobile-studios/plan.md

The iOS Studios page currently stacks all Studios and text-heavy cards beneath five toolbar controls. Make it an image-led workspace with a compact activity entry, horizontal Studio selection, and readable status on each card. Shelby approved the imagegen concept and implementation on October 9, 2026.

Current evidence: `Core/ChatterboxMobile/ChatListView.swift` (`chatCards`, `ChatCard`, toolbar).
[Before](assets/before.jpeg) · [Approved concept](assets/concept.png)

## Scope
Studio page only: new gallery by default, one selected Studio, search spans Studios, menu retains connection/notifications/sort/list controls. Retain list mode, chat open/back, archive, instructions, group pins and all chats (no arbitrary 12-chat cap). Latest thumbnails lead gallery cards, with graceful text-only fallback. Combined activity continues using existing phone-local unread tracking and live running state. Status uses Waiting on you / Working / New reply / relative date. No schema, server, model, or encryption changes. A later user instruction adds one Mac sidebar change: pinned sessions remain rows in card mode; unpinned cards and pin membership stay unchanged. Imaginary concept artwork is replaced by real thumbnails.

## Success criteria
1. Simulator Studios opens with a two-column gallery; thumbnails lead cards, and no-image sessions remain readable.
2. Studio selector switches groups; search finds chats across Studio groups. Real open/back navigation succeeds.
3. Compact activity opens a reply/running chat; card states use provider-colored running indicators and unread/waiting labels.
4. Project cards remain text-only; existing navigation regression passes.

## Workflow and deliverables
- [x] T0 Mac pinned rows in card mode. Acceptance: existing sidebar render inspected and build passes.
- [x] T1 Implement Studio page, compact activity, gallery cards. Acceptance: simulator build passes.
- [x] T2 Extend isolated fixture and navigation tests, inspect screenshots from Studios with/without thumbnails, switch/search/open. Acceptance: `scripts/test-mobile-home-nav.sh iphone` passes, captured renders inspected.
- [x] T3 Commit/push Core and root, upload Release via `scripts/testflight.sh`. Acceptance: upload receipt; Apple processing/compliance verification when available. Phone install acceptance remains user-side.

Deliverables: Core UI committed/pushed, local plan and screenshot evidence committed/pushed, Release uploaded to existing Shelby automatic internal group. No App Store release.
Rollback: no stored-data change; revert scoped commits and upload a new build. Existing TestFlight build remains selectable until expiry; keep current upload receipt in docs.

## Work preparation
Scope and now decision: confirmed by 'sure go for it'. Linear: the changes share one view and its test, so sequential implementation is appropriate. Executor: current session; exact model/effort unavailable. R1–R13 pass; R7 local checklist, no GitHub issue mutations. No blocking open questions. TestFlight delivery follows the established upload workflow; no Mac restart required.

## Verification

- Full `scripts/test-mobile-home-nav.sh iphone`: 3 tests passed, including existing project card/navigation regression.
- Final `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testStudioCardThumbnails scripts/test-mobile-home-nav.sh iphone`: passed thumbnail/no-image fallback, cross-Studio search, close search, switch Studio, open/back, and list mode. An intermediate test used iOS's old Cancel label; corrected it to use the observed Close button.
- Final Mac build and `scripts/test-studio-chat-sidebar.sh`: passed. Native fixture screenshot inspected: rows remain rows with card mode selected and selected row remains readable.
- [Phone gallery](assets/studio-card-thumbnails.png), [search](assets/studio-search.png), [other Studio](assets/studio-switched.png), [list mode](assets/studio-list.png), [Mac pins](assets/pinned-rows.png). Phone fixture uses a gradient thumbnail, not real customer artwork.
- Mac installation approval requested under AGENTS.md; iOS upload next.

## Delivery

Core `97f7953`, root implementation `68ff7c9` pushed. Release build **1.0 (202610091050)** uploaded successfully; Apple completed processing and its current-build encryption declaration was saved. The Shelby automatic internal group now lists this build as **Testing**: [delivery evidence](assets/testflight-ready.jpg). New build phone installation and user acceptance are not claimed. Mac pin-row change is built and pushed, awaiting install approval; no app or service restart occurred.


## Follow-up: Activity remains a list
The Studio gallery introduced cards for the Activity section. Shelby requests reply and working entries remain list rows on iOS, independent of gallery mode. Current evidence is the compact branch in `MobileNewReplies.swift` and [gallery render](assets/studio-card-thumbnails.png); target is the existing row layout shown in [list render](assets/studio-list.png).

Scope: restore the shared list presentation for Activity; retain collapsibility, three unseen replies, running chats and open-chat actions. Studio gallery cards, Activity timeline tab and stored unread state stay unchanged. No open questions.
- [x] A1 Remove Activity card variant. Acceptance: Studios Activity rows span width and stack vertically in simulator.
- [x] A2 Verify Studio navigation and inspect fresh screenshot. Acceptance: targeted home-navigation UI test passes.
- [x] A3 Commit and push scoped change. TestFlight activation is a separate delivery step.
Success: Studio gallery still has thumbnails, while Activity is a list with working and unseen reply links. Deliverables: Core UI, test and evidence committed/pushed. Test: `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testStudioCardThumbnails scripts/test-mobile-home-nav.sh iphone`. Rollback: revert scoped commits; no data change. Work preparation: scope authorized by direct correction; linear for one shared component, current session; exact model/effort unavailable. R1–R13 pass (R12 n/a for source-only delivery). Local checklist only; no GitHub issue mutation.

Follow-up verification: targeted simulator test passed after correcting the test lookup for combined iOS accessibility labels. [Fresh inspected Activity list](assets/activity-list.png) shows full-width rows above gallery cards. Release 202610091257 uploaded and verified Testing in Shelby internal group. Core/root committed and pushed for delivery. Tidy report only: 5 removable, 2 kept; no cleanup applied. Mac pin-row installation succeeded earlier.

Sidequest investigation: Mac breadcrumbs logged unsupported_operation twice at 12:56. Running chatterboxd PID 1764 started October 8 at 16:39, before daemon Sidequest handler commit d0350b4 at October 9 00:50. Installed binary includes sidequest/invalid_sidequest. Idle restart queued through scripts/restart-service.sh, hosted by launchctl job com.shelbyklein.chatterbox.idle-restart; log confirms waiting at 12:58:38. No replies interrupted; retry Sidequest after restart.

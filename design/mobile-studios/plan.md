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
- [ ] T3 Commit/push Core and root, upload Release via `scripts/testflight.sh`. Acceptance: upload receipt; Apple processing/compliance verification when available. Phone install acceptance remains user-side.

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

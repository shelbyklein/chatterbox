# iPad catch-up — 2026-10-19

Status: implementation authorized by Shelby's request; linear execution in the current Codex session (model/effort not exposed). Local tracking preserves the request not to change GitHub issues.

## Outcome and scope

Bring the available iPad up to the current universal iOS app and make its existing split view usable. Keep pairing, drafts, session history, the four tabs, and the phone's layout. Deliver a verified development install to Shelby's iPad mini and the new build through the existing Shelby internal TestFlight group.

Already shared with iPhone: Usage, optional session naming, rename, promotion to projects/Studios, collapsed next steps, Studio thumbnails, last-provider icons, working spinners, Activity working-first ordering and swipe actions, sidequests, widgets and push registration. Verify these using the existing isolated companion fixture. Desktop-only features such as the session tool rail and Mac-local pinned-thread preferences are outside this catch-up; do not invent mobile APIs for them.

Baseline: device has a developer build numbered 1; Apple reports 202610191136 VALID / IN_BETA_TESTING. Build 1 does not identify its source revision. The current iPad simulator shows two cramped cards in a 280-point sidebar, truncated Activity names, and no explanatory first-load progress. Screenshot: [before](before.png).

## Target layout

```text
Projects | Studios | Chats | All
┌ Sidebar: 320–460 pt ────┬ Session ──────────────────────┐
│ Search / page controls  │ Stable conversation + tools  │
│ Refresh/cache feedback  │                              │
│ Activity (working first)│                              │
│  Provider · parent ↗    │                              │
│  sidequest task         │                              │
│ Adaptive session cards │                              │
│ (one when narrow)       │                              │
└─────────────────────────┴──────────────────────────────┘
```

Keep controls reachable in the tablet split view; landscape needs a separate device check if simulator rotation cannot render it. Activity remains a list. Use the existing provider styling and native navigation, no new visual system or external dependency. Empty first load explains that it is connecting; cached results identify themselves while a refresh is pending or failed. Successful idle refreshes do not flash banners.

## Checklist / acceptance

Success criteria: (1) iPad cards remain readable and the open conversation stays beside the sidebar in portrait, proven by simulator screenshots and frame assertions, with landscape checked when the simulator can render rotation; (2) sidequests name their parent and first-load/cache feedback appears before delayed network results, proven by isolated UI tests; (3) existing mobile management, Usage and naming flows pass on iPad and relevant shared flows pass on iPhone; (4) scoped code/docs are committed and pushed, the universal app is installed on the iPad and the new internal TestFlight build is available, verified using device and Apple APIs. No blocking open questions.

Tracking: `local:design/ipad-catch-up/plan.md`. One executor owns all tasks in dependency order because the shared views and their tests overlap. Before replacing the installed app, keep its data container in place; existing TestFlight builds remain the binary rollback. Gates: routine installation and existing internal distribution are standing-approved in AGENTS.md; no service interruption or new audience is authorized.

- [x] P1 Audit current source, Apple build state, installed iPad and baseline UI.
- [x] P2 Adapt sidebar/card width to iPad; retain iPhone two-column cards.
- [x] P3 Identify Activity sidequests using their source and icon; keep ordinary Activity labels and gestures.
- [x] P4 Expose initial/cached load feedback; coalesce overlapping list refreshes and preserve cached data on failure.
- [x] P5 Exercise iPad portrait/landscape, split navigation, Studio thumbnails, Usage, names, rename and promotion; check phone regressions where shared behavior changes.
- [x] P6 Commit/push scoped Core and app changes; source check, signed universal device build.
- [ ] P7 Install to the reachable iPad without erasing data; upload and verify existing internal TestFlight availability.
- [ ] P8 Save proof, record exact delivery status, run tidy report (no unapproved deletion).

Verification: `scripts/test-mobile-home-nav.sh ipad` with focused tablet tests, existing relevant management/Usage/new-session tests; focused iPhone Activity/Studio regression; `scripts/check-sources.sh`; universal signed iOS device build; live devicectl installed-version query; Apple processing and beta-state query. Use canonical build directories and isolated test data. Do not interrupt other replies or restart unrelated services.

Rollback: revert only this task's commits and reinstall the previous universal build; previous TestFlight builds remain available. No schema migration, pairing reset, new tester access, new public endpoints or security changes. Keep unrelated concurrent edits out of commits. If signing or device connectivity blocks a delivery step, record the precise achieved status and continue other verification.

## Work preparation

Readiness: pass · 2026-10-19. R1 summary, R2 observed problem, R3 baseline and target sketch, R4 four verified outcomes, R5 committed code/docs plus installed and distributed builds, R6 ordered task checks, R7 local checklist, R8 linear execution, R9 current session exact model/effort unavailable, R10 exclusions/data preservation, R11 no blocking questions, R12 retained data and previous binary rollback, R13 concrete suites and rendered-state checks. All pass; no new dependencies or sensitive access.

## Verification log

- iPad mini (A17 Pro), iOS 26.2 simulator: split navigation, adaptive Studio card width and thumbnail, sidequest parent/task, rename and Studio promotion passed (`testIPadCatchUp`, 47.3 s). Usage (13.9 s) and optional new-session naming (21.9 s) passed.
- Delayed first-load and cached relaunch passed (`testListRefreshFeedback`, 17.7 s). The unsigned fixture needs an explicit DEBUG-only synthetic token to retain paired state across relaunch; device pairing still uses Keychain.
- Signed universal iOS Debug build passed (family 1,2). Source consistency and whitespace checks passed.
- Landscape remains unverified: orientation requests were acknowledged, but two captured screens stayed 744 × 1133 in the simulator. The October 10 delivery notes record the same simulator behavior. A visible Simulator retry then failed to open the fixture transcript. No orientation workaround was added to production, and the experimental failing rotation test was removed. Portrait split-view interaction is verified; landscape acceptance is not claimed.
- Proof images use isolated sample chats, thumbnails and usage values; they contain no live conversation data.

- iPhone 17 Pro, iOS 26.2: Activity dismissal/swipe actions (43.3 s), delayed first-load/cached relaunch (19.2 s), Studio thumbnails/navigation/brief (71.9 s) all passed. Core implementation committed as `1f32175`.

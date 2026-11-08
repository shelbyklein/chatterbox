<!-- activity-widget-only-2026-11-07 -->
# Keep the activity widget focused on chats

Remove usage from the existing Chatterbox activity widget now that Usage is a separate widget. Shelby's Home Screen screenshot still shows Claude/Codex quota rows below the working thread. Keep the activity widget's identity, chat links, attention/working priority, freshness and Lock Screen behavior; keep Usage and New Chat intact.

## Work preparation

Shelby's direct correction authorizes implementation now. Mode: linear, a small widget presentation/test change; current session, exact model/effort unavailable. Baseline parent e3ab4cf, Core e56b645. Readiness R1-R13 pass. Tracking: [issue 66](https://github.com/shelbyklein/chatterbox/issues/66). No blocking questions. Dev delivery has standing approval; real installation awaits a new Ship.

Current native activity layout: [before](../design/widget-usage-bars/usage-medium.png). Target:

```text
1 working
… Working Playcase Arcade

(no usage section; quotas are in Usage)
```

Success: native small/medium/large activity renders never show usage text, bars or quota link, including empty, stale and one-working states. Existing chat entry links, priority and freshness remain; dedicated Usage still shows all accounts and New Chat still has both shortcuts. Verify with scripts/test-widget.sh and inspected native screenshots. No new target sources or project generation expected.

## Tasks

- [x] A1 Remove the activity footer and its unused presentation helpers; update gallery description. Acceptance: activity code has no usage section, shared data and dedicated widgets unchanged.
- [x] A2 Update native activity checks and verify all widget kinds. Acceptance: scripts/tests-for.sh --why selects test-widget.sh; scripts/test-widget.sh passes activity sizes/states, dedicated Usage and New Chat. Inspect one native batch, fix findings together, confirm once at most.
- [x] A3 Commit/push Core then parent and deliver phone Dev. Acceptance: signed device extension built, actual Dev install result recorded, real Mac/config hashes unchanged. Physical widget activation awaits Ship; keep issue open.

Scope: presentation only; no model/usage source/cache, app routing, schedules, pairing, real service, activity ordering or row-capacity changes. Tests retain functional coverage of dedicated widgets while replacing obsolete footer expectations with activity-only assertions. Full release suite deferred to Ship, known chat-switch mismatch/incomplete coverage remains recorded. Rollback: revert these source commits and reinstall using repo scripts; no migration or user data deletion. Deliver source/tests/screenshots committed and pushed, phone Dev installed, real deployment pending Ship. Open questions: none.

## Real shipment — November 8

Shelby authorized “ship widget updates.” Activity-only (#66) and quick actions (#67) shipped together from parent `53eedfc`, Core `5d43157`. Direct Release install on Shelby’s Duo succeeded on the repo-script retry after a transient remote connection failure. Launch was denied because the phone is locked (CoreDevice10002/FBS Locked). Open Chatterbox once after unlocking; physical Home Screen appearance/interactivity remains awaiting acceptance. The embedded widget and app signatures, shared real app-group entitlements and non-opening provider App Intent metadata passed checks on the final installed artifacts. No Mac install/restart or TestFlight; real Mac app/service/host and Automations hashes unchanged.

Release run: **11 passed, 1 failed, 101 not run**. Same unchanged `test-chat-switch.sh` policy assertion at Coordinator.swift:11, exit133. Proceeded under Shelby’s existing explicit approval for that known failure and incomplete coverage. Full suite is not green. [Real delivery record](../design/quick-actions-widget/real-delivery.json). Keep issues open pending physical acceptance.

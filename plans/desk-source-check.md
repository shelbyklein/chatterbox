# Desk: check new and updated source information

Shelby, 2026-11-06: add a Desk button to check for new/updated information since the last pull. Linear execution here, no work threads. Optional scope question offered; absent a reply, assume both new source tasks and updates to existing cards, matching “new / updated”.

Use the existing configured ClickUp + Outlook morning-priorities routine, not a second scheduler or new integrations. Current installation has that explicit routine; its seven weekday entries form one routine. A missing/ambiguous routine must report setup needed, never run an unrelated automation. The configured routine's source/account limits remain in force.

Flow: Desk → Check for updates → one read-only source check runs → Desk remains open, shows Checking / Needs you and a link to the check → new tasks or source-status/link updates arrive through existing Desk operations. Repeated taps while running reuse its current run. No external writes, email sends, task completion, or column changes from the check.

“Since last pull” uses each source's last verified coverage checkpoint in the existing reports; last requested time is display metadata only, never a successful-coverage watermark. Partial/inaccessible checks report the gap and preserve the last verified checkpoint. De-duplicate against current Desk sources before adding tasks. Preserve verified source links and the approved confidence rubric.

- [x] Service state and UI-only start operation, reuse existing routine, guard duplicates and unsupported configuration, expose last-requested time accurately.
- [x] Mac and phone buttons, progress/needs-you state, Open check link; stay on Desk.
- [x] Behavioral tests with stand-in runs (no actual connector/model calls), Mac render and focused phone UI proof; commit/push and Dev delivery. Full-suite attempt from earlier requests is running; disclose final coverage, rerun checks affected by these edits, and report failures rather than claiming a green uniform-tree run.

No live pull is started during implementation. No changes to saved automation prompts, schedules, mailbox or ClickUp data. Real app updates only on Ship. Rollback by reverting scoped feature code; optional companion fields retain compatibility.

Validation: automation-routines 66 checks, Mac Desk 154 checks, Desk service/CLI 257 checks pass. Focused Duo testActivityTab (24s) and testDeskSourceCheck (10s) pass; actual screenshots inspected in design/desk-sources/ and design/mobile-activity/. No live source pull or connector run was made; external source coverage and account access remain unverified.

Delivery: Core dcc7bf0 / parent 30a4c0a pushed. Mac Dev installed/reopened; Dev service healthy after 1s at 13:44:38 local. No live source pull, physical-phone installation or TestFlight upload for this feature.

# Activity replaces the phone Pinned tab

Shelby, 2026-11-06: replace the circled Pinned destination in the iOS navigation rail with a dedicated Activity view. Execute linearly in this session; no work threads. Scoped refinement of the existing native tab and Activity rows, preserving the incumbent appearance. Ready from the explicit request and screenshot; no unresolved design decisions.

Flow: Activity tab → all working / needs-you sessions and unread replies → tap a row → conversation → Back to Activity. Open Duo retains the existing split conversation layout. Existing saved pins and pin/unpin commands remain intact; an older saved Pinned tab opens Activity after updating.

- [x] Replace the tab and icon, migrate its saved selection, and keep notification/session navigation working from Activity.
- [x] Reuse Activity row controls and live refresh, with all unread replies, search, status labels and an empty state. The compact Activity on other pages remains unchanged.
- [x] Focused Duo UI check passes: saved-tab migration, working/needs-you/unread rows, conversation opening/back, saved pin retained. Earlier iPhone Activity dismissal/swipe check passes. Actual simulator screenshots inspected; commit/push and Dev delivery tracked with the Desk check. Real app only on Ship.

Validation: focused iPhone UI test for the Activity tab, row opening/back, saved-tab migration, idle pinned items excluded and pin state preserved; existing Activity swipe tests. Full-suite attempt already in progress for earlier changes; report coverage and failures explicitly and rerun affected checks after this edit. No iPad runs. Rollback by reverting scoped tab/Activity changes; no stored pin data migration or deletion.

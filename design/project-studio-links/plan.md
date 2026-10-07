# One linked Studio per project

Shelby explicitly requested project→Studio linking and a bottom-right icon on both cards and list items; clarified one Studio only, e.g. playcase.gg→playcase.gg Studio. Existing studioID denotes membership/conversion and must not be reused: it would move the project out of Projects. Add a separate Mac UI link keyed by normalized project folder and Studio UUID, persisted with the existing AppPreferences defaults. No daemon API or restart needed. Project folders, membership, instructions and transcripts stay intact.

Visual target: project card/list [project details …] [bottom-right palette]. Right-click project → Linked Studio → choose one Studio or None. Palette → only that Studio's active chats, with empty-state text; selecting one opens that existing chat. Link is inactive while Studio archived/missing. No automatic matching/linking of real projects.

- [x] S1 Persist single link per folder; replacing/unlinking affects only that project, archive/missing handled.
- [x] S2 Add linking context menu and bottom-right palette on cards/list; preserve card selection and themes.
- [x] S3 Native renders and isolated link persistence/routing checks; build Mac and install locally.

Acceptance: one link, survives store reload, chosen chat belongs to linked Studio only, links neither move nor recreate chats, provider/logo retained, shortcut reachable in Cards and List. Native test fixture uses isolated data and preference suite. Deliverables: local source, test evidence, installed Mac. Linear gpt-6.1-sol medium (same verified session), readiness R1–R13 pass, no unresolved scope questions. User implementation authorization supplied directly; GitHub remains read-only per earlier restriction. Rollback: unlink via menu; revert scoped source and restore previous app backup. New preference is Mac UI only, not mobile/agent routing. No service restart.

Verification: Mac build and local install passed. Isolated store reload/normalization, replace/unlink, archive guard and Studio-only open actions passed; chat records unchanged. Actual card/list views rendered and visually inspected in linked-card-list.png. Menu selection uses verified action but actual menu clicks were not exercised. Uncommitted/local only. Daemon PID 60096 unchanged.

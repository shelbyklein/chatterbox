# Global pinned sessions in the sidebar

Pinned sessions currently render inside each page's Projects, Chats or Studio list, beneath that page's heading. Page-specific Studio and tag filtering can also hide unrelated pins. Move them into one independent section below Activity and above the selected page's heading, and put the list/card switch to the right of Search.

Evidence: [current sidebar](assets/before.png); `Core/Chatterbox/Views/ContentView.swift` (`sidebarPane`, `sidebarSessions`, `cardSection`, `listSection`, `isShown`) and `ChatHomeView.swift:DesktopOverviewControls`. [Target layout](assets/target.svg).

## Outcomes and scope
- Search and the existing page-specific list/card switch share one row, including narrow sidebars.
- Pins form their own bounded, scrollable list below Activity across Projects, Chats and Studio sidebars. They remain list rows in card mode, with source labels, context menus, selection and child threads preserved.
- Pins are independent of page, tag and activity filters; text search still searches them. They do not repeat in the page's ordinary threads.
- No stored-data changes, mobile changes, global shortcut-pin changes or service changes. Existing pin order, keyboard order and persisted view preferences remain.

## Tasks
- [x] P1 Move and separate sidebar components. Check: native render shows Search/switch together, Activity, Pinned, then page heading in that order.
- [x] P2 Verify universal visibility and interaction using the isolated Studio sidebar fixture; cover Projects/Chats/Studio, list/cards, text search and narrow sizing. Run `scripts/test-studio-chat-sidebar.sh` and `scripts/test-chat-toolbar.sh`; inspect screenshots. Run `scripts/check-sources.sh` and Mac build.
- [x] P3 Commit/push scoped Core and root work; install with `scripts/install.sh` under standing approval and verify installed binary/running app. Run tidy report only. No daemon restart or iOS upload needed for this Mac-only view change.

Deliverables: verified Mac UI and tests committed/pushed, inspected screenshots here, installed app. Rollback: revert scoped commits and reinstall; persisted records and preferences are unchanged. Open questions: none.

Work preparation: local: `design/sidebar-global-pinned/plan.md`. User's direct request supplies scope confirmation and implementation authorization. Linear, since one sidebar owns both changes; executor current session, exact model/effort unavailable. No GitHub issue mutation or delegation. Readiness R1–R13 pass; R12 covered by reinstall rollback. Routine installation already approved in AGENTS.md.

## Delivery and verification
- Core implementation committed and pushed as `a90d988`.
- Studio sidebar and chat toolbar tests pass. Render fixtures inspected for Projects, Chats, Studio and a 280-point sidebar; all four universal pins remain visible despite page-specific filters. Saved proofs are in `assets/`.
- Source checks and Mac build pass. Installed with `scripts/install.sh`; installed executable matches the build and the running app visibly shows Search/switch in one row, then Activity, Pinned, and Projects. Live Search for Tool Audit retains that pin; search was cleared afterward.
- Automated interaction coverage remains the existing sidebar suite; the added cases provide render coverage. An attempted geometry assertion was removed because retained fixture windows contaminated shared measurements.
- Tidy report completed; no cleanup applied. It reports three removable mobile test build folders and existing queued restart jobs, left untouched. No service restart requested by this change and no iOS changes.

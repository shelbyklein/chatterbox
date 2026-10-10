# Promote chats on iOS

Regular iOS chats can be renamed, archived and forked but cannot become Projects or join Studios. Add Move to Studio and Make Project to their long-press and open-chat menus, backed by authenticated companion mutations. Keep the same chat identity, transcript, drafts, tags, agent and permission settings; no existing files move.

Evidence: `Core/ChatterboxMobile/ChatListView.swift:chatActions`, `ChatDetailView.swift:chatMenu`; Mac `Studios.swift:joinStudio/newStudio` and `ChatSession.swift:bindProject/setStudio` define existing folder behavior. [Current iOS UI](../mobile-studios/assets/activity-rename-ipad.png) · [Target flow](assets/target.svg).

## Scope and decisions
Ordinary, active, top-level chats only; existing Projects, Studio members, Sidechats, worktrees, automation threads and Golem are excluded. Promotion is refused while running/reconnecting, including a race after opening the sheet. Studios: choose an existing Studio (keep current folder by default, optional shared folder) or name a new one. Projects: choose a Mac folder through a directory-only browser, optionally create a new subfolder. An already-owned project folder is rejected rather than merging/overwriting chats. Cancel/errors keep the sheet usable. No new permission defaults, repository creation, file moving, Mac UI changes or real-chat test mutations.

Optional folder choice was asked; existing plus new is the stated default after giving time to respond. No blocking questions. Local tracking only, honoring the user's existing no-GitHub-issue-mutations boundary.

## Success
1. iPhone/iPad menus expose the two actions only for eligible chats, with running state disabled.
2. Studio/new Project moves preserve identity/history/draft and appear in the destination after refresh.
3. Folder collisions, stale/running sources, unavailable folders, unauthorized requests and failed saves do not silently lose data; retry cannot duplicate a Studio.
4. Simulator interactions and headless backend tests pass; fresh screens inspected.

## Tasks and deliverables
- [x] P1 Add wire types, guarded durable runtime mutation and paired-only directory browsing. Check: backend tests verify preservation, collision/retry, auth and persisted grouping.
- [x] P2 Add reusable destination sheet to both chat menus. Check: iPhone UI exercises existing/new Studio, existing/new Project, cancel, errors and grouping; iPad focused test passes.
- [x] P3 Build Mac/iOS, source check, inspect screenshots, commit/push Core and root scoped work. Check: clean builds and source checks; evidence linked.
- [ ] P4 Complete compatible Mac service activation. User approved routine delivery on October 10; Mac app/service files are installed and TestFlight 1.0 (202610101921) is available to the Shelby group. Only the queued idle service restart remains pending while replies run. Do not interrupt replies. Keep activation status distinct from tested source.

Test commands: `scripts/test-chatterbox-daemon.sh`, a focused paired promotion route test, `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testPromoteChats scripts/test-mobile-home-nav.sh iphone` and `ipad`, `scripts/check-sources.sh`, standard Mac and iOS builds in canonical folders. Retain simulator screenshots and inspect them. Test fixtures use isolated directories; no user chat or folder changes.

Rollback: revert scoped code commits and deliver replacement builds. Existing records remain compatible. Mutation snapshots the chat record/Studio list and restores them on failed persistence; it never deletes existing folders/files. Newly created empty directories are removed on failed creation/mutation when safe. Completed promotions can be undone via existing Mac unbind/remove-from-Studio controls; files remain.

Work preparation: direct implementation request authorizes the described feature now; linear because UI and API share a contract. Executor current session; exact model/effort unavailable. Readiness R1–R13 pass; R7 local: design/mobile-chat-promotion/plan.md. No issue creation/closure or delegation. The original P4 approval gate was satisfied by the user's “Yes do it and update so you don't have to ask”; AGENTS.md now records standing approval for routine delivery.

## Verification
- `scripts/test-mobile-promotion.sh`: passed all paired route and runtime checks, including history/draft/settings preservation, retries, occupied folders, invalid paths, save-failure rollback and directory-only browsing. Artifacts: `/tmp/golem-promotion.lbJGtK`.
- `scripts/test-chatterbox-daemon.sh`: passed both-provider turns, questions/approvals, steering/stopping, replay, restart, drafts and ownership checks. Artifacts: `/tmp/golem-runtime.cxvRzG`.
- Mac app build, standalone daemon build, signed iOS device build and source consistency check passed. No live chats or folders were promoted during testing.
- iPhone simulator `testPromoteChats` passed in `build/mobile-home-nav.6rSiGl`. It exercises both menu entry points, existing/new destinations, cancel, visible errors/retry and destination grouping. Inspected [existing Studio](assets/promotion-existing-studio-iphone.png), [new Studio](assets/promotion-new-studio-iphone.png), [folder browser](assets/promotion-folder-browser-iphone.png) and [new Project](assets/promotion-new-project-iphone.png). Initial runs exposed test-fixture/selector mistakes; the final run passes without production changes.
- Release archive succeeded: `build/TestFlight/Chatterbox-202610101921.xcarchive`, version 1.0 (202610101921). Subsequently delivered through TestFlight as recorded below. The previous delivered archive was replaced under the single-archive rule.
- iPad mini simulator `testPromoteChats` passed in `build/mobile-home-nav.CVDscl`. Inspected the centered [Studio sheet](assets/promotion-existing-studio-ipad.png) and [Project sheet with keyboard](assets/promotion-new-project-ipad.png); controls and text remain visible. Portrait was tested; no landscape claim.
- Core implementation committed/pushed as `6cb7c55`; this companion commit records the submodule, generated project, tests and evidence. Older Mac services omit `canPromote`, so the new menus stay hidden until the compatible service is installed/restarted.
- Final tidy report: no orphan test processes, test simulators or queued restart jobs. It lists 22 saved build/test artifact folders (996 MB); no broad cleanup was applied. Other repositories' app copies were left alone.

## Delivery — October 10, 2026
- `scripts/install.sh` succeeded; installed app and daemon binaries match the verified build, and `/Applications/Chatterbox.app` reopened (PID 62572 at verification).
- The initial `nohup` restart worker exited with the agent shell. `scripts/restart-service.sh` now creates a one-shot launchd job (`RunAtLoad=true`, `KeepAlive=false`) and writes its own PID. A delayed test worker survived the launching shell; replacing it stopped that worker and left one default idle-wait worker owned by launchd (PID 64360 at verification). Shell syntax and plist settings pass. Two replies were active, including this conversation; no forced restart or host termination was performed.
- After the user unlocked the Mac, Xcode Organizer uploaded the saved archive at 7:36 PM. Command-line export had failed with `Failed to Use Accounts`; no rebuild or repeated sign-in was needed for Organizer. Apple processing and the current-build encryption declaration are complete. Verified **1.0 (202610101921)** as **Testing** in the existing Shelby internal group: [TestFlight evidence](assets/promotion-testflight.jpg). No testers were added and nothing was submitted for public release. The prior build was confirmed installed on the iPhone; installation of this newest build is not confirmed.
- After upload, launchd worker 64360 was still alive with parent 1. Two replies remained active, including this conversation; the report still says it is waiting. Promotion capability remains hidden until the queued service restart completes. No live chats were modified for verification.
- Delivery tidy report: no orphan test processes or test simulators; 22 saved artifact folders (996 MB) and the expected queued restart remain. Other repositories' 13 app copies were left alone. No cleanup was applied.

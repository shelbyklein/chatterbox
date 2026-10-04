# Project → Studio: new conversion and pending existing-Studio move

Requested: add a project context-menu option to convert/move it into a Studio. Existing model.move refuses project chats; setStudio clears projectFolder and changes agent cwd to studio.folder. New Studio conversion can reuse the project folder via newStudio(folder:), but needs a deliberate path through the project guard and handling existing worktree/sidechat children so none disappears.

Pending user choice (asked asynchronously): when moving into an existing Studio, keep the project folder as a project within that Studio, or switch to the Studio's shared folder. These imply different data/grouping models. Do not silently change the agent's working directory or move files while this is unsettled.

Prepared UI: project context menu → Convert to New Studio… (reuse current folder), plus Move to Studio → existing names. Proposed checks: preserve history/drafts/provider IDs; test original directory and settings; handle worktrees without hidden orphan chats; persist/reload; no filesystem move/deletion; sidebar and companion groups contain each chat once. Preserve project-scoped secret access when directory remains unchanged.

Work preparation: local:project-to-studio; user authorizes implementation; scope incomplete only for existing-Studio folder semantics. Linear GPT-6.1-Sol Medium. Readiness pending R10/R11 until answer arrives. That was the initial review; independent new-Studio conversion proceeds below. Existing commit/push/install authorization carries forward once ready; no GitHub issue mutations.

## Ready independent scope: Convert to New Studio
The existing-folder new-Studio conversion is unambiguous and independently authorized. Implement this now; existing-Studio move stays excluded pending the answer. Linear GPT-6.1-Sol Medium, readiness R1–R13 pass for conversion scope.

Target flow: Project context menu → Convert to New Studio → name/explicit existing-folder notice → original thread and worktree/Sidechat children in Studios. Success: IDs/history/drafts/cwd/agent settings unchanged; files unmoved; no hidden or duplicate descendants after reload. Add design.md only through established Studio setup, preserving any existing one. Original project-secret scope remains while the converted Studio uses that original folder, and clears when moving away.

- [x] STUDIO-1: Conversion/menu/name sheet with no destructive file operations; idle parent guard.
- [x] STUDIO-2: Fixture history/settings/children/persistence/old-record checks and native sidebar render inspected.
- [x] STUDIO-3: Build, commit/push/install Mac and verify bundle; existing-Studio move reported pending.

Tests: scripts/test-project-studio.sh and scripts/test-sidechat.sh using production debug module and isolated data. Rollback: preserve installed app /tmp/Chatterbox-before-sidechat.app before combined install; restore app if necessary, preserve all new Studio/Sidechat saves. No GitHub issue changes or actual user-project conversion during testing.

Verification: scripts/test-project-studio.sh passed same cwd, provider IDs/tasks/history/draft/settings, running worktree state, descendant uniqueness/order, pins moved, existing design preserved, reload, missing-folder refusal, fork ownership and stale secret scope cleared. Native sidebar render inspected: /Users/shelbyklein/Chatterbox/Screenshots/project-to-studio/converted.png. The menu/name confirmation dialog was not clicked; conversion path was fixture-tested and the resulting production sidebar rendered. No real project was converted. Sidechat regression passed again against integrated code. Existing-Studio direct move remains pending the folder choice.

Installed Mac code revision b315910; scripts/install.sh succeeded, signed bundle verified by installer, installed/built debug dylib SHA-256 match 4e01899fc9c860e86e8d77915107dd61d2ae89c5e443c5a9f1a39696890cfbbc, /Applications process launched and authenticated local API returned 200. No user project converted and no live Sidechat created during verification. Mobile UI not installed/exercised in this task.

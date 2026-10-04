# Separate Golem repository

Shelby requested separate projects/repositories on 2026-10-04. Current baseline `308c681` is clean; another agent worktree at `6f00428` is preserved. Investigation: project.yml Golem compiles Chatterbox except its entrypoint, ChatterboxRuntime, Shared and GolemApp; GolemMobile compiles ChatterboxMobile and Shared with GOLEM_APP. GolemService also compiles engine/runtime source. Moving folders alone would break builds.

## Proposed boundary
```mermaid
flowchart LR
    C[Chatterbox repo: Mac/mobile apps and chatterboxd] --> S[Shared core: reusable UI, engine and protocol]
    G[Golem repo: Mac/mobile apps, rig and golemd] --> S
    G -->|authenticated existing RPC| C
```

User authorized execution of the recommended shared code plan. Selected pinned shared-source Git package, preserving existing compilation flags rather than introducing an incompatible SwiftPM module. Repository visibility must match existing source visibility; verify it before remote creation. No remote repositories created yet. No source or service changes yet.

## Execution
Linear in this Codex session; handoff identifies GPT-6.1-Sol Medium. Local plan tracking respects standing no-GitHub-issue-mutation instruction. Readiness R1-R13 pass: scope confirmed, diagram, checks and rollback recorded; shared ownership and complete target dependency map verified.

- [x] SPLIT1: settle shared ownership; map every target's source/resources/framework dependencies and tests; identify framework/package boundaries including GOLEM_APP compilation conditions.
- [x] SPLIT2: prepare isolated Golem repository at /Users/shelbyklein/Vibes/Golem and shared component with pinned dependency, retaining original source/history; generate independent Xcode projects. Verify fresh-checkout independence, not sibling path assumptions.
- [x] SPLIT3: build both Mac apps/services and both universal mobile apps; run protocol, mobile, lifecycle and rendering regressions with fixture data; inspect Golem screens.
- [x] SPLIT4: only after independent builds pass, remove migrated targets/assets from Chatterbox, commit/push scoped repositories and update docs/install scripts. Preserve unrelated worktrees.
- [ ] SPLIT5: deploy compatible UI binaries under standing authorization; report exact installs separately. Do not adopt/migrate data or reactivate paused automation.

Success: independent Git/build/release roots; reusable code has a single explicit source of truth if selected; existing bundle IDs/APNs topics, pairing, user files, runtime paths, provider sessions and functionality remain compatible. Exclude new services/accounts, production network changes, paid calls, deleting original history, reactivating automation and moving user data. Backup bundles before install. Rollback code/projects using preserved baseline; installed compatible bundles restored without starting legacy writers against daemon-owned data.

## Verification checkpoint
- Shared repo `shelbyklein/chatterbox-core`; independent Golem repo uses Shelby's empty `shelbyklein/golem`; same public visibility as the original. Shared package is pinned Git source, not a SwiftPM module.
- Byte-identical initial extraction of 193 tracked source/resource files. Mobile ConnectView/ReaderStyle common declarations then split from the product entrypoint; subsequent starter/grid updates are separate core commits.
- Both Mac products/services and both universal mobile targets build independently. Fresh remote recursive clones in `/tmp/chatterbox-split-clean.CIkwV1` build Golem and Chatterbox without sibling source dependencies.
- Service/policy fixture pass: `/tmp/golem-service.y7hjh12l`, `/tmp/golem-policies.90vq754q`. Daemon replay/restart/ownership pass `/tmp/golem-runtime.ufguyE`. Command Center native fixture pass `/tmp/chatterbox-command-center.3mMiYv`.
- Separate Golem iPhone and iPad product UI suites pass (`Golem/build/mobile-ui.i64R2E` and `mobile-ui.jUwddL`), including journal/settings, large text, offline/reconnect. Chatterbox iPhone product suite passes in `build/golem-mobile-ui.4chhee`. Golem test's optional cross-app handoff is not exercised by the independent default suite. Full physical-device acceptance, actual window multitasking/VoiceOver and real push remain unverified; existing acceptance limits are preserved.
- Inspected Mac and iPhone fixture renders under `/Users/shelbyklein/Chatterbox/Screenshots/golem-repository-split`.
- Unrelated preserved worktree `agent-abe03c29354d9b44f` remains at `6f00428`. Future integration of old worktrees' shared-code edits must target Core and update consumer pins; do not replay deleted product paths. No running service or data migration changes.

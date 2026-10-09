# New Studio chat permissions

New Studio chats currently inherit ordinary new-chat defaults, which can be Manual. Start newly created Studio chats in Claude Bypass permissions and Codex Full access. Apply the same rule for an empty Studio chat reused by New Chat, the first Maestro chat, and companion-created Studio chats.

Evidence: AppModel.newChat uses PermissionModes.defaultClaude/defaultCodex; Studios.newChat(in:) delegates to it; DaemonContext.newChat(in:) also delegates to ordinary defaults. Scope is creation only: existing populated chats, converted/moved conversations, ordinary chats, model/effort defaults and user permission changes remain unchanged. No visual layout change; R3 n/a. No blocking questions.

Success: restrictive ordinary defaults cannot make a new Studio chat Manual; both provider modes survive selecting a preset or switching agents; ordinary/converted chats retain their modes. Verified in isolated AppModel and daemon fixtures; Mac app builds.

- [x] P1 Add shared creation-default helper and apply in Mac and companion creation paths. Acceptance: both provider fields initialized without changing the selected backend/model.
- [x] P2 Verify new, reused-empty, first-preset and preserved-conversation cases with `scripts/test-project-studio.sh`; verify companion creation and reload with `scripts/test-chatterbox-daemon.sh`; Debug Mac build passes.
- [x] P3 Commit/push scoped changes. Installation and service activation await user approval; never interrupt live chats.

Deliverables: source and regression assertions committed/pushed; built Mac, activation pending approval. No migration or edits to existing user records. Rollback: revert scoped creation-default changes, no bulk record update. Work preparation: direct change request authorizes implementation now; linear because both paths share a helper. Current session; exact model/effort unavailable. R1–R13 pass; R7 local plan, no GitHub mutations, R12 no data migration and source-only delivery.

Verification: Debug Mac build passed; project source check passed. `test-project-studio.sh` passed creation, reused-empty, populated-chat preservation, restrictive ordinary defaults and preset/backend-switch assertions plus existing conversion/navigation regressions. `test-chatterbox-daemon.sh` passed companion creation and persisted-record checks for Claude/Codex, and all existing both-provider reply/replay/restart tests. An intermediate fixture held DaemonContext beyond its intended scope and prevented a test runtime restart; scoped that reference, then the complete suite passed. No installed service restarted.

Delivery: Core 3070296 and root scoped implementation/tests/plan pushed. Mac installation and idle service restart for companion creation remain pending approval.

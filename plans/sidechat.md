# Temporary Sidechats

Add a Sidechat action to a project or chat's Mac context menu. It creates a separate, explicitly temporary conversation using the same folder and agent settings, without Git branching or copying the parent transcript. End Sidechat archives its history; no automatic deletion.

Target structure: Project/Chat → indented [Temporary · Sidechat] → End Sidechat → Archived. Sidechats of Golem appear in Chats with their parent relationship retained, so Golem's fixed home stays compact.

Work preparation: local:sidechat; direct implementation request confirms now. Linear GPT-6.1-Sol Medium, one lane. R1–R13 pass; no blocking questions. Existing scoped commit/push/Mac install authorized; no GitHub issue mutations. Mobile list representation included, no new mobile creation control/device install in this change.

Success/deliverables: Mac menu action creates one fresh session preserving parent's history/draft/provider session, same cwd/settings; visibly temporary/nested; archive retains data; empty sidechats persist on relaunch and remain in companion list. Source/plan/test committed/pushed, Mac built/installed; native screenshot checked. Optional fields must decode old saves.

- [x] SIDE-1: Add optional parent/folder metadata, creation and safe archiving. Fixture regression validates independent session IDs, inherited settings, same folder and persistence.
- [x] SIDE-2: Mac creation/end menu, temporary badge/nesting; companion list visibility. Native menu entry/render check; old save compatibility and no duplicate grouping.
- [ ] SIDE-3: Build, scoped commit/push/install, verify bundle. Screenshot proof and remaining device limits reported.

Preserve parent files/settings/history; no worktree/branch operations or implicit execution. All history remains local; no transcript copying. Converting projects to Studios is separate, waiting on existing-Studio folder semantics. Tests link production debug module with isolated data, automatic Golem jobs off, no provider turns. Backup installed app /tmp/Chatterbox-before-sidechat.app; revert commit to roll back UI, new optional metadata remains harmless and unknown-field-compatible in saved JSON. Never remove saved sidechat files on rollback.

Verified scripts/test-sidechat.sh: native click creates fresh session, inherited route/effort/Fast/permissions/folder, unchanged parent including running flag and draft, one appearance in companion list, old-record decoding, empty persistence/archive and orphan fallback. Native sidebar render inspected at 280pt: /Users/shelbyklein/Chatterbox/Screenshots/sidechat/sidebar.png. Golem sidechats show in Chats. No real provider turn sent; phone payload checked, mobile UI/device not checked. Creation shared button clicked in native harness, full right-click menu itself not clicked.

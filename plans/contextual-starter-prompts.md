# Project and Studio starter prompts

Shelby's screenshot shows generic Claude questions even in scoped work. Make the three empty-thread starter questions use the attached project and/or Studio name, for either backend. Unbound chat fallback and draft-only button behavior remain unchanged; no provider calls or project file reads occur until the user submits a prompt.

Current reference: `/Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/26C523EB-1613-4C9B-AF56-914BEF94709C/CleanShot 2026-10-04 at 11.05.12 AM@2x.png`.

Target sketch: existing three full-width buttons read (1) Tour Galley and its instructions/current work (2) Find unfinished work in Galley (3) Plan the next Galley improvement. Studio-only: read USA Archery instructions/design.md; plan work using briefs/assets; review current work. Combined project/Studio names appear together. Same layout, full wrapping.

Local tracking, linear execution in current Codex GPT-6.1-Sol Medium handoff. User's action request supplies scope/implementation; readiness R1-R13 pass; R12 no stored-data migration (shared git revision can be reverted). No blocking questions. Success: correct three-context suggestions on both backends, real empty ChatView rendered with fixture context, still only fills draft. Tests: scripts/test-starter-prompts.sh plus isolated native render.

- [x] START1: shared core prompt selector, actual session context wired into EmptyChatView.
- [x] START2: project/Studio/combined/unbound tests for both backends pass.
- [x] START3: inspect project and Studio native renders; pin tested core in both apps, build/commit/push/install under existing Mac authorization.

Excludes dynamic AI generation, new mobile empty-state UI, provider/account changes, changes to project/Studio instructions, file reading/indexing, and sending anything on behalf of the user.

Visual proof: actual production ChatView window-server captures inspected in `/tmp/chatterbox-starter-ui.IfU2W8`, stable copies `/Users/shelbyklein/Chatterbox/Screenshots/starter-prompts/`. Provider intentionally unavailable in fixture; warning banner is fixture-only. First view-cache capture failed to draw text correctly; using current-process ScreenCaptureKit produced readable native buttons without screen capture of other applications. No messages/drafts submitted.

Pinned in shared Core `5c3a4ec`, Chatterbox `eb82539`, Golem `8427c4e`. Mac builds pass; installed hash identity verified. Installed interactions not driven.

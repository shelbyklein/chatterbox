# Chat sidebar and session controls

Show New replies explicitly in the Chats sidebar for quick access. Move session-specific controls from the main window toolbar to a compact icon and dropdown in the chat, beside Notes and Quick prompts on the right.

Current evidence: ContentView.sidebarColumn already contains UnseenRepliesStrip, but the strip disappears when empty. ChatView.chatContent places Notes and Quick prompts in a top-leading overlay; WindowToolbar carries ToneSlot, PlaceSlot (including images), and RepoSlot. [Current screenshot](current.png). [Target sketch](target.svg).

Scope: macOS regular chat windows, including project and Studio sessions. Reuse tone, folder/Studio, image and repository/issue controls; keep their existing actions and data. Leave Golem, compact chats, multi-session tiles, iOS, authentication, and agent runtime unchanged. Preserve Notes, Quick prompts and message pins, with pins below the controls. Terminal placement is an optional preference; default to keeping its top-bar shortcut unless requested otherwise.

Success: Chats sidebar visibly offers New replies, including an empty state; unread rows open the correct chat and clear from attention. Session tools, Notes and Quick prompts appear at the top right without overlapping pins. Main toolbar no longer duplicates the moved session controls. Existing actions still target the selected session.

Deliverables: committed and pushed source, local plan and inspected fixture screenshot; Mac build verified. Installation requires user approval under AGENTS.md and remains pending until requested. No service restart needed.

## Tasks
- [x] T1 Make the Chats New replies section discoverable even when caught up; verify unread and empty fixtures.
- [x] T2 Group session controls, Notes and Quick prompts on the right; verify rendering and session binding.
- [x] T3 Verify Mac build and toolbar suite, inspect screenshot, commit/push scoped work and run tidy report.

Validation: scripts/test-chat-toolbar.sh; xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData build -quiet. Extend toolbar fixture to render right-side session controls and New replies. Real entry: Chats view, select a session, top-right Tools icon. Render controls alongside pins and inspect screenshot. No persistent schema change; rollback is reverting scoped commits. Installed app is preserved until approved installation.

## Work preparation
Tracking: local: design/session-controls/plan.md (no GitHub issue mutations).
Scope authorized by user's direct edit request; execute now. Linear, because these controls share ChatView/toolbar state. Executor: current session; exact model/effort unavailable. No delegation. No blocking questions.
Readiness: pass 2026-10-08, R1–R13 covered above; R7 local task checklist. Install gate remains pending.

## Verification evidence
Mac Debug build and scripts/check-sources.sh passed. Inspected [chat controls](chat-controls.png), [tools panel](tools-panel.png), [unread Chats sidebar](new-replies.png), and [caught-up sidebar](caught-up.png). The unread fixture opened the correct chat and cleared its attention entry. Existing toolbar controls retain their identity across chat switches. Native popover and Image Library interaction remain an installed-app acceptance check: the isolated harness cannot reliably drive these SwiftUI controls through AX or synthetic events. The final toolbar suite passed all checks, including Settings/Terminal, after restoring the main test window focus. Synthetic-click assertions were removed because the harness could not exercise those SwiftUI controls reliably; installed dropdown interaction remains pending.

Tidy report: 126 older test folders (837 MB), no leftover test processes or stray app copies in this repo; 12 Golem build apps left to their owner. Report only, no deletions.

## Installed acceptance
2026-10-08: user approved installation; scripts/install.sh completed and the installed executable matched the verified build. The app reconnected; chatterboxd retained PID 24522. Through native computer use, Session tools opened its popover with Friendly, USA Archery and Image Library; Image Library opened the current session’s six images. Closed the sheet and returned to the same chat. Inspected the installed screenshot showing tools, Notes and Quick prompts on the right. No service restart or interruption of replies.

## Compact Working list — 2026-10-08 follow-up
User requests currently turning sessions at the bottom of the left sidebar, minimal. Confirmed scope: all regular sidebar pages, above Archived, provider-colored spinner and one-line title; collapsible heading and a bounded scrolling list, hidden when empty. New replies stays at the top. No new persisted chat data, runtime changes or iOS work. Use Attention.workingChats and openWorkingChat.

- [x] T4 Build and inspect the compact Working strip; existing activity test verifies running/finished filtering and navigation. Run scripts/test-finished-chat-bell.sh and the Mac Debug build, then commit/push. Installed check waits for user approval under AGENTS.md.

Target: the existing target sketch plus a bottom Working heading and one-line rows directly above Archived. Linear; current session, exact model/effort unavailable. R1–R13 pass for this scoped addition; no blocking questions. Rollback by reverting these UI commits.

- [x] T5 Make the whole padded Tools, Notes and Quick prompts label clickable, not just its glyph. Verify padding clicks in the installed app after approved installation. No behavior or data change beyond hit areas.

Follow-up verification: Mac Debug build and source check passed. scripts/test-finished-chat-bell.sh passed running/completed filtering, persistence and native activity navigation. Inspected [compact Working list](working-sidebar.png). Tools, Notes and Quick prompts labels now have contentShape(Rectangle()) after their padding, so padded label areas participate in hit testing. Installed bottom placement and padding-click acceptance remain pending user-approved installation. Tidy report unchanged (126 older temp folders); nothing deleted.

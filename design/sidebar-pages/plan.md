# Separate Projects and Chats navigation

Shelby requested separate sidebar pages, removal of the Studios link under search, a Projects-shaped first toolbar icon, and a trailing New Chat +. Keep transcripts, project sidechats/worktrees, Studios thumbnails, multi-session and Automations views intact. Current evidence: supplied screenshot shows Projects/Studios/Chats sections together with project tag filters hiding standalone chats.

[Target sketch](target.svg): toolbar [folder Projects | palette Studios | grid Multi | clock Automations | bubble Chats] … [usage | terminal] [settings] [+ New Chat]. Projects sidebar: Projects only. Chats sidebar: standalone sessions only, with search; project tags must not hide them.

- [x] N1 Implement local sidebar page state, navigation actions and final +; no new service API or stored data changes.
- [x] N2 Verify native toolbar actions, no chat creation from Chats navigation, creation from +, project/chat card separation and rendered sidebar states.
- [x] N3 Build and install locally without daemon restart; leave GitHub unchanged.

Success: folder and bubble show the correct sidebar sections; navigating to Chats does not create sessions; + creates/selects a standalone chat; no Studios button below search. Deliverables: local code/tests, inspected renders, installed app. Linear gpt-6.1-sol medium, readiness pass R1–R13; user authorized implementation with explicit layout request. No blocking questions. Target sketch above and user's before screenshot are the visual aids. Rollback: existing /tmp/chatterbox-card-rollback.* app backup. Test: scripts/test-chat-toolbar.sh plus native isolated sidebar fixture; xcodebuild Mac. Existing selection, drafts and all service processes preserved.

Results: Mac build passes. Native toolbar assertions pass (Projects/Chats navigation, Chats creates no session, trailing + opens standalone chat, persistent toolbar across switches/Settings). Sidebar separation/filter parity visually checked in native captures; global geometry and AX assertions are unsupported for this offscreen fixture and were replaced by inspected captures. [Projects](projects.png), [Chats](chats.png), [Toolbar](toolbar.png). Final native runner used -Onone, otherwise same script. App installed locally and executable matches build; daemon PID 60096 unchanged. Source remains uncommitted/unpushed; GitHub untouched. Rollback: /tmp/chatterbox-sidebar-rollback.Zx5S7K/Chatterbox.app.

Follow-up scope: Projects defaults to Cards, Chats defaults to List; separate per-page preferences so toggling one does not change the other. Chats list rows gain 6pt padding above/below in addition to the Appearance row-spacing preference. Preserve project spacing. Verify native sidebar captures in their default formats.

Follow-up result: independent Projects Cards and Chats List defaults visually verified in tests/current-model native fixture. Mac build passes and local install completed; service unchanged. Each layout toggle saves to its own page preference. Chats row padding adds 12pt total per item.

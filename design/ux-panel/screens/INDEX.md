# Chatterbox screenshot pack (UX/UI review)

## About the app

Chatterbox is a personal Mac + iPhone/iPad app for running and supervising many Claude and Codex
coding and design agent sessions at once. The Mac runs the agents; the phone is a remote for them.
Key concepts: **sessions** (also called chats or threads: one conversation with one agent);
**projects** and **Studios**, the places work lives (a project is a code folder, a Studio is a
creative workspace such as "USA Archery" holding several sessions; a session can also stand alone
under Chats); the **Desk**, a front desk that shows what needs you (approvals, questions), incoming
requests waiting to be placed, and what is working; **automations**, scheduled routines that run a
session on the Mac; and **approvals**, where an agent asks before running a command.

All content is fixture data from the test harnesses (no real chats). Captured November 4, 2026.
Dark mode unless noted. The Desk is shown as it is today; it is the baseline for a planned redesign.

## Screens

| File | Platform | Screen / state | Notes a reviewer can't see |
|---|---|---|---|
| 01-iphone-desk.png | iPhone 17 Pro | Desk tab: summary line, ask box, Needs you (an approval with Approve/Deny, a question with Open), start of Incoming | The Desk is the first tab and where a fresh install opens. Tapping a card opens its session. Tab badges count waiting items. |
| 02-iphone-desk-silence-swipe.png | iPhone | Desk with the Tracker Trapper question card swiped left, showing Silence | Swiping a Needs-you card left reveals Silence; a full swipe silences without a tap; long-press also offers Silence. Silencing takes it off the Desk only; the session still waits. |
| 03-iphone-desk-start-there.png | iPhone | Start There sheet for an incoming request: the request, its place (USA Archery, Change), sessions already in that place, New session | Continue sends the request into the checked session as its next message; picking New session shows a model row instead. It runs in the background: the Desk stays and shows a note with Open. |
| 04-iphone-desk-change-place.png | iPhone | Choose a Place sheet over the Desk: Studios and projects with one-line descriptions, search | Opened by Change Place / Choose a place on an incoming card. The list also has "A session of its own" at the bottom. Start There is disabled until a request has a place. |
| 05-iphone-desk-empty.png | iPhone | Desk with nothing waiting: "Nothing else needs you." and the working line | Empty sections are hidden. The working chips (Galley, Coach Archie) open those sessions. |
| 06-iphone-projects-list.png | iPhone | Projects tab: Activity box (working sessions, one new reply) above the project sessions | Rows show the agent mark (Claude orange, Codex green), last line, a waiting dot, a worktree branch icon (optimization) and a sidequest line under SDHQ. The ⋯ menu switches list/cards and sort. |
| 07-iphone-studios.png | iPhone | Studios tab: Activity box, then one card per Studio | A Studio card opens that Studio's sessions as cards with the newest image as each card's thumbnail. |
| 08-iphone-conversation.png | iPhone | A working Claude session (Galley), scrolled to the latest reply: heading, list, code block with Copy, table, "Worked for 12m 34s", Working indicator, composer | The session is still running: the composer reads "Add something while it works…" (a message sent now is queued) and the round button beside it stops the reply. The header subtitle "Claude · Opus" shows the session's agent and model. |
| 09-iphone-conversation-steps.png | iPhone | Same session scrolled up: user message, collapsed Thought, tool rows, plan checklist, a failed test run, narration, a passing run | Thought is folded until tapped. Tool rows are one line, truncated in the middle; the icon shows done, failed or running. |
| 10-iphone-session-settings.png | iPhone | Session Settings sheet: provider (Claude / Codex / Open models), current model row, effort slider, Permissions below | Opened from the session's ⋯ menu. Tapping the model row opens a menu of that provider's models (Opus 5.5, Sonnet 5, Haiku 5). Changes apply from the next message. |
| 11-iphone-approval.png | iPhone | SDHQ session with a pending permission card: the command and Allow / Allow for This Session / Deny | The same approval appears on the Desk (01) with Approve/Deny. The strip at the top is a running sidequest (a side session sent to Codex). |
| 12-iphone-composer-attachment.png | iPhone | PlayCase Magnets session with the message box holding a marked-up image and generated feedback text | Produced by tapping a photo in a reply → Comment → tapping a spot and dragging an area, each with a note → Add to Message. The note text and marked-up copy wait in the box; nothing is sent until Send. |
| 13-iphone-new-chat.png | iPhone | New Chat sheet: optional name, Start in (Chats), model provider and model, effort, permissions (Manual vs Bypass permissions) | Opened from the compose button on a list. Start creates the session and opens it. "Start in" picks a project or Studio. |
| 14-iphone-automations.png | iPhone | Automations sheet: three routines with project, agent, model, schedule, next run; one switched off | Opened from the ⋯ menu or the Desk. The switch turns the routine on or off on the Mac (all of its days). "Last run" opens that run's session. Tapping a routine opens its editor with Run Now. |
| 15-iphone-connection-error.png | iPhone | Projects list after the Mac stopped answering: "Can't reach Regression Mac" card above the cached list | The fixture held replies past the app's 6-second timeout and the list was pulled to refresh. Saved sessions stay readable while the Mac is unreachable. |
| 16-iphone-desk-light.png | iPhone | Desk in light mode | Same state as 01. |
| 17-ipad-desk-two-columns.png | iPad mini (portrait) | Desk on a wide screen: Needs you and Incoming cards in two columns; top tab bar | Each card still swipes to Silence on its own. An open iPhone Duo gets this layout too. |
| 18-ipad-sidebar-conversation.png | iPad mini (portrait) | Projects list beside the open Galley session (sidebar + conversation) | The list stays beside the open session; tapping another row switches the right pane. With nothing open the right pane says "Choose a Session". |
| 19-mac-desk.png | Mac | Home on the Desk page: sidebar (Activity, Desk with badge, Studios), summary, ask box, Needs you in two columns (question, plan, command approval), Incoming with place chips, Working chips | The bell-slash icon silences a card; the square-arrow icon opens its session. "Choose a place" is orange when nothing is proposed, and Start there stays disabled until a place is chosen. Plan cards approve a plan to start building. |
| 20-mac-desk-start-there.png | Mac | Start there sheet with New session chosen: place (Geekify, Change), sessions already there, provider tabs, model picker | Continuing an existing session keeps that session's model; the model controls appear only for New session. Start runs in the background with a note on the Desk. |
| 21-mac-studio-page.png | Mac | Studio page (USA Archery): session list with status and thumbnails, filter (All / Needs you / Working), inspector with the latest image | Inspector tabs: Latest, All Images, Files. "Open Session" (bottom right) opens the chat. The list/grid toggle is top right. |
| 22-mac-conversation.png | Mac | Main window: toolbar, Projects sidebar as cards (Galley selected, SDHQ highlighted as needing you), Galley session with plan, collapsed step groups, markdown reply with code and table, composer bar | "4 steps" / "3 steps · 12m 34s" rows expand to the tool calls. The composer's bottom bar holds permissions (Manual), effort slider and the model chip, which opens the model popover. The right column is a rail of per-session tool buttons. The empty band between the toolbar and the first message is as the harness rendered it; not checked against the shipping window. |
| 23-mac-approval.png | Mac | SDHQ session with a pending command approval docked above the composer | "Waiting for your approval below" marks where the turn stopped. Allow / Allow for This Session / Deny. |
| 24-mac-studio-session.png | Mac | A Studio session (2027 Indoor Magazine): Studios column, the Studio's sessions, a reply with a rendered image | Images in replies have Copy image and Annotate (mark up and send back as feedback). |
| 25-mac-command-center.png | Mac | Command Center: two sessions side by side, each with its own message box and settings bar | Clicking a message box focuses that session (blue outline). Layout menu sets the grid; Add session adds a pane. The Codex pane's model chip reads "Claude · gpt-6.1-sol" in this fixture. |
| 26-mac-automation-editor.png | Mac | Automation editor (WordPress updates): on/off switch, Run Now, name, day, time, agent, model, the instructions each run follows | The instructions are the app's built-in WordPress routine template. Run Now shows dimmed in this render. The note at the bottom lists rules every run follows. |
| 27-mac-settings-models.png | Mac | Settings → Models: default Claude model and effort, default Codex model, proxy models | Settings is a separate window; pages are listed down the left in three groups (everyday, Connections, Advanced). |
| 28-mac-conversation-light.png | Mac | Same as 22 in light mode | |

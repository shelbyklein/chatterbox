# Notes in the chat gutter

Authorized: a note icon in Shelby's highlighted space left of the transcript, expanding into a text box and running list. One scoped notebook per project folder, standalone chats by UUID. Mac preferences persistence, including unsaved note drafts. Do not alter transcripts, composer drafts, Studio membership or daemon APIs. Compact tiles excluded. Add and delete saved notes; no external writes. Linear implementation in current session; no subagents. GitHub remains read-only.

- [x] N1 Persist isolated notes/drafts per normalized project or chat.
- [x] N2 Expand/collapse the note control in the left gutter; honor themes and keep transcript usable.
- [x] N3 Verify persistence, scopes and native rendering; build/install Mac without daemon restart.

Acceptance: blank notes rejected; newest note first; notes and draft survive reload; changing chat retains correct notebook; delete only targeted note; card/list working spinner follows provider color. Evidence and visual target: target.svg, native fixture screenshots. Rollback: remove scoped source changes, previous installed app backup; stored preferences retained. No GitHub changes or service activation required.

Checks: Mac xcodebuild passed. Isolated note test passed: project/worktree scope, independent chat, newest-first order, blank rejection, targeted deletion, draft/store reload, unchanged chat records. Native full ChatView icon click expanded the panel (expanded-gutter.png visually inspected). Native cards render provider-colored working spinners (notes-and-spinners.png inspected). Other native empty-chat controls render white in standalone harness, outside this change. Installed app acceptance still user review; source local/uncommitted, no GitHub writes.

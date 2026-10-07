# Finished chats bell

Authorized UI feature: soft in-app notification bell with unread count, click for finished unseen chats, click an entry to open the existing chat. Existing Attention tracks completion transitions and unread marks, but its watching predicate incorrectly counts a selected chat hidden behind Settings/Studios/Automations. Persist unread IDs in AppPreferences; never fabricate old completion notifications on first hydration. No daemon API, OS notification preference changes, or transcript writes. Exclude assistant/archived/missing/running sessions from bell list. Preserve other pending UI work. GitHub read-only.

- [x] B1 Preserve unread completions across launch, correct hidden-page visibility, filter and sort list, safe open action.
- [x] B2 Always-available toolbar bell, count and popover with name/provider/latest final reply/time and empty state.
- [x] B3 Isolated completion/visibility/persistence/navigation tests, native bell/popover render and click, Mac build/install without restart.

Linear current session implementation; no subagents. Scope settled by direct request. Success: unseen completion appears once; open clears only its entry and navigates to correct page; list remains after closing popover; viewed completion not added; reload preserves unread; changing views doesn't mark selected hidden chat read. Deliver local source/tests, inspected render, installed Mac. Rollback scoped files/previous app bundle; retain preferences. Visual target target.svg. Model/effort verified in inherited session record; no lane dispatch. Readiness R1-R13 assessed for this narrowly authorized feature, no external tracking due user's GitHub write restriction.

Verification: Mac build passes. Isolated native test passes completion dedupe, hidden-page visibility, unread store reload, archived/running filters, actual list row click navigation, targeted clearing and persisted clearing. finished-list.png inspected; provider images unavailable in standalone fixture bundle. Final app build includes mark-seen on ChatView appear, covering returning from another page. Toolbar popover/installed display await user acceptance. No daemon restart or GitHub changes. Local changes remain uncommitted.

User extension: show Working sessions in same popover, using provider spinner and elapsed turn time. Existing bell badge stays unread finished count. Working row opens existing chat without stopping/creating turns. Exclude archived/Golem; update live from observed sessions. Verify running-to-finished movement, safe navigation and empty states.

Working extension verified: Mac build passes, isolated native test passes running navigation without stopping turn, archived filtering, running-to-unseen-finished transition and finished targeting. working-list.png visually inspected. Local Mac installed via install.sh; daemon PID 60096 unchanged. No commits/pushes/GitHub writes.

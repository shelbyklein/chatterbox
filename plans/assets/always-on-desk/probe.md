# T1 probe (2026-11-21, read-only)

## ClickUp (API, `CLICKUP_API` secret)
- `GET /user` → Shelby, id 57216908, America/New_York. Workspaces: PlayCase 9013812795, SKD 90131020388, USA Archery 9014281602.
- `GET /team/9014281602/task?assignees[]=57216908&date_updated_gt=<ms>&subtasks=true&include_closed=true&order_by=updated` → 7 tasks updated in 3 days, one page. Fields include id, name, status.status, priority.priority, due_date, date_updated, date_closed, url, text_content, list, assignees.
- `GET /task/{id}/comment` → comments with id, date (ms), user.id/username, comment_text, reply_count. Replies via `/comment/{id}/reply` when reply_count > 0. User id lets the watcher ignore Shelby's own comments.
- Rate limit: 1000/min (`x-ratelimit-*` headers). Polling every 3 min with a handful of comment reads is far inside it.
- A comment updates the task's date_updated, so one `date_updated_gt` query finds tasks to inspect.

## Outlook
- The current Desk checks read USA Archery Outlook through **Codex computer use** driving the Outlook app (`mcp:computer-use/get_app_state`, `mcp:cua_repl/js` in run 3AA9634B), not a connector. Slow, costly, partially verifiable (the Desk's "Outlook not fully verifiable" notes).
- Claude Code here has no Outlook/Microsoft 365 connector loaded (a haiku check listing tools found none; $0.0045, 2 s).
- Microsoft Outlook.app is the **new Outlook** (`IsRunningNewOutlook = 1`): no AppleScript, cloud cache.
- Apple Mail has Exchange info@playcase.gg (EWS) and a stale IMAP account (last mail 2024); **no USA Archery account**.
- Options: add the USA Archery account to Apple Mail and read Mail's local index (no AI, near-instant); Microsoft Graph sign-in (tenant may need admin consent); keep computer use (costly); a claude.ai Microsoft 365 connector (if the org allows).

# Tasks from ClickUp and email: aware of their source, board statuses as milestones

## Summary

Desk tasks that came from ClickUp or an email (most arrive through the morning automation, with
the ClickUp link or the email in the task's note) know their source, and moving the task across
the board is checked against it. Shelby, 2026-11-05.

## Decisions (Shelby, 2026-11-05)

- **Milestones are the board's own statuses:** To do → Working → Needs you → Review → Done. No separate checklist.
- **Gates warn, they don't block:** a card shows in amber when its source disagrees with where
  it is on the board (e.g. the ClickUp task is closed while ours is still Working; ours is Done
  while ClickUp still says In progress; the email thread got a newer reply after we marked Ready).
- **Write-back asks each time:** a move offers a one-tap action ("Set ClickUp to In progress",
  "Mark the ClickUp task complete", "Draft the reply to Lauren"); nothing changes outside
  Chatterbox without the tap.

## Design

- **Source link on the task** (DeskStore TaskRecord): `origin` (Companion.DeskOrigin: kind clickup|email, id, url?,
  title?, status?, checkedAt?, replyFrom?, replyAt?; `source` already names who added it), set when the task is added (the `desk add` CLI and connector
  get `--source clickup:<id or url>` / `--source email:<message id>`; existing notes with a
  ClickUp URL are parsed once).
- **Reading the source** happens through the agents, not a new API client in the app: ClickUp
  and Outlook are reached through the agents' connectors. The morning automation (and a task's
  own thread when it runs) reports each linked task's source status with `desk source <task>
  --status "<status>"`; the service stores it and computes the warning.
- **Write-back** is a button on the card after a move (Mac and phone). Tapping it sends a message
  into the task's thread (or the automation's, for an unstarted task) asking the agent to make that
  change in ClickUp or draft the email; the agent does it with its connector and confirms.
- **Warnings** (amber line on the card, and in the card's About/peek): "ClickUp says Complete",
  "New reply from Lauren since this was marked Ready", with the write-back or "Move to match" as
  actions.

## Tasks

- [x] S1 Service: source on tasks, `desk add --source`, `desk source` status reports, URL parsing of
      existing notes, mismatch rules; tests.
- [x] S2 Board UI (Mac + phone): source badge on cards, amber mismatch line, write-back buttons on
      moves; tests and screenshots.
- [x] S3 Automation run instructions now require source references, titles and verified source URLs on imported Desk tasks, and source-status reports. Applied at run time to existing routines; saved user prompts are preserved. Agent instruction version 19 carries the same rule to existing chats.

## Not changed

The board's columns and rules; ClickUp and email are never changed without Shelby's tap.

## Source URLs on import (Shelby, 2026-11-06)

Request: include a link to the source on the Desk cards shown on the phone. Linear execution in this session, no work threads. Existing Mac and phone source badges already open `origin.url`; the missing path was preserving email links on add. Scope/readiness confirmed from this request and the approved source plan above.

- [x] Add optional `originURL` to the import contract, `desk add --source-url`, and connector `source_url`. Keep source title and reference. Validate web URLs before saving.
- [x] Expose existing report fields as `desk source REF --url URL --task DESK_ID`, allowing a recovered source to attach to one existing task without changing every task with the same reference.
- [x] Instruct agents and every automation run to preserve verified links; never fabricate IDs or URLs, send email or change ClickUp to obtain one.
- [x] Validate service (256 checks), connector (36 checks), automation instructions (55 checks), and CLI payload forwarding. Core `9129261` pushed.
- [x] Parent integration `883f2db` pushed; installed/reopened Chatterbox Dev on Mac. Dev service healthy after 2s (2026-11-06 12:15:38 local).
- [x] Full-suite attempt finished: 98 pass / 12 fail; details and stable reruns in `plans/2026-11-06-validation.md`. Dev phone install attempted but Xcode could not resolve the paired Duo destination (exit 70); no phone install or TestFlight claimed.

Current-data limit: both screenshot tasks have no origin/message ID/URL. The morning report explicitly records null `source_link` and `stable_message_id`, with partial native-Outlook coverage. Read-only native Outlook inspection confirmed the 93ft message identity but exposed no Copy Link command. No real tasks or mailbox data were changed, and no exact email links were invented. Existing missing links remain unresolved until the source can provide them.

Success: a verified email/ClickUp link survives import and is returned in the same Desk payload used by Mac and phone cards; legacy tasks can receive a recovered link narrowly; unsafe links are refused. No new source files or redesigned UI. Rollback: revert the scoped URL/import changes; optional fields remain backward compatible.

Validation note: adding this request during the Studio full run changed sources while empty-chat and Fast Mode were compiling; those original runs are invalid. Stable-source reruns: Fast Mode passes; empty-chat persistence fails `Studio chat is back after relaunch`. Other full-run results remain in `build/studio-suggestion-full-suite.log`. Later Activity and Desk-check requests added more code during this long attempt; focused checks are rerun on those final changes. This is not a uniform-tree full-suite pass.

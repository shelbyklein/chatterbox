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
- [ ] S2 Board UI (Mac + phone): source badge on cards, amber mismatch line, write-back buttons on
      moves; tests and screenshots.
- [~] S3 Automation prompt (agent instructions v17 done; the morning automation's own prompt still to update): add `--source` when putting ClickUp/email work on the Desk, and report
      linked tasks' source status each run.

## Not changed

The board's columns and rules; ClickUp and email are never changed without Shelby's tap.

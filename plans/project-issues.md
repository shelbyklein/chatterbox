# Project issue boards (PlayCase Arcade first)

Shelby, 2026-11-09: "we need an internal issue board for threads to support working on playcase
arcade games." Decisions: inside the project (Mac and phone), stored by Chatterbox (not the repo,
not GitHub); grouped by game, then status; issues start/link threads AND agents file issues;
an issue holds title and notes, screenshots/attachments, priority, type (bug, feature, polish).

## Design

- Store: `ProjectIssueStore` (Core/Chatterbox/Engine/ProjectIssues.swift), `issues.json` and
  `IssueAttachments/<issue>/` in the data folder, keyed by the project's folder. Any project can
  have a board; one with `catalog/games.json` groups issues by its games (General otherwise).
- Status: open, inProgress, review, done. Linked to a thread it follows the thread (working or
  waiting on Shelby: In progress; finished: Review; archived: Done); unlinked it's set by hand.
- Start: a work thread of the project's own session, named "#N title", its first message the
  issue (game, type, priority, notes, attachment paths). Link/unlink an existing project thread.
- Socket op `issues` (list, add, update, delete, link, unlink, start; agents: list and add only,
  filed as their agent); `issues.changed` events; phone: GET/POST /v1/issues,
  GET /v1/issues/attachment (only from IssueAttachments).
- `issue` command (bin/issue): list, add (--game --type --priority --notes --attach), games.
  Agent instructions v20 mention it.

## Tasks

- [x] I1 Service, CLI, phone routes; tests/project-issues (38 checks).
- [x] I2 Mac board: in the project (toolbar/thread sidebar), grouped by game, status columns or
      sections, new/edit sheet with attachments (drop, paste), start/link, live via issues.changed.
- [x] I3 Phone board: from the project's session (About/rail), same groups, add with photos,
      start/link, attachments viewable.

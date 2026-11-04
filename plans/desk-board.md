# The Desk as a board

## Summary

The Desk becomes a kanban board of five columns, left to right:
**To do · Working · Needs you · Ready to mark complete · Done**. It replaces today's stacked
sections (Needs you, Incoming, a Working strip). Built in the `ux-panel` worktree as a separate
test build alongside the UX panel's fixes.

## Decisions (Shelby, 2026-11-04)

- **To do**: requests on the Desk not started yet (today's Incoming). Cards keep the place chip,
  note, Start there (the start step), Change place and Ignore.
- **Working**: sessions running now (an agent mid-reply).
- **Needs you**: sessions waiting on Shelby: approval, plan, questions, a question in a reply
  (today's Needs you, with silence kept).
- **Ready to mark complete**: sessions that finished their reply and ask nothing. Limited to
  sessions not archived whose last reply finished in the last 7 days (otherwise every old idle
  session would land here); sidequests and automation runs left out as today.
  Action: Mark complete. Also Open, and silence (hides it until something new happens).
- **Done**: marking complete archives the session. The column shows sessions archived from the
  board in the last 7 days, with Reopen (unarchive).
- **iPhone**: column tabs at the top with counts (a segmented switcher); one column at a time;
  swipe a card for its main action. **iPad, an open Duo and the Mac**: columns side by side,
  scrolling sideways when they don't fit.
- Starting from the Desk stays in the background (the "Started in X · Open" note).

## Contract

`Companion.Desk` gains `ready: [DeskReady]` and `done: [DeskDone]` (optional, so older phones and
services keep working); `working` gains enough to show a card (title, place, last activity).
New `POST /v1/desk/complete { chatID }` (archives, records it as completed from the board) and
`POST /v1/desk/reopen { chatID }`; socket `desk` actions `complete` and `reopen`.

## Tasks

- [ ] B1 Service: ready/done derivation, complete/reopen routes and socket actions, desk.json
      records board completions. Extend scripts/test-desk.sh.
- [ ] B2 iPhone/iPad: board with column tabs (phone) and side-by-side columns (wide); card
      actions; UI tests against the fixture.
- [ ] B3 Mac: board page; render test.
- [ ] B4 Screenshots to design/desk-board/; then into the panel's re-score.

## Not changed

Sessions, Studios, projects, the start step, silencing, the `desk` CLI and connector `propose_work`.

## Rollback

Revert the commits; older clients ignore the new fields.

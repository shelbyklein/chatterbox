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

As built: `DeskReady { id (the session), title, place, subtitle, text (its last reply's first
sentence), finishedAt }`, `DeskDone { id, title, place, subtitle, completedAt }`, `DeskWorking`
gains `activity` (what it's doing, as the session list says it) and `since` (its reply's start).
Bodies are `DeskSessionRequest { chatID }`; both answer the Desk. Complete refuses a working
session (409) rather than stop it. Silencing a ready session is `POST /v1/desk/silence` with its
id as both `chatID` and `id` and its `text`; it hides it until its last reply changes. desk.json
gains `completions` (chatID, completedAt; Done is the last week's whose sessions are still
archived). Ready also leaves out sessions with background work, and shows at most 50.

UX panel fixes (design/ux-panel/SUMMARY.md): `DeskWaiting` gains `detail` (an approval's exact
command, so the Desk's approval card shows it); new `POST /v1/desk/unsilence` (socket `desk` action
`unsilence`, app only), the silence body, answering the Desk: Undo after silencing and the
"N silenced" row at the foot of Needs you. Allow for Session from the Desk goes through the
session's own approval call (`approvedForSession`), as before on the session's card.

## Built choices

- The Desk tab and toolbar badge still count Needs you + To do: Ready waits on nothing urgent,
  and counting it would keep the badge lit all week.
- Phone: tabs (count over a short name: To do, Working, Needs you, Ready, Done) pinned above the
  cards; it opens on Needs you when something does, else To do, then stays on the column picked
  (adding from the ask box switches to To do). Swipe left: Silence (Needs you), Complete (Ready).
- Wide (iPad, open Duo) and Mac: 320-point columns; the board starts scrolled to Needs you when it
  has something and isn't fully on screen. Wide phones/iPads don't swipe cards (a sideways drag
  scrolls the board); Silence and Mark Complete are on the buttons and the long-press menu.
- Project sessions are included in Ready: marking one complete archives the project's session.

## Tasks

- [x] B1 Service: ready/done derivation, complete/reopen routes and socket actions, desk.json
      records board completions. Extend scripts/test-desk.sh.
- [x] B2 iPhone/iPad: board with column tabs (phone) and side-by-side columns (wide); card
      actions; UI tests against the fixture.
- [x] B3 Mac: board page; render test.
- [ ] B4 Screenshots to design/desk-board/; then into the panel's re-score.

## Tasks linked to threads (Shelby, 2026-11-04)

Not every thread is a task. A Desk request stays a **task** after it starts, linked to its thread,
and moves across the board with that thread's state.

- One task per thread, one thread per task. Linking a thread that already carries an open task
  asks first and unlinks the old task (it goes back to To do).
- Starting a task (new session or Continue in) links it. Also: "Link a thread" on a To do card
  (sessions in its place, best matches first, as the start step ranks them), and in a session's
  menu "Make this a task" (a new card, already linked) or "Link to a task" (pick an open one).
  Unlink from the card's menu (the task goes back to To do).
- Columns: To do = unlinked tasks; Working / Needs you / Ready = linked tasks by their thread's
  state; Done = completed tasks (last 7 days). Mark complete archives the linked thread (Reopen
  unarchives it and reopens the task).
- Threads with no task appear only when they need you (approvals, questions), as today, marked
  as not a task, with "Make this a task". They no longer appear in Working or Ready.
- A linked thread that's archived or deleted outside the board: the task goes to Done (archived)
  or back to To do (deleted).
- Defaults chosen by Claude where Shelby didn't answer: unlinked threads in Needs you only;
  linking from the card and the thread; complete archives the thread.

## Not changed

Sessions, Studios, projects, the start step, silencing, the `desk` CLI and connector `propose_work`.

## Rollback

Revert the commits; older clients ignore the new fields.

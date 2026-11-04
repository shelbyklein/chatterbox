# Work threads: one front thread per project, fresh threads behind it

## Summary

Shelby likes one context window per project, but one long thread fills up: it gets summarized
(detail lost), everything competes for attention, and it's one lane. Keep the project's main
thread as the **front thread** Shelby talks to; real pieces of work go to **work threads**:
fresh Chatterbox threads in the same project, each linked to a **task** on the Desk board, that
report their result back to the front thread. Folds in the task-to-thread linking from
plans/desk-board.md ("Tasks linked to threads").

## Decisions (Shelby, 2026-11-04: "sure lets do it")

- Projects stay one window for Shelby; the front thread stays short (decisions and status).
- Work threads are real threads (survive restarts, visible on the board, can be opened).
- Built and tried in Chatterbox Dev first; the real app gets it when Shelby says ship.
- From plans/desk-board.md: one task per thread; unlinked threads show only in Needs you;
  Mark complete archives the thread; link from the task card or from the thread.

## Today (code evidence)

- Sidequests already make a child thread and post its answer back: `RuntimeServer.swift` ops
  `sidequest` (ui, or an agent from its own running chat) and `returnSidequest`;
  `record.sidequestOf`; `bin/sidequest`. A sidequest reads the whole parent conversation and
  runs on the other agent.
- The Desk forgets a request once started (DeskStore removes it); the board's Working / Ready /
  Done show every session.

## Target

- **Tasks** persist on the Desk (desk.json): text, place, note, source, linked thread (0 or 1),
  completedAt. Columns: To do = unlinked; Working / Needs you / Ready = by the linked thread's
  state; Done = completed in the last 7 days. Threads with no task appear only in Needs you.
- **Work threads**: a thread in the same project (same folder; Studios too) with
  `workOf` = the front thread, its own task (linked, place = the project), started with a
  **brief** (what to do, what's decided, which files/plans to read), not the front thread's
  transcript. Same agent and model as the front thread unless chosen.
- **Report back**: when the work thread finishes (or calls `work report`), its result arrives in
  the front thread as a message ("Work thread <name> finished: …", with Open), like a sidequest's
  answer; its task moves to Ready.
- **Agents start them**: `bin/work` (`work start "TITLE" --brief TEXT [--agent claude|codex]
  [--model M]`, `work list`, `work report "TEXT"` from a work thread), allowed from the agent's own
  running front thread, like `sidequest`. The front thread's instructions say when to use one
  (a piece of work that needs more than a few steps or many files).
- **Shelby starts them too**: "Start a work thread" in a thread's menu (Mac and phone) and from a
  To do card (Start → "New work thread for <project>").
- **In the front thread**: a compact Work strip (each work thread with its state: Working, Needs
  you, Ready, Done; tap to open). **In a work thread**: a header "Work for <front thread>" with a
  link back.
- **Linking by hand**: "Link a thread" on a To do card, "Make this a task" / "Link to a task" /
  "Unlink" in a thread's menu.

## Tasks

- [ ] W1 Service, tasks: desk.json tasks with links; start links instead of removing; link,
      unlink, make-task routes and socket actions; board derivation tasks-only for Working /
      Ready / Done; archived or deleted threads move their task (Done / back to To do).
      Backward compatible. test-desk.sh.
- [ ] W2 Service, work threads: `workOf`; socket op `work` (start, list, report) with the
      sidequest permission rule; the brief as the first message; report back into the front
      thread on finish or `work report`; companion routes for the phone. test.
- [ ] W3 `bin/work` (installed with the bundle's bin like desk/sidequest), and the front-thread
      instruction in prompts/.
- [ ] W4 UI, Mac and phone: Work strip, work-thread header, start actions, task linking on cards
      and in thread menus, board shows tasks only (plus unlinked Needs you). Tests and screenshots.
- [ ] W5 Install to Chatterbox Dev (Mac and Dev phone app); try a front thread starting two work
      threads in Dev.

## Not changed

Sidequests (still the other agent, still read the conversation); sessions' own data; Studios'
and projects' structure.

## Rollback

Revert the commits; desk.json's new fields are ignored by older builds; work threads stay as
ordinary threads.

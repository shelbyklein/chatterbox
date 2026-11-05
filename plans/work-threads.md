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

- [x] W1 Service, tasks: desk.json tasks with links; start links instead of removing; link,
      unlink, make-task routes and socket actions; board derivation tasks-only for Working /
      Ready / Done; archived or deleted threads move their task (Done / back to To do).
      Backward compatible. test-desk.sh.
- [x] W2 Service, work threads: `workOf`; socket op `work` (start, list, report) with the
      sidequest permission rule; the brief as the first message; report back into the front
      thread on finish or `work report`; companion routes for the phone. test.
- [x] W3 `bin/work` (installed with the bundle's bin like desk/sidequest), and the front-thread
      instruction in prompts/.
- [x] W4 UI, Mac and phone: Work strip, work-thread header, start actions, task linking on cards
      and in thread menus, board shows tasks only (plus unlinked Needs you). Tests and screenshots.
- [x] W5 Install to Chatterbox Dev (Mac and Dev phone app); try a front thread starting two work
      threads in Dev. Done 2026-11-04: installed (Dev service restarted on it, the real one
      untouched), Dev phone app on Shelby's Duo. In Dev's project "Work threads try-out", its
      Claude ran `work start` twice (`which work`: Dev's bundle); both work threads wrote their
      file, reported back into the front thread, which carried on, and both tasks sit in Ready.

## Decided (Shelby, 2026-11-04, before building)

One task per thread (linking a thread that carries an open task asks first and sends the old one
back to To do); threads with no task show only in Needs you; Mark complete archives the linked
thread (Reopen unarchives it and reopens the task); work threads get a brief, on the front
thread's agent and model unless chosen; the result posts back into the front thread when the
work thread finishes its reply (or calls `work report`), and its task goes to Ready; agents start
work threads only from their own running front thread (like sidequest); one level only.
Migration: desk.json's requests become tasks to do; existing sessions are not made tasks.

## Chosen while building (2026-11-04)

- **Storage.** desk.json gains `tasks` (id, text, source, createdAt, proposed, note, chatID,
  linkedAt, completedAt) and keeps writing `requests` as the tasks to do, so an older build still
  sees To do. `completions` (the board's sessions marked complete) is no longer read: those were
  sessions, not tasks.
- **Board.** To do: tasks not linked, or linked to a thread that's gone (until its deletion,
  `chat.deleted`, unlinks it for good). Working: a task's thread running or with background work.
  Ready: a task's thread idle and asking nothing, however long ago it finished (no week window, so
  a task never falls off the board; "No reply yet." when it hasn't answered). Done: tasks whose
  thread is archived (from the board or elsewhere; unarchived elsewhere, the task is open again),
  for a week, then dropped. A deleted thread's done task goes with it.
- **A project's Start is a work thread.** Starting a To do task in a project makes a work thread
  of the project's session (its front thread), named from the request, with the request (and
  note) as its brief; the project's session is told, and hears the result. Studios and loose
  sessions start as before. The start step says "New work thread for <project>".
- **Work threads are Sidechats** of the front thread (`sidechatOf`, same folder, Studio or
  project), plus `workOf`, `workReported` and `workReportedAt`. They get no parent context: the
  framing (`<work_thread>`) goes with the brief, which is the first message. Their task is named
  from the title, in the front thread's place, from the agent ("claude"/"codex") or "you".
- **Reporting.** Each finished reply not yet reported goes to the front thread
  (`<work_result>`, shown as "Work thread "X" finished", with Open), unless the thread waits on an
  approval or questions, or reported with `work report` during that turn (the reply ending it is
  then only marked reported). Later replies (Shelby carrying on in it) report too. An archived
  front thread isn't woken; the work thread notes it. Work threads aren't archived when they
  report: Mark complete does that.
- **Done means nothing left running (2026-11-04, after two early "I'll be notified…" results).**
  A turn that ends while a background command or subagent it started still runs (the session's
  `backgroundTasks`, Claude's and Codex's alike) isn't reported: `record.workPendingSince` is set,
  the task stays Working (Work strip, board, `work list`, phone), and the strip shows its latest
  status line (`WorkThread.status`, the step it's on or what it said last) without waking the
  front thread. The turn that ends with nothing running reports its reply. Safety net: the
  service's 30-second idle sweep (`ConversationRuntime.reportIdleWork`) reports the newest reply
  once a pending work thread has sat idle, nothing running, for 30 minutes
  (`ChatSession.workIdleReport`). `work report` still goes at once; "during this turn" now means
  since the previous turn ended, so a background run's later result still reports.
  `work start` waits 90 s for a busy service, then looks for the thread in `work list` before
  calling it a failure.
- **Permission.** Socket op `work`: `list` from any session; `start` from the app, or an agent
  from its own front thread mid-reply (not a sidequest or automation run); never from a work
  thread (`nested_work`, for the app too); `report` only from a work thread (`not_work_thread`),
  an agent only while it's working. Desk `link`, `unlink`, `makeTask` are the app's (and the
  phone's), not agents'.
- **Dev chats find `work`** (and desk, sidequest) in Chatterbox Dev's own bundle: its agents'
  PATH starts with `Contents/Resources/bin` (BinaryLocator.devBin). The real app links `work`
  into ~/.local/bin at the next ship (install.sh).
- **UI.** Mac: a Work strip across the top of a front thread (chips: name and state; click
  opens), a banner in a work thread ("Work for "X"", Open X), a Start a Work Thread button in the
  column of buttons and in the session menu (name, brief, agent), and the session menu's Make
  This a Task / Link to a Task / Unlink. Desk cards show their task, Needs you marks "Not a task"
  with Make this a task, To do cards have Link… (every thread in the place; one carrying a task
  asks first), task cards' menus Unlink. Phone: the same, the strip and header above the
  transcript, Start a Work Thread as a sheet, Link a Thread as a sheet.
- **Instructions.** Every session's agent instructions gain a Work threads paragraph (when to
  start one, what a brief needs, that results come back); `instructionsVersion` 13 tells chats
  already running.

## Contract (as built)

- `ChatSummary.workOf`; `ChatDetail.work: [WorkThread]` (a front thread's, newest first, done
  ones for a week) and `workOfTitle`. `WorkThread { id, title, state (working, needsYou, ready,
  done), task, backend, updatedAt }`.
- `GET /v1/chats/<id>/work` → `[WorkThread]`; `POST /v1/chats/<id>/work` (`WorkStartRequest {
  title, brief, agent?, model? }`) → the work thread's ChatDetail (409 from a work thread).
- `Desk.linked: [DeskTask { id, text, chatID, completedAt }]`; `DeskWaiting`, `DeskWorking`,
  `DeskReady`, `DeskDone` gain `task` and `taskText`; `DeskThread.task` (the open task it
  carries); `DeskStartRequest.replace`.
- `POST /v1/desk/<task>/link` (`DeskLinkRequest { chatID, replace? }`, 409 when the thread
  carries another open task), `POST /v1/desk/<task>/unlink`, `POST /v1/desk/task`
  (`DeskTaskRequest { chatID, text? }`), `GET /v1/desk/<id>/threads?place=…&all=1`; socket `desk`
  actions `link`, `unlink`, `makeTask`, `threads` with `all`; socket op `work` (start, list,
  report). All answer the Desk unless said.
- `bin/work`: `work start "TITLE" --brief TEXT|- [--agent claude|codex] [--model M]`,
  `work list`, `work report "TEXT"`, each with `--chat ID`.

## Not changed

Sidequests (still the other agent, still read the conversation); sessions' own data; Studios'
and projects' structure.

## Rollback

Revert the commits; desk.json's new fields are ignored by older builds; work threads stay as
ordinary threads.

## Next: open work threads beside the front thread (Shelby, 2026-11-04)

On the Mac, opening a work thread (or a sidechat) from the front thread no longer replaces the
view: it opens as a **peek panel**, a rounded floating card on the right side of the front thread
(over the thread sidebar's space), showing that thread live with its own composer, approvals and
status, plus "Open in full" and close. Several open as tabs in the card; Esc closes it. The front
thread stays readable and typeable. Clicking a work thread in the sidebar list (or the Desk's
"Open") still opens the full view. Starts after the thread-sidebar work lands (same files).

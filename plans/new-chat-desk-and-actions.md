# New threads on the Desk, and action buttons under replies

Shelby, 2026-11-04. Built in Chatterbox Dev first.

## Put on the Desk (new threads)

- **Where:** the Mac's New Session sheet (Chats, a Studio, and now a project's New Sidechat,
  which asks through the same sheet) and the phone's New Chat sheet. A toggle, off by default.
- **What it does:** the new thread carries a Desk task (DeskStore `makeTask`, as Make This a
  Task), placed where the thread was made, source "you". The task has `followsThread`: it is
  named after its thread. That means the name given in the sheet, or else the first message's
  first line (the same line a "New chat" takes as its title; for a Sidechat, which keeps
  "Sidechat · X", the line up to 80 characters). After that, renaming the thread renames the task (`DeskStore.threadName`,
  applied in `reconcile`).
- **Contract:** `NewChatRequest.desk: Bool?` (phone, `POST /v1/chats`);
  `DeskTaskRequest.follow: Bool?` (socket `desk` action `makeTask`, and `POST /v1/desk/task`).
  Older services ignore both: the chat is made, without a task (phone) or with a fixed-name
  task (Mac). The Mac creates the session first (the `create` command), then asks for the
  task, retrying a "gone" answer for up to 1.5 s while the service catches up.

## Action buttons (```actions)

- An agent ends a reply with a fenced block, one button per line, `Label | the message it
  sends` (a bare line is both; at most 5). Rendered by `MarkdownText` (Mac and phone) as a
  row of buttons, like ```draft cards.
- A button only sends its message into the same thread, through the normal send path, so it
  shows as Shelby's message. The app runs nothing itself.
- Only the newest reply's buttons are live (`ReplyActions.state`): once a message follows
  they're used (the one sent is ticked, with "Sent"); once another reply follows they're
  stale. Nothing is stored: it's read from the transcript.
- The agents hear about it in `Prompts.agentInstructions` (instructionsVersion 14): 1–3
  obvious next steps, never a destructive or outward-facing step without saying so in the
  label. AGENTS.md asks for a Ship button after a Dev delivery.

## Tests

`scripts/test-desk.sh` (new chat with desk, naming, renames, Sidechat, socket follow),
`scripts/test-reply-actions.sh` (parse, state, a real click sends once, used state;
screenshots), `tests/mobile-home-nav` `testReplyActionButtons` and the Desk toggle in
`testNewChatPicksSettingsFirst`. Screenshots: design/actions/.

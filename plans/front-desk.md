# The Desk: a front desk for Chatterbox

## Summary

A **Desk** home in the app (iPhone/iPad first tab, a Mac home page): what needs Shelby, work
waiting to be placed, and what's working. The Desk never does work itself; starting a request
opens a session in its Studio or project, so work stays in its compartment. Ideas borrowed from
DeepSeek's dsh-superagent prototype: a front desk that routes, isolated workers, speak only when
someone must act, a healthy state takes no space.

## Decisions (Shelby, 2026-11-03)

- In the Chatterbox app, not a separate app (Golem's lesson).
- Planner defaults for version 1: iPhone/iPad and Mac; sources are typing at the Desk and Claude
  (the connector's `propose_work`); email arrives through Duet; GitHub and other intake rules
  with a record-only trial run are version 2.

## Target

- **Needs you**: sessions waiting on Shelby with what they ask (approval, plan, questions, a
  question in a reply); approve or deny in place, open, or silence (iPhone/iPad: swipe left or
  long-press; Mac: the bell button or right-click). Cards are named as the session lists name
  them (worktree branch, else project, else title), the session's own title under a project's.
- Wide (iPad, an open iPhone Duo, a Mac page over 1100 points): Needs you and Incoming in two
  columns.
- **Incoming**: requests with a proposed place (Studio or project, from each one's
  instructions or brief) and an optional note: Start there, Change place, Ignore.
- **Start there** opens a step (iPhone/iPad: a sheet; Mac: a popover): the place (Change),
  "Continue in" sessions already there that look like the same work (a clear match is chosen)
  and New session, with a new session's agent and model as New Chat would start one there.
  What starts runs in the background: the Desk stays, with a "Started in" note to open it
  (Shelby, 2026-11-03).
- **Working**: one quiet line of running sessions.
- Nothing waiting: "Nothing else needs you."
- **Ask box**: type what needs doing; the Desk proposes where before anything starts.

## Contract (Shared/CompanionAPI.swift: Companion.Desk and friends)

- Service owns the state: `desk.json` in the data folder (incoming requests and silences; Needs
  you and Working are derived from sessions). A silence is one waiting thing (chat + approval,
  plan or questions item; for a reply, the reply item + its question): off Needs you, the
  counts and badges on every device, still pending in its session; something new from the same
  session shows again; silences that match nothing waiting are pruned. `Desk.silenced` lists
  them (the Mac filters its own sessions' approvals with it).
- Phone and connector, companion HTTP: `GET /v1/desk` → `Desk`; `POST /v1/desk`
  (`DeskAddRequest`) → `Desk`; `POST /v1/desk/<id>/start` (`DeskStartRequest`: `place`,
  `agent`, and optionally `model`, `effort`, `openModel`, or `continueChat`) → `ChatDetail` of
  the started session (its first message is the request's text), or with `continueChat` of that
  session (the request is its next message, queued while it works; nothing new starts);
  `GET /v1/desk/<id>/threads?place=<id|loose>` → `[DeskThread]` (sessions in that place sharing
  the request's words, best first, at most five, `match` "clear" or "possible");
  `GET /v1/new-chat-options?project=<id>` gives a project's new Sidechat's options; `POST /v1/desk/<id>/ignore`
  → `Desk`; `GET /v1/desk/places` → `[DeskPlace]`; `POST /v1/desk/silence`
  (`DeskSilenceRequest { chatID, id, text? }`) → `Desk`.
- Mac app, service socket: operation `desk` with `action` get | add | start | ignore | silence |
  places | threads (`id`, `place`) | options (`place`, `picks`) and the same bodies; the service
  publishes `desk.changed` when the Desk changes. Agents may get, places, threads, options, add.
- Connector: `propose_work(text, place?, note?)` puts a request on the Desk; `list_sessions`
  stays as is.

## Tasks

- [x] T1 Service: DeskStore (desk.json), place proposal (Studios and projects), Needs you and
      Working, routes, socket operation and event, connector `propose_work`. Test.
- [x] T2 iPhone/iPad: Desk tab first, sections, ask box, Start there / Change place / Ignore,
      approve and deny in place. UI test against the fixture server.
- [x] T3 Mac: Desk home page with the same sections and actions. Render test.
- [ ] T4 Integrate, install, service restart, TestFlight; live check.

## Not changed

Sessions, Studios, projects and routing rules (the connector's start_session still requires a
place). No email watching in the app.

## Rollback

Revert the commits; delete `desk.json`.

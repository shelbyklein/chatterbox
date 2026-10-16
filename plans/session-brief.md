# Session Brief and tool context in handoffs

Issue: https://github.com/shelbyklein/chatterbox/issues/45

## Summary

A session can carry a short **Brief**, the assignment, the tools to use and the key files,
that both agents always get. Agent switches also tell the incoming agent which tools the
session has been using, and warn when it doesn't have an MCP server the other agent used.

## Problem

When a session switches between Claude and Codex, the incoming agent gets a transcript of
the conversation but not of the tools behind it. `ChatSession.transcript`
(`Core/Chatterbox/Engine/ChatSession.swift`) lists user messages, final replies, plans,
answered questions, shell runs and images; tool rows fall to `default: break`. A thread
driving InDesign through its MCP then continues on the other agent with scripts or PDF
tools instead. Tool rows also store only a readable label (`DisplayItem.text`, e.g.
"Running `rg …`"), not which tool or MCP server ran, so there is nothing to summarize yet.

The Notes panel (top right, `ChatNotes`) is private to this Mac and never sent to agents.

## Target

- **Brief pill** in the session's top-right row, beside the other buttons (decision: a
  separate pill, not part of Notes). Empty: "Brief". Set: its first line, truncated. Click
  opens an editor popover: a text box, Save, Clear. Same on iPhone, in the session's menu.
- Both agents get the Brief in their instructions at session start, after a switch and in a
  fresh session (`Prompts.fullInstructions`). An edit mid-session goes once, with the next
  message, as `<session_brief>` in an `<app_note>` that replaces the earlier version
  (`sentBrief`, like `sentStudioInstructions`). Clearing sends "no brief now; ignore the
  earlier one".
- Handoffs (agent switch) end with one line: `Tools used: indesign MCP (set_text ×32,
  place_image ×14), Bash ×3`. Counted from tool rows that record their tool (new
  `DisplayItem.tool`); older rows without it are left out. No inputs or outputs.
- On a switch, if the leaving agent used an MCP server the incoming agent has neither in
  its own config nor in Chatterbox's Tools for this session, the session gets a notice:
  "Codex doesn't have the indesign MCP server. Add it in Settings → Tools, or import it."

## Settled decisions

- Brief is its own pill (user, 2026-10-16). Notes stay private and unchanged.
- All three parts in scope (user, 2026-10-16).
- Brief is stored on the session record, so the service, both agents and the iPhone share it.

## Success criteria

1. A Brief can be set, edited and cleared per session on Mac and iPhone; it persists.
2. A new session, a switch and a fresh session each start with the Brief in instructions.
3. Editing it mid-session sends exactly one update with the next message; no edit, nothing.
4. A switch's handoff includes a compact tools-used line built from recorded tool rows.
5. A switch away from an agent that used an MCP the other lacks posts the notice.
6. `agentInstructions` explains `<session_brief>`; `instructionsVersion` is bumped.

## Deliverables

- `Models.swift`: `ConversationRecord.brief`, `sentBrief`; `DisplayItem.tool`.
- `ChatSession+Claude.swift`, `ChatSession+Codex.swift`: record `tool` on tool rows; send
  the brief update with messages.
- `Prompts.swift`: brief in `fullInstructions`, `briefUpdate`, tools-used line in `handoff`,
  tag documented, version bump.
- `ChatSession.swift`: `toolsUsedSummary`, `takeBriefUpdate`, `setBrief`; the notice on switch.
- Mac `BriefButton` in the session's top-right row; service `metadata` carries `brief`.
- iPhone: brief in the session summary and an editor; `CompanionServer` route to set it.
- Test `scripts/test-session-brief.sh`: instructions, one update, tools line, notice, render.

## Tasks

- [ ] T1 Record `tool` on new tool rows (Claude names, Codex `mcpToolCall` server/tool, commands). Check: unit test sees the names.
- [ ] T2 `toolsUsedSummary` + tools line in handoffs. Check: a handoff for a fixture lists tools with counts.
- [ ] T3 Brief on the record, in `fullInstructions`, and sent once as an update. Check: unit test of instructions and update rules.
- [ ] T4 Mac Brief pill and editor; service carries `brief`. Check: rendered pill set and empty; edit persists through the service.
- [ ] T5 iPhone Brief view and route. Check: simulator test sets a brief and the fake Mac records it.
- [ ] T6 MCP availability notice on switch. Check: unit test with a fixture config.
- [ ] T7 Install, TestFlight, manual check: a Claude thread using an MCP, switch to Codex, Codex keeps using it.

## Scope boundaries

Not changed: Notes, Studio instructions, how tools are configured (#44), the transcript's
other parts. Older tool rows aren't back-filled from their labels.

## Test plan

Headless engine test (`-D CHATTERBOX_HEADLESS`, like `test-sidequest.sh`) for T1–T3 and T6;
render test for the pill (Mac); iPhone UI test with the fake Mac for T5; manual T7.

## Rollback

New record fields are optional; reverting the commits leaves saved sessions readable.

## Work preparation

- Scope: confirmed by the user's answers (separate pill; all three parts).
- Mode: linear, this session (Claude Opus 5.5); one connected change across shared files.
- Readiness: passes; no open questions.

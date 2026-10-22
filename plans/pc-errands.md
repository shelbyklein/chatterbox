# PC errands: "go do that on the PC", including Photoshop

## Summary

From any session, hand a task to Shelby-PC and get the answer back, like a sidequest:
the agent runs `pc-errand "TASK"` when you say "do that on the PC" (or you pick **Do on
Shelby-PC…** in the session menu). A Sidechat opens beside the session, set to Run on
Shelby-PC and caught up on the conversation; its answer returns to the session and its
files are copied to the Mac. PC agents can drive **Photoshop** on the PC: by scripting
first, and by screen control (see the screen, click, type) for what scripts can't do.

## Problem (now)

- A whole session can run on the PC (`record.runOn`, `ChatSession+PC.swift`), but a session
  on the Mac can't send one task there and carry on. Sidequests (`bin/sidequest`,
  `ChatSession+Sidequest.swift`) always switch agents and stay on the session's machine.
- PC agents run through `ssh desktop` → `chatterbox-worker.js`, in Windows session 0 (checked
  2026-10-22: `SessionId` 0). Session 0 has no desktop, so they can't reach an app on the
  screen. Photoshop (Beta) is installed at `C:\Program Files\Adobe\Adobe Photoshop (Beta)`.
  Ollama hit the same wall and starts at logon instead (scheduled task "Chatterbox Ollama").

## Decisions (Shelby, 2026-10-22)

- Trigger: an agent command **and** a session-menu item.
- Photoshop: **scripting first, screen control as the fallback**.
- Defaults (planner): the errand runs on the session's own agent (Claude stays Claude); the
  Sidechat is temporary, like a sidequest; the PC must be logged in (it needn't be watched).

## Target flow

```
Mac session ──pc-errand "Export the logo at 3 sizes" --file logo.psd──▶ chatterboxd
   │                                                                       │ uploads files
   │                               Sidechat (Run on Shelby-PC, same agent) ◀┘
   │                                 └─ PC agent ─ chatterbox-desktop ps-script export.jsx
   │                                                 └─ desktop helper (session 1) ─ Photoshop
   ◀── answer + files (~/Chatterbox/PC/<errand>/) ──┘
```

## Deliverables

1. **`pc-errand` command** (`bin/pc-errand`, linked into `~/.local/bin` like `sidequest`):
   `pc-errand "TASK" [--file PATH …] [--agent claude|codex]`. Service operation `pcErrand`:
   a sidequest-style record (`sidequestRecord`) with `runOn = "pc"`, the same agent unless
   asked, the files uploaded to the PC first and named in the task. The answer returns
   through the existing sidequest return path.
2. **Session menu: Do on Shelby-PC…**: the sidequest form, with the task, files and agent.
   Hidden when the PC isn't set up; disabled while it's unreachable.
3. **Photoshop for PC agents: Slippy.** The worker adds Slippy's Photoshop MCP (and
   Illustrator's, when it's listening) to the agent it starts, reading the token on the PC,
   so it never crosses to the Mac. Claude: `--mcp-config`; Codex: `mcp_servers` config.
4. **Desktop helper on the PC** for screen control (`deploy/pc-worker/chatterbox-desktop.js`,
   scheduled task at logon, session 1, localhost only, user-only token file) and its command
   for PC agents, `chatterbox-desktop`: `screenshot` (PNG to the workspace), `click X Y`,
   `type TEXT`, `key COMBO`, `window TITLE` (focus); `jsx FILE` as a last resort for
   Photoshop scripting Slippy doesn't cover.
5. **PC agent instructions** (`pcInstructions`): the helper and when to use it (scripts
   first; screenshots to check; screen control only when scripting can't).
6. Agent instructions for every session: `pc-errand` exists and when to use it.

## Tasks

- [x] T1 Prove the reach (2026-10-22). From the desktop session (one-time scheduled task,
      `/IT`): COM `Photoshop.Application.BETA` ran a JSX file ("27.12.0 | documents: 0") and a
      screenshot was taken (1920×1080). Better: **Slippy's Photoshop MCP** (the panel in
      Photoshop, `127.0.0.1:7332/mcp/<token>`, token in `%APPDATA%\slippy\Photoshop\token`)
      answers from an SSH (session 0) shell: initialize 200, 16 tools (document_open/export,
      layer_*, text_create, ps_batchplay, …). So Photoshop goes through Slippy, not raw JSX.
- [x] T2 Slippy for PC agents: worker 2 adds the servers that are listening (token read on
      the PC; Claude via a user-only `--mcp-config` file, Codex via `-c mcp_servers…`; none
      for open models). Live 2026-10-22: Claude on the PC called `slippy_status` →
      "Photoshop 27.12.0 is reachable through Slippy 1.2.1's native plug-in".
- [x] T2b Desktop helper: `chatterbox-desktop` (worker folder, on PC agents' PATH, worker 3).
      No resident server: each command runs one action in the desktop session through a
      one-off interactive scheduled task, launched windowless (desktop-run.vbs). Live: windows
      list and screenshot from SSH.
- [x] T3 Screen control. Live: `open` a scratch file, `type … --in "typing.txt - Notepad"`,
      `key ctrl+s --in …` saved "hello from chatterbox (1+1)"; `--in` an absent window refused.
      Found and fixed on the way: cmd ate `^` (keys are now `ctrl+s`), typing without a target
      went to the front window (now `--in` focuses and checks first), `--in` clashed with
      PowerShell's own parameters (arguments are now read raw).
- [x] T4 Service `pcErrand` + `pc-errand` (bin/sidequest by another name) + uploads; files
      copied back before the answer, PC paths rewritten to the Mac copies. Test:
      `scripts/test-pc-worker.sh` (stand-in ssh and scp).
- [x] T5 "Do on Shelby-PC…" in the session's right-click menu and as an icon beside
      Sidequest; form: task, files (picker or drop), agent. Render: `scripts/test-pc-errand-form.sh`.
- [x] T6 Instructions: every session learns `pc-errand` (version 11); PC agents learn Slippy
      first, then `chatterbox-desktop` with `--in`.
- [ ] T7 Live: from a Mac session, "do that on the PC: open logo.psd in Photoshop, export a
      PNG at 512 px" → the PNG shows in the session.
- [ ] T8 Install, service restart, worker redeploy to the PC.

## Not changed

Running a whole session on the PC (Run on) stays as is. Screen control for Mac sessions, and
any app other than Photoshop beyond the generic screen commands, are out of scope.

## Risks

- The PC must be logged in; a locked screen blocks screen control (scripting may still work).
- A Photoshop dialog can block a script: the helper times out and screenshots it.
- Another session is working on the PC worker (`pc-use` worktree): coordinate before editing
  `deploy/pc-worker/` or `scripts/pc-worker-setup.sh`.

## Rollback

Remove the scheduled task and `chatterbox-desktop.js` on the PC; revert the commits. No data
changes.

## Work preparation

- Scope: confirmed by Shelby's answers (command + button; scripting and screen control).
- Mode: linear, this session (Claude Opus 5.5): one connected change; T1 decides T2's method.
- Readiness: ready; the only unknown (Beta COM) is T1's own check, with a fallback named.

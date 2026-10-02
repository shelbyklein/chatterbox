<!-- vm-handoff-2026-10-02 -->
# Hybrid VM workflow: browse in the agent computer, hand files to the Mac

Issue: https://github.com/shelbyklein/chatterbox/issues/22 · Tracker Trapper: off (see Work preparation)

## Summary
Agents that need a browser (Geekify picking photos from Dropbox) currently take over Shelby's Mac Chrome. Chatterbox already has a separate agent computer (a Docker Linux desktop with Chromium), but only Golem can use it, nothing it downloads can reach the Mac, and it can't open local SKD Studio previews. This plan lets any project chat browse in the agent computer, hand a downloaded file to its project on the Mac, and open a local preview Shelby has explicitly enabled.

## Problem (current behavior, with evidence)
- **Mac Chrome is driven directly.** The Geekify chat runs `/tmp/geekify-dropbox.py`, which uses `osascript` to find the Dropbox tab in Google Chrome and run JavaScript in it (observed 2026-10-02 15:19–15:24), taking over Shelby's own browser and signed-in sessions.
- **Only Golem gets the computer's browser.** `ChatSession.dotMCPConfig` / `dotCodexConfig` (`Chatterbox/Engine/Dot.swift`) add the `computer` MCP server only for the assistant.
- **No way out of the VM.** `docker inspect chatterbox-dot` shows a single mount, the profile volume `chatterbox-dot-profile → /home/dot/profile`. Downloads stay inside the container.
- **Local previews are unreachable.** SKD Studio serves sites on IPv6 loopback only (`lsof`: `node [::1]:8891` = "Geekify Inc"). From the container, `host.docker.internal` (192.168.65.254) reaches the Mac's IPv4 loopback, so `:8891` is refused; the IPv6 gateway is unreachable. A throwaway relay `127.0.0.1:8891 → [::1]:8891` plus a request with `Host: localhost:8891` returned `200 OK · Geekify Inc` from inside the container. WordPress redirects to `http://localhost:8891`, so the VM browser must use that exact origin.

## Target flow
![flow](assets/vm-handoff/flow.mmd) (Mermaid source: `plans/assets/vm-handoff/flow.mmd`)

## Success criteria
1. A project chat (Geekify) can drive the agent computer's browser with `browser_*` tools, and Mac Chrome is untouched — verified by a real Codex test chat taking a VM screenshot.
2. A file downloaded in the VM browser appears in `~/Chatterbox/Computer/Downloads` on the Mac, and `hand_off_download` copies it into the chat's project (`<project>/handoff/`) — verified by a real download and file comparison.
3. With port 8891 enabled in the Computer window, the VM browser loads `http://localhost:8891` and sees "Geekify Inc" — verified in the VM; with it disabled, the VM can't connect.
4. The VM keeps its own logins (profile volume preserved across the container recreate) and nothing else from the Mac is mounted — verified with `docker inspect`.

## Deliverables
- Code: DotComputer mount + image version, preview relays, chatterbox-mcp computer tools, per-chat "Use agent computer" setting — committed, pushed, installed on the Mac (standing authorization).
- Agent computer image rebuilt and container recreated (profile volume kept) — done on install.
- This plan and issue #22 — published.
- Acceptance run with Dropbox: awaiting Shelby's interactive Dropbox sign-in in the VM.

## Tasks
| ID | Task | Acceptance check |
|---|---|---|
| T1 | Image v2: Downloads dir + `--output-dir`, forward helper, version label; DotComputer recreates the container with the Downloads bind mount when outdated | `docker inspect` shows profile volume + `~/Chatterbox/Computer/Downloads → /home/dot/Downloads` only; old logins still present |
| T2 | Preview relays: Mac IPv4-loopback relay to `[::1]:PORT` (or direct when already on IPv4) + in-container forward `localhost:PORT → host.docker.internal:PORT`, per enabled port; Computer window lists local sites with toggles | From the VM, `http://localhost:8891` returns 200 "Geekify Inc"; a non-enabled port is refused |
| T3 | chatterbox-mcp computer tools for project chats: `computer_status/start/show`, `list_computer_downloads`, `hand_off_download(file, to)`, `list_previews`; app routes validate the file is inside the Downloads folder and the destination is inside the chat's own project | Unit-level harness: hand-off copies byte-identical file; `../` and other-project destinations rejected |
| T4 | "Use agent computer" per chat (Claude `--mcp-config` + allowed tools; Codex thread config), off by default; instructions tell agents to browse there, never in Mac Chrome | Real Codex test chat lists/uses `browser_*` and the hand-off tool |
| T5 | Build, commit, push, install; recreate the computer | Installed app runs; container recreated with logins kept |
| T6 | Acceptance with Geekify (Shelby signs into Dropbox in the VM) | A selected original lands in `geekifyinc.com/handoff/`; VM shows the 8891 preview |

Person's gates: Dropbox sign-in on the VM screen (T6). Install/restart is pre-approved.

## Scope boundaries
- Not mounted: anything on the Mac except `~/Chatterbox/Computer/Downloads`. No Mac browser profiles, cookies, or Keychain items are copied.
- Relays bind 127.0.0.1 only and only for ports Shelby enables; nothing is published to the network or the internet.
- Unchanged: SKD Studio and native design tools on the Mac; Golem's existing computer access; the Geekify chat's in-progress reply (not interrupted, its scripts not edited). Moving Geekify's work onto the VM is offered to that chat, not forced.
- No paid services, no production deploys.

## Test plan
- `xcodebuild -scheme Chatterbox build`.
- Harness (isolated data dir) for hand-off validation and copy.
- Live: `docker inspect` mounts; in-VM HTTP to `localhost:8891` with the toggle on/off; a real Codex test chat (gpt-6-luna) with "Use agent computer" taking a VM screenshot and calling `list_computer_downloads`; a real VM download of a public test file, handed off and compared with `cmp`.

## Rollback
- Turn off "Use agent computer" per chat (default off).
- Container: `docker rm -f chatterbox-dot` and Start again recreates it; the profile volume `chatterbox-dot-profile` is never deleted. Image v1 can be rebuilt from the previous commit.
- Downloads folder is plain files under `~/Chatterbox/Computer/Downloads`.

## Open questions (non-blocking)
- Per-project download subfolders: one browser has one download folder, so downloads share one inbox and the hand-off step scopes them to a project. Revisit if several projects browse at once.

## Work preparation
- Scope: confirmed in Shelby's request (2026-10-02), including authorization to implement, build, commit, push and install.
- Mode: `linear` — one tightly coupled change across the computer, the tool server and chat setup; no useful parallel lanes.
- Model: Claude Opus 5.5 (`claude-opus-5-5`), this session.
- Now/later: now (requested).
- Tracker Trapper: off by Shelby's standing instruction ("Tracker Trapper reporting is off by default… unless the user explicitly asks"); R7 satisfied by issue #22 + this local plan.
- Readiness: pass · 2026-10-02 · R7 via standing instruction above · R12 covered (container recreate) · R3 flow diagram linked.

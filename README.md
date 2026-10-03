# Chatterbox

A native Mac chat app that talks to either **Claude** or **Codex**, built around the ideas that make OpenAI's Codex (github.com/openai/codex, Apache-2.0) feel conversational. The prompts are rewritten in my own words; the mechanics are reimplemented in Swift.

Pick the backend per chat: the Claude/Codex switch on an empty chat, the New Chat button menu, Cmd-Option-N for Claude, or Cmd-Shift-N for Codex. The default is set in Settings. A chat stays on its backend once it starts, because the two keep separate histories.

## Run it

```bash
xcodegen generate
```

```bash
xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Debug/Chatterbox.app
```

Or open `Chatterbox.xcodeproj` in Xcode and press Run.

- **Claude** runs on your installed **Claude Code** (`claude` CLI) and your Claude subscription. No API key. Chatterbox launches `claude` in stream-json mode, one process per chat, and uses your own `~/.claude` settings, CLAUDE.md files, skills, MCP servers, and hooks. It finds `claude` automatically, or you can set the path in Settings. If it isn't signed in, run `claude` in Terminal once and log in.
- **Codex** needs the Codex CLI installed and signed in. Chatterbox launches `codex app-server` in the background and uses your own `~/.codex` config, MCP servers, hooks, and ChatGPT sign-in. It finds `codex` automatically, or you can set the path in Settings.

## Ship the Mac app

```bash
./scripts/ship.sh
```

Builds, pushes committed main, installs into Applications, and restarts Chatterbox. For new work, review and stage only the files to ship, then run `./scripts/ship.sh "Commit message"`. It refuses unstaged/untracked work or a feature branch. Mobile installation remains separate.

## What makes it feel conversational

**Prompt layer** (`prompts/`, bundled into the app): `personalities/friendly.md` and `pragmatic.md` are swappable tone layers. Both agents bring their own system prompt; Chatterbox adds the tone and a note about the chat window.

**Runtime layer** (`Chatterbox/Engine/ChatSession.swift`):
- **Commentary vs. final.** Progress notes stay visible in the chat while a reply runs, including Golem's chat and mini window. Tools and thoughts stay in their step groups. When the reply finishes, progress notes fold into the completed steps too. Only the text that ends the turn becomes the reply.
- **Steering.** The input box stays live while the agent works. Anything you send joins the running turn. It shows "Queued" until the agent picks it up at its next step, then "Sent while working".
- **Interrupt.** Stop (Cmd-.) keeps the partial reply.
- **Tone switching.** The tone menu in the toolbar has Friendly, Pragmatic, and Neutral. The tone is sent as a tagged block only when it changes.
- **Plan card.** Claude Code's to-do list and Codex's plan render as a live checklist.
- **Switching agents.** One chat can move between Claude and Codex models. The incoming agent gets a transcript of what it missed.
- **Projects.** A chat can be bound to a folder, and each folder has one chat. Both agents work in that folder.
- **GitHub.** A project's GitHub repo is read from its folder's git remote. The toolbar shows the repo, branch, and commits to push or pull, with links to the repo, branch, issues, and pull requests. File → New Project from GitHub (Cmd-Shift-O) lists your repos through `gh`, or takes a pasted URL, clones it, and opens it as a project; a repo that already has a chat opens that chat instead.
- **Issues.** Issues… in the repo menu, or Cmd-Shift-I, opens a side panel with the repo's open issues (read through `gh api`): search, label, milestone, and “Mine” filters, three sort orders, and each issue's body and comments. Work on This sends the issue to the chat's agent (as `/dev-work #N` when your Claude Code has that skill) and shows it in the toolbar, next to the branch's pull request. Triage sends the list and asks the agent to rank it, flag duplicates and stale issues, and then ask you which to take next. The app only reads GitHub; any change there is made by the agent, with its usual approvals.
- **Modes.** The mode menu under the message box (Cmd-Shift-P) sets what the agent may do without asking. Claude: Auto, Manual, Accept edits, Plan, Bypass permissions. Codex: Read only, Ask for approval, Approve for me, Full access.
- **Model and presets.** The model line under the message box opens the model picker (Cmd-Shift-M). Preset pills beside it switch agent, model, and effort in one click. They're tinted with the agent's color. Right-click a pill to rename or delete it, or drag it to reorder.
- **Context and usage.** A small ring next to the model line shows how full the conversation's context is. Hover it for the token count, or click it to see your 5-hour and 7-day usage limits and when they reset. It appears after the agent's first reply.
- **Quick switcher.** Cmd-K finds any chat or project by name, title, tag, or agent. It also has New Chat, New Project Chat, New Project from GitHub, and Settings. Use the arrow keys, Return, and Esc.
- **Sidebar.** Search filters chats by title, project name, and tags. The filter button shows only projects with a given tag. A spinner in the agent's color marks chats that are working.
- **Golem mini.** Cmd-J in Chatterbox, the Mini button in Golem's toolbar, or Show Mini Window in its sidebar menu opens a separate window above ordinary app windows. Drag its header to move it; the minus button shrinks it to a draggable avatar with unread and waiting indicators. Click the avatar to resume the same chat and draft. The expand button returns to the main window. Its position, size and collapsed state are remembered; hiding it does not stop Golem.

## Claude Code backend

`Chatterbox/Engine/ClaudeCode.swift` runs `claude -p --input-format stream-json --output-format stream-json`. `ChatSession+Claude.swift` maps it onto the transcript:

- Streamed text, thinking, and tool calls become the reply, dim notes, and status rows. `TodoWrite` becomes the plan card.
- Permission prompts arrive over stdio (`--permission-prompt-tool stdio`) and show as approval cards with Allow, Allow for This Chat, and Deny. The mode menu sets Claude Code's permission mode live; in Plan mode, the finished plan shows as a card with Start Building, Start and Accept Edits, and Keep Planning.
- Model, effort, and permission changes are sent live as control requests. The model list and effort levels come from Claude Code's own startup handshake.
- Each chat resumes its Claude Code session with `--resume`, so it survives restarts. A reply that's still running when you quit continues in the background host (see below).

## Codex backend

`Chatterbox/Engine/CodexAppServer.swift` runs one shared `codex app-server` process over JSON-RPC on stdio. `ChatSession+Codex.swift` maps it onto the same transcript as Claude:

- Codex's `commentary` / `final_answer` message phases become the dim notes and the reply.
- Commands, file edits, MCP tools, and web searches become status rows. `turn/plan/updated` becomes the plan card.
- Messages sent mid-turn use `turn/steer`, and Stop uses `turn/interrupt`.
- Each chat has a folder (the toolbar folder button) and a mode: Read only (read-only sandbox), Ask for approval (can write in the folder, asks for anything beyond it), Approve for me (same, with Codex's `auto_review` reviewer deciding), or Full access (no sandbox, never asks). Approval cards have Allow, Allow for This Chat, and Deny.
- The tone picker still works. The personality goes in as developer instructions when the thread starts, and as a tagged block when you change it.
- Codex threads persist, and reopening an old chat resumes its thread.
- Models and effort levels come live from `model/list`.

## Background host

Replies keep running after you quit Chatterbox, and are waiting when you reopen it. The agent processes don't run as the app's children: `ChatterboxHost` (a small command-line tool inside the app, `Contents/MacOS/ChatterboxHost`) runs them, like tmux for JSON streams.

- The app launches the host on first use. It listens on a Unix socket in `~/Library/Application Support/Chatterbox/Host/` (folder mode 0700, socket 0600, same user only). It's in its own session and ignores SIGHUP and SIGPIPE, so quitting or crashing the app doesn't take it down. It exits by itself after 60 seconds with no processes and no app connected.
- Each process's stdout is written to `Host/logs/<id>.jsonl`. The app reads it back as `(line, byte offset)` pairs: first the saved lines from an offset, then live ones, then the exit status. Once the app has saved past a point, a log over 32 MB is trimmed to that point. Offsets stay valid after trimming.
- Each chat saves the id of its Claude Code process and how far it has read. It also saves the in-flight turn's bookkeeping, like which row each streamed block goes to. Saves are batched and always happen between two output lines. On relaunch, the chat reattaches and replays from its offset into exactly the saved state, so it never gets repeated or half-built rows. The shared Codex app-server works the same way: `Host/codex-resume.json` holds its id and offset, and each chat skips lines it had already saved.
- Approval and question cards stay answerable after a relaunch while their process is still alive. They expire only when their process is gone. A reply that finished while the app was closed replays the rest of its log, so the final answer lands.
- With no app attached, an agent that isn't working is let go after 30 seconds by closing its stdin. A Claude chat is working until its `result`. Codex is working while any turn is running. If an agent asks for approval or has a question while no app is attached, the host posts a notification through `osascript`, because a command-line tool can't post notifications of its own.
- Settings → General → **Keep replies running after Chatterbox quits** (on by default). When it's off, quitting stops everything the app started.
- For testing, set `CHATTERBOX_HOST_DIR` to move the socket and logs, and `CHATTERBOX_HOST_BINARY` to use a different host binary. Timings can be changed with `CHATTERBOX_HOST_IDLE_SECONDS`, `CHATTERBOX_HOST_DETACHED_IDLE_SECONDS`, and `CHATTERBOX_HOST_LOG_LIMIT`. `CHATTERBOX_HOST_NOTIFY=0` turns notifications off.

The app isn't sandboxed, because it has to launch `claude` and `codex` and let them reach your files.

Conversations are saved as JSON in `~/Library/Application Support/Chatterbox/Conversations/`, and attachments in `Attachments/` next to it.

## Layout

- `Chatterbox/Engine/` has the chat session (`ChatSession.swift`), the Claude Code bridge (`ClaudeCode.swift`, `ChatSession+Claude.swift`), the Codex bridge (`CodexAppServer.swift`, `ChatSession+Codex.swift`), the background-host client and resume logic (`HostClient.swift`, `ChatSession+Host.swift`), tool labels, presets, the prompts loader, and persistence.
- `ChatterboxHost/` is the background host. `Chatterbox/Support/HostProtocol.swift` (paths, framing, sockets) and `JSON.swift` are compiled into both targets.
- `Chatterbox/Views/` has the SwiftUI views: sidebar, transcript rows, composer, Markdown, and settings.
- `prompts/` has the tone files, which you can edit without touching code.
- `reference/typescript/conversation.ts` is a provider-agnostic TypeScript version of the conversation loop, for porting into other software.
- `project.yml` is the xcodegen spec. The `.xcodeproj` is generated.

## Graft development tools

[Graft](https://github.com/NanoNets/context-graph-engine) indexes Chatterbox's source for coding agents. It's a project-local development dependency (Node.js 20 or later), separate from the app, the iOS companion and the MCP server.

```sh
npm ci
npm run graft:setup   # adds graft_development to this checkout's .codex/config.toml and .mcp.json
npm run graft:build   # structural index; no model or API key
npm run graft:check
npm run graft:map
```

Start a new agent session after setup to load it. The wrapper disables telemetry and anchors commands to this checkout. The generated index, dependencies and machine-specific MCP configuration are ignored by Git. `graft build --deep` (model-written summaries) is a separate, explicit step.

## License

Apache License 2.0. See [LICENSE](LICENSE). Chatterbox builds on ideas from [OpenAI Codex](https://github.com/openai/codex), also Apache-2.0; see [NOTICE](NOTICE).

## PDF review on iPhone and iPad

PDFs attached to a chat or named by a reply have a **Review PDF** tile. Markdown PDF links open the same full-screen viewer. Downloads stream to disk with progress and cancellation; after downloading, PDFKit provides page scrolling, pinch zoom and text selection. Use **Save to Files** to export a copy or **Share** to send it to another app.

Opened PDFs stay in **Saved PDFs**, under the chat list's connection menu, for offline review. **Refresh PDF** fetches a newer copy; a failed or invalid download preserves the previous copy. The Mac must be reachable for the first download or a refresh. Transfers use the existing paired connection and chat-scoped file IDs; they do not expose an arbitrary filesystem endpoint.

Verification: `scripts/test-companion-pdf.sh` tests the Mac route and bounded transport; `scripts/test-pdf-cache.sh` tests replacement integrity; `scripts/test-mobile-pdf.sh iphone` (or `ipad`) tests the viewer, Files export, cancellation/retry and offline library on an isolated simulator/server.

## iPhone and iPad push notifications

On the Mac, Settings → iPhone → Push notifications accepts an APNs Key ID and .p8 signing key (stored in Keychain). Enable the companion server, then on each paired mobile device tap the bell in the chat list and turn on Notifications. The Mac can send a test to each registered device.

Approvals/questions, finished replies, Golem briefings and important emails can each be enabled separately; previews and sound are optional. The Mac must stay awake with Chatterbox open. Notifications arrive through Apple on cellular as well as Wi-Fi; tapping into the actual chat still needs a connection to the Mac. Debug installs use APNs sandbox; Release uses production. See [validation and setup limits](design/mobile-push/delivery.md).

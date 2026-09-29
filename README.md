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

## What makes it feel conversational

**Prompt layer** (`prompts/`, bundled into the app): `personalities/friendly.md` and `pragmatic.md` are swappable tone layers. Both agents bring their own system prompt; Chatterbox adds the tone and a note about the chat window.

**Runtime layer** (`Chatterbox/Engine/ChatSession.swift`):
- **Commentary vs. final.** Text written before a tool call is shown as a dim inline note. Only the text that ends the turn becomes the reply.
- **Steering.** The input box stays live while the agent works. Anything you send joins the running turn. It shows "Queued" until the agent picks it up at its next step, then "Sent while working".
- **Interrupt.** Stop (Cmd-.) keeps the partial reply.
- **Tone switching.** The tone menu in the toolbar has Friendly, Pragmatic, and Neutral. The tone is sent as a tagged block only when it changes.
- **Plan card.** Claude Code's to-do list and Codex's plan render as a live checklist.
- **Switching agents.** One chat can move between Claude and Codex models. The incoming agent gets a transcript of what it missed.
- **Projects.** A chat can be bound to a folder, and each folder has one chat. Both agents work in that folder.
- **GitHub.** A project's GitHub repo is read from its folder's git remote. The toolbar shows the repo, branch, and commits to push or pull, with links to the repo, branch, issues, and pull requests. File → New Project from GitHub (Cmd-Shift-O) lists your repos through `gh`, or takes a pasted URL, clones it, and opens it as a project; a repo that already has a chat opens that chat instead.
- **Modes.** The mode menu under the message box (Cmd-Shift-P) sets what the agent may do without asking. Claude: Auto, Manual, Accept edits, Plan, Bypass permissions. Codex: Read only, Ask for approval, Approve for me, Full access.
- **Model and presets.** The model line under the message box opens the model picker (Cmd-Shift-M). Preset pills beside it switch agent, model, and effort in one click. They're tinted with the agent's color. Right-click a pill to rename or delete it, or drag it to reorder.
- **Context and usage.** A small ring next to the model line shows how full the conversation's context is. Hover it for the token count, or click it to see your 5-hour and 7-day usage limits and when they reset. It appears after the agent's first reply.
- **Quick switcher.** Cmd-K finds any chat or project by name, title, tag, or agent. It also has New Chat, New Project Chat, New Project from GitHub, and Settings. Use the arrow keys, Return, and Esc.
- **Sidebar.** Search filters chats by title, project name, and tags. The filter button shows only projects with a given tag. A spinner in the agent's color marks chats that are working.

## Claude Code backend

`Chatterbox/Engine/ClaudeCode.swift` runs `claude -p --input-format stream-json --output-format stream-json`. `ChatSession+Claude.swift` maps it onto the transcript:

- Streamed text, thinking, and tool calls become the reply, dim notes, and status rows. `TodoWrite` becomes the plan card.
- Permission prompts arrive over stdio (`--permission-prompt-tool stdio`) and show as approval cards with Allow, Allow for This Chat, and Deny. The mode menu sets Claude Code's permission mode live; in Plan mode, the finished plan shows as a card with Start Building, Start and Accept Edits, and Keep Planning.
- Model, effort, and permission changes are sent live as control requests. The model list and effort levels come from Claude Code's own startup handshake.
- Each chat resumes its Claude Code session with `--resume`, so it survives restarts.

## Codex backend

`Chatterbox/Engine/CodexAppServer.swift` runs one shared `codex app-server` process over JSON-RPC on stdio. `ChatSession+Codex.swift` maps it onto the same transcript as Claude:

- Codex's `commentary` / `final_answer` message phases become the dim notes and the reply.
- Commands, file edits, MCP tools, and web searches become status rows. `turn/plan/updated` becomes the plan card.
- Messages sent mid-turn use `turn/steer`, and Stop uses `turn/interrupt`.
- Each chat has a folder (the toolbar folder button) and a mode: Read only (read-only sandbox), Ask for approval (can write in the folder, asks for anything beyond it), Approve for me (same, with Codex's `auto_review` reviewer deciding), or Full access (no sandbox, never asks). Approval cards have Allow, Allow for This Chat, and Deny.
- The tone picker still works. The personality goes in as developer instructions when the thread starts, and as a tagged block when you change it.
- Codex threads persist, and reopening an old chat resumes its thread.
- Models and effort levels come live from `model/list`.

The app isn't sandboxed, because it has to launch `claude` and `codex` and let them reach your files.

Conversations are saved as JSON in `~/Library/Application Support/Chatterbox/Conversations/`, and attachments in `Attachments/` next to it.

## Layout

- `Chatterbox/Engine/` has the chat session (`ChatSession.swift`), the Claude Code bridge (`ClaudeCode.swift`, `ChatSession+Claude.swift`), the Codex bridge (`CodexAppServer.swift`, `ChatSession+Codex.swift`), tool labels, presets, the prompts loader, and persistence.
- `Chatterbox/Views/` has the SwiftUI views: sidebar, transcript rows, composer, Markdown, and settings.
- `prompts/` has the tone files, which you can edit without touching code.
- `reference/typescript/conversation.ts` is a provider-agnostic TypeScript version of the conversation loop, for porting into other software.
- `project.yml` is the xcodegen spec. The `.xcodeproj` is generated.

## License

Apache License 2.0. See [LICENSE](LICENSE). Chatterbox builds on ideas from [OpenAI Codex](https://github.com/openai/codex), also Apache-2.0; see [NOTICE](NOTICE).

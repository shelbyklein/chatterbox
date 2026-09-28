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

- **Claude** needs an Anthropic API key. Paste it in Settings (Cmd-,). It's stored in your login keychain. Debug builds are ad-hoc signed, so macOS may ask for keychain access again after a rebuild.
- **Codex** needs the Codex CLI installed and signed in. Chatterbox launches `codex app-server` in the background and uses your own `~/.codex` config, MCP servers, hooks, and ChatGPT sign-in. It finds `codex` automatically, or you can set the path in Settings.

## What makes it feel conversational

**Prompt layer** (`prompts/`, bundled into the app):
- `conversational_base.md` covers preambles before actions, progress check-ins, replies sized to the request, teammate voice, numbered next steps, a visible plan, and how to handle messages sent mid-task.
- `personalities/friendly.md`, `pragmatic.md` are swappable tone layers.
- `compaction.md` is the handoff-summary prompt for long chats.

**Runtime layer** (`Chatterbox/Engine/ChatSession.swift`):
- **Commentary vs. final.** Text Claude writes before a tool call is shown as a dim inline note. Only the text that ends the turn becomes the reply.
- **Steering.** The input box stays live while Claude works. Anything you send is folded into the running turn at the next model call, marked "Sent while working".
- **Interrupt.** Stop (Cmd-.) keeps the partial reply and tells the model it was cut off.
- **Tone switching.** Friendly / Pragmatic / Neutral in the toolbar. Personality is sent as a tagged block only when it changes, so the system prompt stays frozen and cached.
- **Plan card.** An `update_plan` tool renders a live checklist for multi-step work.
- **Compaction.** When a request passes about 300K input tokens, history is replaced by a summary plus your last few messages verbatim.

## Codex backend

`Chatterbox/Engine/CodexAppServer.swift` runs one shared `codex app-server` process over JSON-RPC on stdio. `ChatSession+Codex.swift` maps it onto the same transcript as Claude:

- Codex's `commentary` / `final_answer` message phases become the dim notes and the reply.
- Commands, file edits, MCP tools, and web searches become status rows. `turn/plan/updated` becomes the plan card.
- Messages sent mid-turn use `turn/steer`, and Stop uses `turn/interrupt`.
- Each chat has a folder (the toolbar folder button) and a **Can edit** toggle. Off is a read-only sandbox; on lets Codex write inside that folder. Approval policy is `on-request`, so when Codex needs to go beyond that, an approval card appears with Allow, Allow for This Chat, and Deny.
- The tone picker still works. The personality goes in as developer instructions when the thread starts, and as a tagged block when you change it.
- Codex threads persist, and reopening an old chat resumes its thread.
- Models and effort levels come live from `model/list`.

The app isn't sandboxed, because it has to launch `codex` and let it reach your files.

## API details

- Model `claude-opus-5` by default (Sonnet 5 selectable), adaptive thinking with summarized thoughts shown in a collapsible "Thinking" row, and effort defaulting to medium for snappier chat.
- Streams via raw HTTP and SSE (Swift has no official Anthropic SDK). `Chatterbox/Engine/AnthropicClient.swift`.
- Opus 5 requests opt into server-side refusal fallbacks (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`). A declined request is retried on Anthropic's recommended model in the same call, and the transcript notes the switch.
- Web search and web fetch are server tools, toggled per chat with the globe button. Search is billed per use.
- History is append-only and raw content blocks are echoed back unchanged, which keeps thinking blocks valid and the prompt cache warm. Top-level `cache_control` turns on automatic caching.
- Conversations are saved as JSON in `~/Library/Application Support/Chatterbox/Conversations/`.

## Layout

- `Chatterbox/Engine/` has the Claude API client and loop (`ChatSession.swift`), the Codex bridge (`CodexAppServer.swift`, `ChatSession+Codex.swift`), tools, the prompts loader, and persistence.
- `Chatterbox/Views/` has the SwiftUI views: sidebar, transcript rows, composer, Markdown, and settings.
- `prompts/` has the prompt files, which you can edit without touching code.
- `reference/typescript/conversation.ts` is a provider-agnostic TypeScript version of the same loop, for porting into other software.
- `project.yml` is the xcodegen spec. The `.xcodeproj` is generated.

For Claude chats, I left out the coding-specific Codex patterns: AGENTS.md handling, sandboxing and approvals, patch editing, and git safety rules. Codex chats get all of those from Codex itself.

## License

Apache License 2.0. See [LICENSE](LICENSE). Chatterbox builds on ideas from [OpenAI Codex](https://github.com/openai/codex), also Apache-2.0; see [NOTICE](NOTICE).

# T1 spike — 2026-10-22

All runs from the Mac via `ssh -T desktop node C:\Users\sklei\.chatterbox\chatterbox-worker.js` with a JSON header line (`deploy/pc-worker/chatterbox-worker.js`). Scripts: `/tmp/pcw-spike/*.py` (scratch).

| Check | Result |
|---|---|
| Claude stream-json over SSH | Transport OK: `system/init` reported `cwd: D:\Chatterbox\workspaces\spike` and the Bash/PowerShell tools. The turn failed with **"OAuth session expired and could not be refreshed"**, so Claude's sign-in on the PC must be renewed (Shelby's gate) |
| Codex app-server over SSH (ChatGPT Pro sign-in) | `initialize`, `account/read`, `thread/start` (default model gpt-5.6-sol) and a turn all completed. The command output matched the PC workspace and the env secret `s3cr3t-ünïcödé` arrived intact. The file was written as UTF-8 bytes `68-C3-A9-6C-6C-6F-20-E2-9C-93-0A` |
| Stop / orphan cleanup | SIGKILL of the local `ssh` process group removed the worker `node.exe` and `codex app-server` on the PC within 5 s. Only Shelby's own Codex desktop process (pid 19460, pre-existing) remained |
| Ollama in session 1 | Logon task "Chatterbox Ollama" (`wscript ollama-serve.vbs`; `OLLAMA_HOST=127.0.0.1:11434`, `OLLAMA_CONTEXT_LENGTH=32768`, `OLLAMA_KEEP_ALIVE=30m`). `Start-ScheduledTask` over SSH started `ollama` in session 1. `/api/tags` lists 5 models |
| Ollama Anthropic API (`/v1/messages`) | gpt-oss:20b returned `stop_reason=tool_use` with a correct `write_file` call |
| Ollama Responses API (`/v1/responses`) | OK |
| Codex + Ollama | Needs a custom provider id: `ollama` is reserved ("Built-in providers cannot be overridden"), so the id is `chatterbox-pc` with `wire_api=responses`. The effort must be set explicitly: the PC's Codex default `xhigh` is rejected by Ollama, which accepts none/low/medium/high/max. gpt-oss:20b completed a shell-tool turn in 42 s (cold), qwen3.5:9b in 38 s (cold, including model swap) |
| Claude Code + Ollama | Env `ANTHROPIC_BASE_URL=http://127.0.0.1:11434`, `ANTHROPIC_AUTH_TOKEN=ollama`, `ANTHROPIC_API_KEY=""`, small/haiku model = same model. qwen3.5:9b completed a Write-tool turn in **12 s**, gpt-oss:20b in 68 s (including model swap). No Anthropic sign-in needed |
| VRAM | gpt-oss:20b at 32k context = 14 GB, **32% CPU / 68% GPU** (doesn't fit 12 GB). qwen3.5:9b at 32k = 6.6 GB, **100% GPU** |
| Mac → PC tunnel | `ssh -N -L 127.0.0.1:47340:127.0.0.1:11434 desktop`. `/api/tags` and `/v1/messages` answered from the Mac |

**Decisions from the spike**
- Default PC model: **qwen3.5:9b** (fits the GPU, fastest). gpt-oss:20b stays selectable for harder work.
- The Codex provider id is `chatterbox-pc`. The effort sent for PC models is capped to Ollama's accepted values (xhigh → high).
- The worker design holds. Remaining gap: Claude sign-in on the PC.

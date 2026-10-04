# Color in the embedded terminal

The embedded shell has a monochrome login prompt although SwiftTerm supports ANSI output. Set a readable 16-color palette, enable CLICOLOR, and style the zsh prompt green/cyan/amber in Chatterbox only.

Target sketch: [green user] [cyan folder] [amber %] on existing dark pane. Existing terminal layout preserved.

Work preparation: local:terminal-color; direct implementation request confirms scope/now. Linear GPT-6.1-Sol Medium. R1–R13 pass; no open questions. Existing commit/push/install authorization applies. No GitHub issue mutations.

Deliverables/success: committed/pushed code, built/installed Mac, inspected native screenshot showing colored prompt. Actual embedded zsh must emit ANSI and still run original startup files. Normal user shell files remain untouched. Non-zsh shells keep their own prompt; palette and CLICOLOR apply to all.

- [x] COLOR-1: Palette and session-only zsh startup forwarding. Check original rc executes and prompt includes ANSI.
- [x] COLOR-2: Build, inspect native rendered terminal; commit/push/install.

Test plan: production ChatTerminal native harness, synthetic source rc marker, prompt/output render and ANSI foreground checks. Existing terminal-bottom shortcut harness retains ordering. Rollback by restoring /tmp/Chatterbox-before-terminal-color.app; temporary startup files removed on shell exit. No schema/pin/chat changes, no syntax-highlighting plugin or external dependency. The colored prompt intentionally replaces prompt formatting only in embedded zsh; original aliases/functions/login startup still run.

Verified native zsh prompt has 90 colored cells, original rc marker executed and rc byte content unchanged. Actual composited screenshot inspected: /Users/shelbyklein/Chatterbox/Screenshots/terminal-color/prompt.png. Build passed. Repeatable check: scripts/test-terminal-color.sh. Non-zsh prompt styling intentionally unchanged; every command is not automatically syntax-highlighted.

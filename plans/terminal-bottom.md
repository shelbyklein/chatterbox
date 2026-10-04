# Terminal below the chat

The terminal currently sits between transcript and composer in ChatView.chatContent, splitting the chat into two pieces. Put it after the composer so the full chat occupies the upper pane and the terminal occupies the bottom pane.

Evidence: user screenshot /Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/61F71604-91C3-4B13-8886-67CCD7059E7C/CleanShot 2026-10-04 at 3.58.43 AM@2x.png.
Target order sketch: [transcript → restart status → composer] above [resize handle → terminal].

Work preparation: local:terminal-bottom; confirmed by direct implementation request. Linear, GPT-6.1-Sol Medium; one layout edit. R1–R13 pass; no open questions. GitHub issue mutations excluded under standing read-only issue instruction. Existing scoped commit/push/install authority applies.

Success: terminal below composer, transcript still above composer, both within chat column. Shell persistence, resize/close and shortcuts unchanged. Deliver source committed/pushed, built/installed and native render proof inspected.

- [x] TERM-1: Move TerminalPanel below composer in shared Mac layout.
- [x] TERM-2: Build and check native chat with terminal open; inspect ordering, then commit/push/install.

Verification: xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData build -quiet; isolated native ChatView using real terminal toggle. No redundant layout unit tests for this low-impact ordering change. Preserve transcripts/drafts/shell lifecycle; no mobile or column-width changes. Rollback: backup installed bundle /tmp/Chatterbox-before-terminal-bottom.app and restore it if needed.

Verification: native ⌃` shortcut accepted; real LocalProcessTerminalView bounds y6–207, composer TextView y286–302 (AppKit coordinates), intact draft. Production ChatView screenshot inspected: /Users/shelbyklein/Chatterbox/Screenshots/terminal-bottom/open.png. Terminal glyphs do not appear in offscreen capture; pane order and composer verified. No shell command executed. Resize/close behavior unchanged but not separately exercised. Build passed.

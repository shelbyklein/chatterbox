# Tools popover crash

Opening the session's puzzle-piece Tools button intermittently crashes the Mac app. A live debugger reproduction on October 20 captured EXC_BAD_ACCESS at a null callback in UpdateCycle, reached through SwiftUI PopoverHostingView.updateAnimatedWindowSize and AppKit NSPopover's animated content resize. The server list arrives asynchronously and previously changed the popover's intrinsic height.

Local plan: `instructions/tools-popover-crash.md`. The requested fix preserves the existing tool configuration and edit actions.

## Evidence and intended layout

Current entry: [user's Tools icon](</Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/FEF6E23D-E3E0-4413-BBC5-F40FF1A03417/CleanShot 2026-10-20 at 1.13.56 PM@2x.png>).

Debugger trace is retained locally in `build/tools-crash-backtrace.txt`. Relevant path:

```text
UpdateCycle::continueProcessing
  NSMoveHelper / NSResizeMoveHelper animation
  NSWindow setFrame:display:animate:
  NSPopover _setContentView:size:canAnimate:
  SwiftUI PopoverHostingView.updateAnimatedWindowSize
```

Target:

```text
┌────────────── fixed 320 × 360 pt ──────────────┐
│ Tools                                        │
│ ┌──────────── scrollable content ───────────┐ │
│ │ Loading → server list, notes, disabled... │ │
│ └─────────────────────────────────────────┘ │
│ Edit for project…                     Edit… │
└─────────────────────────────────────────────┘
```

## Success criteria

- Opening Tools for either provider does not resize its window as server discovery finishes. Empty and long lists remain usable within the same bounded panel.
- Project and global edit actions remain available. The installed app survives repeated opening/closing of the actual button.
- UI crash monitoring runs in daemon-connected mode and clean shutdown replaces stale previous-run metadata.

## Work preparation

Mode: linear, a small coupled Mac UI fix. Executor: current session; exact model/effort unavailable. Readiness: pass; R1-R11/R13 documented here. R12: no data migration or tool configuration changes; revert the scoped Core/root commits and reinstall with `scripts/install.sh` if needed. Existing conversations and tool configuration are left intact. No service restart, mobile build, GitHub issue changes, or agent host stops are in scope. No blocking questions remain after the debugger reproduction.

## Tasks and acceptance

- [x] T1 Reproduce the crash under a debugger; captured the animated popover resize path above.
- [x] T2 Fix stable sizing and restore diagnostics. `scripts/test-tools-settings.sh` exercises the actual button, fixed size for Claude/Codex/empty/60-server results, and replacement of existing last-run metadata.
- [x] T3 Verify and deliver. Inspect rendered panel and real installed Tools entry, run Mac build/source checks, commit and push scoped changes, install/reopen with standing approval, verify monitoring marker and repeated Tools opens, then run tidy report.

Validation: `scripts/test-tools-settings.sh` passed all actual button openings (Claude, Codex, 60-server list, empty results). Every window stayed 346 × 386 pt including popover chrome. Crash marker replacement passed. Log: `build/tools-popover-after.log`. Mac build and source check passed; installation verification remains below T3.

Installed verification (October 20): reopened the actual Tools panel repeatedly in a Claude project and a Codex Studio sidechat; both stayed responsive. The monitored UI PID matches `/Applications/Chatterbox.app/Contents/MacOS/Chatterbox`. Inspected native screenshot: `build/verification/tools-popover-installed.png`. Root implementation commit: `242a588`; Core: `69e18df`. No daemon restart was needed. Tidy report completed; historical removals were left untouched.

# Waiting-session card highlighting

Cards should make a session with an unanswered question clearly visible, just as list rows do. Keep the waiting highlight visible even when the card is selected, and remove it when the question is answered. The user selected this scoped fix after read-only triage; GitHub remains unchanged.

Current evidence: `ContentView.row` sets a yellow `listRowBackground`, which does not paint the card layout. `ThreadCard` only sets a thin orange outline with the usual neutral fill. `ChatSession.isWaitingOnYou` correctly includes pending questions and approvals.

Current rendered state: [baseline native render](before.png), captured by `scripts/test-card-attention.sh`. Target: [highlight sketch](target.svg). The same waiting fill applies to full cards and icon tiles.

## Success criteria
- Pending questions have a visible yellow fill and stronger border on selected and unselected cards, in light and dark mode (native ThreadCard render).
- Answering clears the waiting highlight and restores selected/neutral appearance (same-session mutation and subsequent render).
- Pending approvals use the existing shared waiting predicate; no provider, message, draft or filtering changes.

## Tasks
- [x] C1 Capture baseline with isolated native cards; inspect pending and answered states.
- [x] C2 Add waiting backgrounds/borders inside ThreadCard; run native regression/render checks and Mac build.
- [x] C3 Inspect resulting images and install verified Mac build using existing install script; report status without GitHub writes.

Deliverables: local source, local regression fixture, inspected screenshots, built/installed Mac app. No commits, push, GitHub issue creation or closure under this request's GitHub restriction.

## Work preparation
Mode: linear, one executor for one shared UI file. Runtime model: gpt-6.1-sol, medium (verified current turn_context). Scope and implementation authorized by user's choice “card view highlights”. Local plan: `design/card-attention/plan.md`. No blocking questions. R1–R11/R13 pass after baseline captured; R12: install rollback uses previous installed app copied before replacement. Readiness: pass, 2026-10-06; R1–R13 satisfied. Baseline inspected; only a thin outline distinguishes waiting cards. No background service restart required.

Test: `scripts/test-card-attention.sh`; `xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData build -quiet`. Entry point is actual shared ThreadCard used by sidebar card view and Studios thumbnails, rendered by NSHostingView in an isolated store. Installed interaction is distinguished from fixture verification.

## Results
Native rendering and state/link checks pass. Mac build passes; app installed and executable byte-matches tested build. App PID 37959; daemon PID 60096 stayed running (no restart). Local source remains uncommitted and unpushed; GitHub unchanged. Live click/answer interaction not automated; native shared view renders inspected. Rollback bundle: /tmp/chatterbox-card-rollback.RoT52c/Chatterbox.app.
[Verified after render](after.png)

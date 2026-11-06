# General automation validation — November 6, 2026

Implemented on parent branch `general-automations` with Core branch of the same name. The completed upstream mobile Activity change is integrated. The real app and automation configuration are unchanged; activation/migration remain a Ship step.

## Passing feature checks

- `scripts/test-automation-routines.sh`: 88 behavioral checks, including independent General sessions without an open project, preset/default agent consistency, backward-compatible companion responses, stable weekday identity, archived-session recovery, invalid-target refusal, cross-weekday overlap prevention and Desk source checks. Stand-in runs invoke no model or external source.
- `scripts/test-general-automation-migration.sh`: four tests covering exact deltas, idempotency, mismatched-input refusal, dry-run purity, backups and real/Dev write guards.
- `scripts/test-automations-panel.sh`: native Mac editor/center rendering, independent scope/destination, and seven weekdays displayed as one daily routine.
- Focused phone UI on iPhone 17 Pro / iOS 26.2: General listing, opening its reporting session without a review, and editing/saving/running against the fixture server pass. The edit test reveals the run button after the keyboard scrolls the taller General form.
- `scripts/test-flavor.sh`: real and Dev identities remain distinct.
- Current real configuration copied to an isolated build fixture and migrated twice: only the seven destination fields and delivery sentence changed; unrelated routines and state bytes were preserved; repeat application was a no-op.

## Installed Dev acceptance

Installed/reopened Chatterbox Dev; its service restarted under the idle rule and reported healthy at 15:41:27 local after 5 seconds. A seven-day fixture with paused, source-free instructions was imported and migrated online twice. Runtime preparation created the ordinary Morning priorities chat with Codex, no project/Studio/parent context, the Dev data working folder, no conversation items and no agent host.

CUA exercised toolbar Automations → General → Open Session, and Add Automation → General → Edit. Saved installed proofs are `dev-installed-center.png`, `dev-installed-editor.png`, `dev-installed-report-session.png`; persisted invariants are in `dev-preview-state.json`. Original real configuration hashes and Dev run-state bytes were checked unchanged. No morning review was started.

## Broad regression limit

The required `scripts/tests-for.sh --run --all` attempt ran for approximately 45 minutes while honoring the Mac pressure/build guards. Twelve scripts passed and `test-chat-switch.sh` failed with exit 133 at `tests/chat-switch/Coordinator.swift:11`. That assertion requires the outgoing view to have opacity zero and a negative offset after 40ms; the current `ChatSwitchTransition.show` deliberately swaps immediately with opacity one and zero offset. Both the test and implementation are unchanged from this feature's baseline (`27affb1` / Core `b89df0f`).

The broad run was stopped safely after that known baseline mismatch, during the next script's guard-held compilation. The remaining 98 scripts were not completed. This is incomplete broad coverage, not a green full-suite result. Logs are in the worktree's `build/general-full-suite.log` and `build/test-logs/`. The feature-specific checks above passed independently, including the final agent-setting follow-up.

No unrelated animation behavior or tests were changed to hide the mismatch. The tracking issue stays open for broad validation/review and the separate Ship/real migration gate.

## Final restoration

A concurrent Main-based Dev installation replaced the General-enabled service at 16:02. The branch now also integrates the committed Activity connection-error fix (Core a58ea21 / parent 60fb8f1). General Mac/runtime sources were checked byte-identical to the versions exercised by the 88 behavioral checks. The combined build was reinstalled and its Dev service reported healthy after the idle restart at 16:10:02 (4s). The General card and ordinary reporting session were verified again; current screenshot: `dev-restored-center.png`. Real configuration remains unchanged and the same seven paused preview entries/reporting UUID remain intact. The test-mapping regression script also passes after retaining both integrations’ map entries.

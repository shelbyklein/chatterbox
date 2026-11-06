<!-- desk-intake-deduplication-2026-11-06 -->
# Prevent duplicate Desk intake

Incoming source updates can create a second task while the original is working or waiting for Shelby in review. Enforce identity checking at task creation, across the stored task list, and make the intake instructions and CLI expose that behavior clearly.

Evidence: Core/Chatterbox/Engine/DeskStore.swift add(_:) unconditionally inserts a new UUID after parsing its origin (lines 268–319). ProjectAutomations.deskSourceInstructions currently asks agents to de-duplicate, but cannot enforce it. bin/desk plain list prints incoming only; --json returns the board. The existing plan desk-source-check.md also requires source de-duplication.

## Scope and flow

Incoming source → parse canonical identity → compare existing stored tasks in all columns → existing task: reuse its ID without changing its thread, column, text or confidence; otherwise create one task.

Exact source identity is authoritative (ClickUp ID/link, email message ID). For legacy source-less tasks, use conservative exact normalized text with compatible source/place context; never fuzzy-merge unrelated tasks. Intake instructions also compare verified sender/subject/date when no email ID is available. Preserve Done tasks against unchanged re-imports; genuine new work requires a separate task identity. Existing duplicates are left intact for separate review.

## Success criteria

1. Repeated intake for one source produces one task, including while working, needs-you, review, silenced or done; verify service tests and saved/reloaded state.
2. Reuse preserves task ID, thread, column, confidence and contents; distinct sources remain distinct even with identical titles.
3. CLI and source-check instructions describe full-board comparison and do not claim a new task was created on reuse; verify CLI fixtures.

## Deliverables and tasks

- [x] T1 Implement central add-time identity check in Core with regression tests for repeated/changed-wording imports, ID/link forms, legacy fallback, all lifecycle states, distinct identities, persistence and no auto-start side effects. Acceptance: scripts/test-desk.sh passes.
- [x] T2 Update bin/desk output/help and shared intake instructions so checks cover the whole board and report reuse accurately. Acceptance: CLI fixtures and scripts/test-automation-routines.sh pass (verify test name before running).
- [ ] T3 Run scripts/tests-for.sh --run for changed files, then scripts/tests-for.sh --run --all once; disclose failures. Commit/push only scoped changes, including Core pointer. Install with scripts/install-dev.sh and report Dev service state. Real app shipment waits for Shelby's Ship instruction. Acceptance: tests recorded, commits pushed, Dev installed.

Execution is linear: one small service/CLI change with shared behavior; no delegation. Model: current session; exact model/effort unavailable.

No board redesign, connector changes, live intake, external source writes, automatic merging/deletion of existing duplicates, database migration or production installation. Check both repository statuses before changing files; preserve other sessions' work.

Rollback: no schema change or stored-task rewrite is planned. Before Dev install preserve its desk.json in a dated backup; revert scoped commits and reinstall Dev if necessary. Do not restore a backup over newer live tasks.

Open questions: none blocking; scope follows Shelby's requested prevention across the existing task list.

Tracking: https://github.com/shelbyklein/chatterbox/issues/50

## Work preparation

Scope confirmed by the explicit duplicate-prevention request. Execution: linear, current session; exact model/effort unavailable. Recipient: this session. Now/later: now, explicitly authorized by Shelby. T1 and T2 complete; T3 in progress. Readiness: pass, 2026-11-06; R1–R13 covered; R3 flow is embedded above, no visual UI change. Plan and checklist are the same document, mirrored to the linked issue below. Implementation complete; delivery and full-suite verification pending.

Validation so far: Desk service/CLI 276 checks pass (build/desk-dedup-final-focused.log); automation routines 67 checks pass. Regression fixtures verify every task state, capped-out Review, persistence, same-source changed wording, distinct source IDs and side-effect-free reuse. Corrected mobile-promotion fixture source list to include its existing AutomationRunner dependency; recheck passes. Test-selection mapping for bin/desk added; test-tests-for passes.

Delivery: Core b89df0f and parent c1dd980 pushed. Dev installed/reopened; idle-rule service restart healthy at 14:51:33 local. Installed Dev agent read confirms the complete tasks inventory. Pre-install backup: build/backups/desk-intake-deduplication/20261106-145110-desk-dev.json. No real-app shipment or new phone binary (service/CLI-only fix). The full-suite attempt ended without a final summary after 9 passes and a chat-rendering failure (No manual report); chat-switch-perf was last started. Results are partial in build/desk-dedup-full-suite.log. The Desk-specific checks passed as recorded; broad coverage remains partial. Existing duplicates are preserved.


Real shipment November 6: Shelby said Ship. The Desk deduplication source is included in the combined Core 23f6dd6 / parent b1fce96 release. Real Mac installation succeeded and the service restarted safely between replies onto the General-capable build. Updated phone app installed/opened directly on Shelby's Duo. The seven morning-priorities entries were migrated to General with exact allowed deltas and unchanged run-state bytes; no source review was triggered by migration. Focused Desk results remain valid; broad validation remains incomplete with disclosed baseline fixture failures.

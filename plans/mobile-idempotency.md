# Safe mobile mutation retries (#4)

Mobile POST requests currently retry every saved Mac address after a transport error. If the Mac applied a request but its response was lost, a retry can send another message, create another chat, or fork again. Add operation identity and bounded response replay; preserve intentional repeated messages.

Issue: https://github.com/shelbyklein/chatterbox/issues/4
Tracker plan: D7DCCD57-BFB6-414B-8EA0-FF2A422F0D2A

Current evidence: MobileStore.raw applies its host retry loop to every HTTP method; CompanionServer.respond applies mutations without an operation identity. Baseline 28652e8. Existing draft protection (#5) stays untouched.

[Request flow](assets/mobile-idempotency/flow.mmd)

## Success criteria
1. Each logical mutation carries one UUID across address fallback, independent of message text (transport regression).
2. Authenticated same-device retries return the original response and produce exactly one message/chat/fork (isolated real server routes and dropped-response test).
3. Different devices/UUIDs stay independent; mismatched payload reuse, expiry and server restart never repeat an uncertain operation (regressions).
4. Bounded retained replies and conservative old-server fallback; uncertain outcomes show a check-before-retry error (regressions).

## Tasks
| ID | Acceptance (matches issue criteria) |
|---|---|
| CB4-1 | Assign a stable operation ID before the first mutation attempt and reuse it across retries. |
| CB4-2 | Server deduplicates per paired device/operation and returns the original result. |
| CB4-3 | Test a successful mutation with its first response deliberately dropped: exactly one message/chat/fork is created. |
| CB4-4 | Handle uncertain outcomes visibly rather than silently replaying an unsafe mutation. |

## Implementation decisions
- Authenticated read-only capability preflight before mutations. Server advertises a process incarnation and its clock time. Each fallback verifies the same incarnation; an older server gets at most one mutation attempt.
- Headers carry operation UUID/incarnation/issuance time. All authenticated mobile mutations use the protocol; local agent traffic and pairing remain unchanged.
- Main-actor server reserves before mutation and caches original responses per device+UUID. Fingerprints include method, target, body and issuance; changed payload reuse is rejected.
- Ten-minute validity window, 512 records, 32 MiB replies. Expired requests are rejected, not re-executed; full ledger refuses new work before execution. Oversize replies retain an uncertainty tombstone rather than unbounded bytes. Restart changes incarnation, so a lost old reply cannot re-execute on a fresh ledger.
- No durable migration or claims of exactly-once transactional persistence across app crashes; such cases visibly require checking outcome.

## Deliverables and verification
Scoped code, local plan and tests committed/pushed; signed Mac/mobile builds installed under standing authorization. Keep GitHub body/comments/labels/state unchanged per Shelby's instruction; tracker/local evidence records progress instead.
Run `scripts/test-mobile-idempotency.sh` for cache/transport/actual server route behavior, including dropped response. Run signed Mac/mobile builds; check installed Mac binary and actual physical-device install/launch results. Existing composer lifecycle regressions protect draft handling. No visual redesign; inspect the error text used by existing error presentation.

## Boundaries, rollback, questions
Do not delete transcripts, dedupe text, change selected model/access/routing, trigger paid inference, change pairing tokens, or touch the golem-rig worktree. Revert scoped commit and reinstall previous build to roll back; no transcript/schema migration. Legacy mobile remains usable but is not granted safe retry semantics until updated. No blocking questions. Previous installed Mac app backed up to /tmp/Chatterbox-before-issue4.app before replacement.

## Work preparation
Shelby authorized work on #4 now and previously authorized commit/push/install/restart. Linear: tightly coupled protocol/client/server; executor gpt-6.1-sol, medium (verified current session turn_context). No agent delegation. R1–R13 pass, 2026-10-02; R7 matches the issue's unnumbered acceptance criteria without editing GitHub. Run 307978FE-4ED5-444B-A920-775F68FE19EB linked to this session's verified JSONL.

## Verification evidence
- Initial `scripts/test-mobile-idempotency.sh`: passed all actual authenticated listener tests (Golem + regular chat, create and fork with discarded first replies), response-byte replay, distinct intentional-repeat IDs, device/payload/authorization isolation, expiry/eviction, incarnation restart, cache limits, old-server refusal and definitive-error handling.
- Existing draft lifecycle suite passed consume/persistence, edits and attachments during acknowledgment, failure recovery, stale callbacks and intentional repeats.
- Final idempotency run passed at /tmp/chatterbox-idempotency.FPwAno, including unreadable successful mutation replies. Three iPhone simulator UI composer tests passed (0 failures) at /tmp/chatterbox-mobile-composer.L7BSiH; delayed acknowledgment for Golem and regular chat, intentional repeats and failure recovery. Golem proof screenshot inspected. Signed Mac and mobile builds passed; iPhone 17 Pro and iPad mini final installation receipts succeeded (17:58). Mac signature/binary match verified on initial installation; final receipt below. No paid agent inference or real transcripts used in tests. Lost responses were discarded by the transport test after real URLSession delivery; physical cellular packet loss was not induced.

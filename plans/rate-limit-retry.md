# Switch provider after a rate limit

When Claude or Codex cannot answer because of a provider rate/usage limit, iOS currently shows a raw error with no useful next action. Add an explicit suggestion and a button to switch to the other provider and repeat the failed request in the same chat. Only tapping that button sends the retry; account settings and normal failures retain their behavior.

## Work preparation

Scope confirmed by Shelby's direct implementation request. Tracking: [issue 62](https://github.com/shelbyklein/chatterbox/issues/62). Linear execution because engine detection, companion contract and mobile presentation depend on each other; current session, exact model/effort unavailable. Baseline parent `2192885`, Core `c24a0bd`. Readiness: R1–R13 pass; implementation authorized now, Dev activation has standing approval, real activation and closure remain gated by Shelby. No blocking questions.

Evidence: `ChatSession+Claude.swift` records the screenshot's failure as a terminal provider notice; `ChatSession+Codex.swift` records corresponding terminal errors. `ChatDetailView.swift` renders those rows without a retry action. [Supplied screenshot](</Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/B59C53BC-7B73-4360-85EC-719653C15D85/Feedback.png>).

```text
Current: original request → provider rate-limit error → message box
Target:  original request → provider rate-limit error
                           Claude is rate-limited. Try Codex instead.
                           [Switch to Codex and ask again]
                           → same thread, original request + attachments, using Codex
```

## Success and delivery

1. Completed rate-limited Claude/Codex turns expose the correct other provider; active turns, ordinary errors, older failures, open models and manually switched chats do not. Verify engine/service tests.
2. One validated companion mutation switches the chat and resends the original request with its attachments. Stale/repeated actions are refused; no automatic replay or new chat. Verify service request and attachment arguments with no real model calls.
3. iOS presents a clear native action beneath the error, locks it while submitting and preserves the composer draft. Verify native iPhone and Duo UI flows with captures.
4. Commit/push Core then parent, install Mac Dev plus idle-safe service restart and direct phone Dev. Report installation and activation separately. Real apps wait for Ship; no TestFlight or account configuration changes.

## Tasks

- [x] R1 Detect eligible failures and expose an optional retry offer; validate switch-and-resend by original request ID. Acceptance: service fixtures cover both providers, unrelated errors, stale/busy rejection and original text/attachments, without starting models.
- [x] R2 Add the iOS suggestion/action and native UI coverage. Acceptance: correct label, single retry, same thread, saved draft and readable iPhone/Duo captures.
- [x] R3 Run focused checks, commit/push and deliver to Dev. Acceptance: source revisions, observed installation/restart state and evidence recorded, issue left open for activation/acceptance.

## Boundaries and validation

Do not repair provider credentials, change accounts, change proxy routing, automatically switch on failure, replay older requests, publish, run live prompts or extend this to a Mac UI redesign. The incoming provider retains this chat's existing model/effort choices and normal transcript handoff. Existing error text remains available for diagnosis. The server owns eligibility; clients cannot replay arbitrary messages through this action. The server rechecks eligibility against the current thread before changing anything.

Run focused `scripts/test-desk.sh` service coverage and the new `testRateLimitRetry` flow via `scripts/test-mobile-home-nav.sh iphone` and `duo`, selected with `scripts/tests-for.sh --why` / `--run --fail-fast`. Inspect actual native captures. Run `scripts/check-sources.sh` and diff checks. No new target sources are planned. Full release coverage is deferred to Ship.

Rollback: revert this task's scoped commits and reinstall Dev with repository scripts, using the default safe service restart. No migration or stored-schema change is required; the wire offer is optional and older clients ignore it. The new endpoint only mutates a chat after the user's tap. Test fixtures isolate data; real data and provider accounts remain untouched.

## Verification

See [validation and native captures](../design/rate-limit-retry/validation.md). Service/Desk coverage passed with 17 new retry checks and no agents started. Final iPhone 17 Pro/iOS 26.2 flow passed in 29.567s; final Duo/iOS 27.1 flow passed in 36.809s. Both directions resend once, remove the offer and preserve the draft. Rendered captures were inspected, including confirmation of the explanation wrapping fix. These are focused checks; the full release suite is deferred to Ship.

## Dev delivery

Core `368b1c2` and parent source `dbf926a` committed/pushed to main. Mac Dev installed/reopened, default idle restart at 14:06:43, service PID 57993 healthy at 14:06:46; a fresh socket read also returned ready and the installed app/service match the build bytes. Phone Dev installed on Shelby's Duo; automatic launch could not be confirmed, so open it on the phone. Real app/service executable and automation-config hashes remain unchanged. [Delivery metadata](../design/rate-limit-retry/dev-delivery.json). Real shipment and issue closure remain pending Shelby.

## Real shipment

Shipped November 7 after Shelby explicitly accepted the known chat-switch failure and incomplete release coverage (11 passed, 1 failed, 101 not run). Real Mac installed/reopened, service healthy after a between-turns restart; real Duo installed and opened, widget extension included. Physical widget appearance remains unverified. See [shipment evidence](../design/rate-limit-retry/real-delivery.json). Issue remains open for acceptance.

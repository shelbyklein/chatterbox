# Rate-limit retry validation

Baseline: parent `2192885`, Core `c24a0bd`. iOS now shows a suggestion and explicit **Switch to Codex/Claude and ask again** action under a terminal provider rate-limit failure. No automatic switch occurs. The service validates the original user-row ID and target provider, switches through the existing chat handoff, then resends its original text and stored attachments in the same session. The mobile composer is not consumed.

## Behavior and compatibility

- Eligibility requires an idle, unarchived, non-reconnecting direct-agent chat, no pending approval/question or pressure hold, a terminal provider failure notice and a usable, unqueued original request. Assistant text quoting an error does not qualify. Manually switching provider, sending a newer request or finishing a retry invalidates the old offer.
- `ChatDetail.rateLimitRetry` is optional; older phone clients ignore it and older services omit it. `POST /v1/chats/ID/retry-rate-limit` requires pairing and checks fresh eligibility before changing anything. Malformed payloads return 400; stale/busy/wrong-provider requests return 409. Missing attachments are rejected before switching. Normal authentication errors and open-model failures retain their prior UI.
- The action uses the provider's existing per-chat settings/defaults and ordinary transcript handoff. It does not change credentials, account routing or proxy configuration. Existing diagnostic text stays visible.

## Validation

- `scripts/test-desk.sh` passed (`build/rate-limit-retry/service-verified.log`; fixture `/tmp/chatterbox-test-desk.Kei6Rx`). Seventeen added checks cover Claude and Codex detection, pairing, bad payload, wrong provider, active turn, open model, authentication failure, ordinary quoted text, newer-request rejection, missing attachments, ordering, exact prompt, retained attachment identity, repeated stale action, reverse direction and manual-switch suppression. All existing Desk checks pass; its final assertion confirms no agent started. Dispatch uses an isolated session command stand-in; no real prompt or provider account was used.
- Final iPhone native run: `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testRateLimitRetry MOBILE_TEST_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-2 scripts/tests-for.sh --run --fail-fast tests/mobile-home-nav/HomeNavTests.swift`. **1 passed, 0 failed, 0 not run**, test case **29.567s**, artifacts `build/mobile-home-nav.O3agmp`, log `build/rate-limit-retry-iphone-layout.log`.
- Final Duo native run: `MOBILE_TEST_ONLY=HomeNavTests/HomeNavTests/testRateLimitRetry scripts/test-mobile-home-nav.sh duo`. **Passed**, test case **36.809s**, artifacts `build/mobile-home-nav.h7Ku4I`, log `build/rate-limit-retry-duo-layout.log`.
- Both native runs exercise both provider directions through the real chat view and store request. Each verifies the action label, explanation bounds, one accepted request, correct target, displayed simulated response, offer removal and an untouched `A separate draft` composer. Captures are synthetic native simulator evidence, not physical phone screenshots or a live retry against the rate-limited account. Duo coverage is its closed portrait layout; the existing split-view shell was not changed.
- First render inspection found a clipped explanation. It now takes its full available width and natural multiline height; the confirmation screenshots show complete text on both devices. Source and target styles preserve the existing native chat UI.
- `scripts/check-sources.sh`, fixture Python syntax and parent/Core diff checks passed. No target source files were added, so project regeneration was unnecessary. Selector reasoning is recorded in `build/rate-limit-retry-selection.log`. These are focused checks; no full-release-suite result is claimed.

## Earlier attempts

The first UI run exposed the outer suggestion accessibility identifier overriding the button ID; the group now contains its children explicitly. Subsequent fixture-only failures were a case-sensitive UUID/path comparison and a duplicated reply row ID in the mock server; these were corrected to match Swift UUID semantics and unique transcript identities. Fixture preflight verifies both directions. An obsolete Duo fixture run was stopped after identifying those mock defects; the final Duo run above completed successfully. Mac pressure gates delayed several builds and simulator starts and were never bypassed.

## Captures

[iPhone: Claude limit](iphone-rate-limit-claude.png), [iPhone: Codex limit](iphone-rate-limit-codex.png), [iPhone: request retried and draft retained](iphone-rate-limit-retried-claude.png), [iPhone: reverse retry](iphone-rate-limit-retried-codex.png).

[Duo: Claude limit](duo-rate-limit-claude.png), [Duo: Codex limit](duo-rate-limit-codex.png), [Duo: request retried and draft retained](duo-rate-limit-retried-claude.png), [Duo: reverse retry](duo-rate-limit-retried-codex.png).

Real deployment and issue closure remain pending Shelby. Dev delivery is recorded separately after installation.

## Dev delivery

- Core `368b1c2`, parent source `dbf926a`, both committed/pushed to main before installation.
- `scripts/install-dev.sh` completed successfully (`build/rate-limit-retry-install-mac.log`). Mac Dev reopened. Its default safe restart fired on idle at **14:06:43**, and new service **PID 57993** was healthy at **14:06:46** (app PID 57922). A fresh Dev Unix-socket hello/health check returned ready. Installed app and daemon SHA256 values match the fixed Dev build products; the daemon binary contains the new retry route.
- `scripts/install-phone.sh --dev "Shelby's Duo"` installed `com.shelbyklein.Chatterbox.mobile.dev` successfully (`build/rate-limit-retry-install-phone.log`). The following CoreDevice launch client remained unresponsive for more than two minutes. Only that owned Mac launch client was terminated; the installer finished with **Installed on Shelby's Duo (open it there)**. Phone launch is unconfirmed, not claimed successful. The build is Dev flavor with no embedded widget.
- Real app/service executable and real Automations.json hashes match their pre-delivery values. No real install/restart, account/proxy configuration change, live prompt, live retry or TestFlight upload was performed.
- Read-only simulator tidy reports **0 removable, 8 kept** (`build/rate-limit-retry-tidy.log`). Owned test simulators are shut down; the unrelated active Duo simulator was preserved. No cleanup apply was run.
- [Delivery metadata](dev-delivery.json) records build identity and observed activation separately. The remaining user gate is Ship to the real apps; issue 62 stays open.

## Release check, November 7

Shelby requested Ship. The final-source release run stopped with **11 passed, 1 failed, 101 not run**. `test-chat-switch.sh` failed at `tests/chat-switch/Coordinator.swift:11` (exit 133), the same old-fade assertion previously disclosed. Both that test and `ChatSwitchTransition` are unchanged from the prior shipped baseline (parent `343c0b0`, Core `2ca56b9`). Remaining tests are unverified; this is not a green release suite. Signed Mac and real-phone candidates, including the widget extension, built successfully. No real installation/restart occurred, and real executable/configuration hashes are unchanged. The current coverage decision remains pending Shelby under AGENTS.md. See [release check record](../rate-limit-retry/release-check.json).

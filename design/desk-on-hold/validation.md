# Desk On hold validation

Baseline: parent `57f8e4b`, Core `9ec87f9`. Linear implementation in the main checkouts; scoped files only. Issue [59](https://github.com/shelbyklein/chatterbox/issues/59).

## Behavior

Use a task card's menu to **Put on hold**, then **Resume** to return to the state derived from its preserved thread. Review stays Review; an unstarted task returns to To do. Hold is explicit and durable across source reimports and service reloads. It retains the same task/source/thread IDs and prepared conversation. It is excluded from the other Desk lanes, attention counts, automatic starts and explicit task starts/writeback. A live reply cannot be put on hold; no agent is interrupted. Only Shelby's clients can hold/resume. Older clients ignore the additive payload; newer clients hide hold features against older services. Downgrading the service after using holds requires care: older builds do not understand the saved hold state.

## Focused checks

- `scripts/test-desk.sh`: passes persistence, stable-identity/source reimport, exclusive lanes, socket/HTTP actions, invalid holds, permission checks, old-wire decode and auto-start regressions; fixture confirms no agent was started. Log `build/desk-on-hold-engine.log`.
- `scripts/test-work-threads.sh`: passes existing work-thread lifecycle and permissions. Log `build/desk-on-hold-work-threads.log`.
- `scripts/test-mac-desk.sh`: passes six-column rendering, native Resume click, local stale Needs you/Working exclusion and old-service fallback, plus existing board actions. Log `build/desk-on-hold-mac-final.log`.
- `scripts/tests-for.sh --run --fail-fast scripts/test-tests-for.sh`: 1 script passed, 0 failed, 0 not run. Added direct mappings for Mac Desk and mobile Desk/store views. Log `build/desk-on-hold-selector.log`.
- `scripts/check-sources.sh` and both repositories' `git diff --check`: pass. No source file was added, so no project regeneration required.
- iPhone 17 Pro / iOS 26.2: existing `testDeskFirstTab` passed (29.244 s), existing `testDeskTasks` passed (24.491 s), initial new hold flow passed (57.699 s). Final hold-only iPhone check passed (55.565 s), Duo/iOS 27.1 passed (66.059 s) after tab-spacing refinement. Logs `build/desk-on-hold-iphone-final.log` and `build/desk-on-hold-duo.log`. Phone flows cover menu actions from Review/To do/idle task-backed Needs you; Resume to the original lane; Open and Back; relaunch persistence; failed action leaves the original card; exact hold/resume calls and no start/complete/writeback.

## Captures and boundaries

[Mac fixture](mac.png) was visually inspected. Final [iPhone Review hold](iphone-review.png), [iPhone To do hold](iphone-todo.png), [Duo Review hold](duo-review.png) and [Duo To do hold](duo-todo.png) were visually inspected: all six tabs visible at normal text size, readable cards and Resume/Open controls, no content clipping. Screenshots contain synthetic fixture content. Tests use local isolated servers, not real sources or models. The broad suite was not repeated for this focused Dev change; previously recorded unrelated chat-switch/chat-rendering failures and incomplete release coverage remain unresolved. No full-suite green or real shipment is claimed.

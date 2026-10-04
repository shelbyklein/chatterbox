# Smooth Mac chat switching
Switching chats currently replaces the keyed ChatView immediately, then expands its initial transcript page and repositions the newest message. Shelby reports about a second of visible settling. Stage the replacement behind a brief fade: outgoing content moves slightly left, new content enters from the right, while columns remain stationary.

Current layout: [native Golem capture](/Users/shelbyklein/Chatterbox/Screenshots/mac-unified-columns/golem-1100.png).
![Target flow](assets/chat-switch/flow.svg)
Tracker: local:05E16D87-F743-40C8-822F-276294F0CBEE

Success criteria: the swap occurs only with the chat hidden; rapid selection settles on the newest ID; Reduce Motion never slides; drafts are unchanged; sidebar remains interactive while outgoing chat is disabled. Verify coordinator tests and native ContentView captures of Golem and regular chats. This masks layout work, it does not promise to remove main-thread stalls.

Tasks: FADE-1 implement cancellation-safe staged switching and input gating, tested with normal/rapid/alternate/Reduce Motion cases. FADE-2 exercise real native ContentView with isolated copied histories and inspect captures; assert drafts and column bounds. FADE-3 build, commit/push and install Mac under standing authorization; verify binary and launch.
Deliver code, plan and regression tests committed/pushed; installed Mac build. Preserve mobile, transcript data, routing, model settings and worktrees. No external model requests or paid services. No blocking questions.
Rollback: back up installed app before replacement; restore that bundle or revert scoped commit. No stored data/schema changes.
Work preparation: R1–R13 pass; linear GPT-6.1-Sol Medium, no delegation. Run swiftc coordinator tests, native whole-source harness, signed xcodebuild and scripts/install.sh. Existing transcript entry tasks remain active while hidden; short staging window covers their initial deferred layout. Changes from Settings/web/mini bypass chat-to-chat staging.

## Verification
FADE-1/2 passed: coordinator includes delayed mounting; native production-library captures show outgoing content, blank hidden replacement and incoming content. Rapid selections finish on latest chat. Golem/project drafts and transcript counts remain unchanged;800pt pane bounds pass. Reduce Motion verified in coordinator, not via the OS toggle. Full evidence: tests/chat-switch/verification.md.
![Native transition](</Users/shelbyklein/Chatterbox/Screenshots/mac-chat-switch/sequence.png>)

## Follow-up: remove added lag
Shelby reports the shipped animation lags. The coordinator adds640ms of explicit waits (140+320+180) plus mounting, and disables interaction until the last wait finishes. Keep a70ms outgoing phase and a single16ms post-mount frame, reveal with a100ms fade, and enable interaction at reveal. Do not promise to eliminate the underlying main-thread rendering cost.
Tracker: local:715E0D5E-4893-432C-9026-BA149E0F862A. LAG-1: coordinator tests verify no long pause/lock, mount gating, cancellation and Reduce Motion. LAG-2: native latency/capture/draft checks, signed build, scoped commit/push/install; installed binary match. Linear GPT-6.1-Sol Medium. Existing visual, scope boundaries, standing install authorization and rollback apply; readiness R1–R13 pass. Existing scripts/test-chat-switch.sh is the acceptance path.

## Added scope: collapsed activity with a floating Golem
Shelby requests the right activity panel start collapsed, while Golem remains at his existing upper-right position unless moved into the mini. Keep one live avatar outside the chat-fade surface and panel. Reserve its existing header space when the activity panel is expanded; clicking the avatar or toolbar button toggles the panel. Store expansion in a new preference defaulting false, retaining the old preference for rollback. Native LAG-2 verification also covers collapsed/expanded avatar coordinates, actual avatar click, close, and mini exclusion. Existing screenshot baseline above plus target: the activity list disappears; the120pt avatar stays centered160pt from the right edge,18pt below content top. No model, mood, transcript or mobile changes. Readiness rechecked R1–R13 pass; existing run owns LAG-2, and final install will include both scoped commits.
The actual Golem branch has its own80-row eager DotConversation and ignores generic ChatView page limits. Main Golem now starts with12 conversation rows (Show earlier still adds80); compact/mini remains80. UUID link parsing is deferred to visible reply rows and the fixed regex compiled once. Unused regular-transcript mapping is skipped for Golem. Main inline avatar is suppressed because one live floating avatar now owns that role. Native visual/latest-message and Show earlier checks guard retained functionality.

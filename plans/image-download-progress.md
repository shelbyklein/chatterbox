<!-- image-download-progress-2026-11-14 -->
# Request and track iOS image downloads

Images can leave Shelby staring at a spinner with no way to tell whether anything has downloaded. Add a Download action for an image whose automatic visibility load has not begun, show actual bytes and percentage during a transfer, and retain an explicit restart action while it is loading.

The current screenshot shows two spinner-only images. The resumed implementation in Core/ChatterboxMobile/ChatDetailView.swift and MobileStore.swift adds download state and URLSession progress callbacks, but existing passing image tests do not exercise a partial transfer. Preserve automatic loading, image caching, full-resolution viewing/markup, quick address probes and address-switch recovery. This is phone-only, without a saved-data/protocol change.

[Before](../design/image-download-progress/before.jpeg). Target uses the existing native placeholder and accent:

```text
Not started:       [ ↓ Download image.png ]
Downloading:       [━━━━━━──────────]
                   42% · 120 KB of 290 KB
                   [Restart Download]
Unknown length:    spinner · 120 KB downloaded
Failed:            [Couldn't load. Tap to retry.]
Complete:          image
```

## Work preparation

Shelby requested this change and said Continue after the agent handoff. Continue implementation now; no repeated scope/install question needed. Baseline parent25b32f9/Core6fbcbb2, with the three owned Core files already modified by the prior agent. Seven existing design screenshot changes are unrelated and remain untouched. Linear, one executor for the coupled view/network behavior; current session, exact model/effort unavailable. Readiness R1–R13 pass. Open questions: none. Tracking: [issue70](https://github.com/shelbyklein/chatterbox/issues/70).

## Success criteria and deliverables

- A slow native image transfer visibly shows nonzero progress, percent and received/total bytes, and Restart Download starts a new request without leaving the chat. Unknown totals show received bytes without an invented percentage.
- Existing cancellation, retry, scrolling and cache behavior passes its focused tests; cancelled transfers cannot overwrite the progress of a replacement.
- Code, changelog, focused test evidence and inspected native captures committed/pushed Core-first, then the real phone app installed on Shelby’s Duo. Keep the issue open for physical-user acceptance.

## Tasks

- [x] IP1 Review and finish the handoff implementation, preserve historical changelog entries, and guard progress state across restarted transfers. Acceptance: only current transfer callbacks update the placeholder; idle/loading/error states all offer the intended action.
- [x] IP2 Add and run slow-stream native tests, including restart and missing total, and inspect native captures. Acceptance: percentages/data advance before completion, restart increments the fixture's request count, image displays after release, and existing image/scroll/server-request checks remain covered.
- [x] IP3 Commit/push and directly install the real phone app. Acceptance: installer reports actual installation/launch separately; record results, limitations and any phone reachability failure.

## Verification and rollback

Already passed detached run `imgprog`: scripts/test-mobile-idempotency.sh, test-mobile-images.sh and test-mobile-scroll.sh (3 passed, 0 failed). Use `scripts/tests-for.sh --why` for changed paths; add direct mappings for missed image/network coverage. Run `scripts/detach.sh image-progress-verified scripts/test-mobile-images.sh iphone` for new behavior, retaining existing image cases; rerun affected coverage only if product/network changes justify it. Native entry: open the fixture Projects chat → inline image. Inspect known/unknown-length progress and completed image captures, at most two batched visual rounds. No full navigation or release suite for this scoped image change.

After tests pass, commit Core product/changelog, then parent tests/plan/captures/gitlink; install with `scripts/install-phone.sh "Shelby's Duo"`. No Mac/service/Dev install or TestFlight. Exclude the unrelated screenshot modifications and all broader layout/route changes. No data migration or stored-image format changes; rollback reverts this task’s commits and rebuilds/reinstalls the phone app from the previous source. Existing cached images and pairing remain usable. Issue closure requires Shelby’s acceptance.

## Verified source

Core5cdbbb0. Detached `image-progress-verified` exit0: six image UI tests, seven scroll UI tests and the request-safety suite passed. One native visual round verified25%/50% progress, restart, unknown total and completion. [Evidence](../design/image-download-progress/validation.md). Source membership/whitespace checks pass. Real phone installation is next; unrelated design screenshots stay untouched.

## Delivered

Parent81410b1/Core5cdbbb0 committed and pushed; real Release app installed and opened on Shelby’s Duo (iOS27.3), strict signature passed. [Delivery record](../design/image-download-progress/delivery.json). All selected tests passed; native captures inspected. No Mac/service/Dev install or TestFlight. No work threads existed. Keep issue70 open for physical-user acceptance; unrelated existing screenshot modifications remain uncommitted.

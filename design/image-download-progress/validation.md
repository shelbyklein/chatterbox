# iOS image download verification

Source baseline parent25b32f9/Core6fbcbb2, plus the resumed image-progress implementation. Issue70. Scope is inline phone images and their download callbacks; no service, host, pairing, protocol or stored-image format change. Seven unrelated existing screenshot modifications remain outside this work.

The initial detached run `build/runs/imgprog.status` completed exit0: three scripts passed (mobile-idempotency, mobile-images, mobile-scroll). Its image cases covered ordinary automatic retry, cache reuse, failed-load retry and cancellation/reentry. They did not cover actual progress, so native streamed-download cases were added before delivery.

Additional checks use a real valid uncompressed PNG served in quarters by the isolated fixture, with explicit gates at25% and50%. Known-size checks require percent plus received/totalKB before completion; Restart Download must cause a new request from the same chat. Missing-Content-Length checks require receivedKB and no invented percent. Native captures are retained. The fixture contacts no real service or provider.

The view scopes updates/defer cleanup to the current load so a cancelled request cannot clear a replacement's state. Manual requests consume their override once, and scene activity is tracked separately from scroll visibility to retain background cancellation. The network callback ignores quick address-probe bytes. Historical What's New entries are preserved; today's entry describes the new controls.

Current focused run: `scripts/detach.sh image-progress-verified bash -c 'scripts/test-mobile-images.sh iphone && scripts/test-mobile-idempotency.sh && scripts/test-mobile-scroll.sh iphone'`. Build and test resources use the repo's normal locks, fixed DerivedData folder and simulator cleanup. Direct selector mappings now include the image and request-envelope coverage that inference missed. No full navigation/release suite requested or run for this scoped behavior change.

Final results, inspected screenshots, commits and physical installation are recorded below when complete. Simulator evidence establishes native behavior/layout; physical-user acceptance remains pending.

## Native progress evidence

All six image UI cases passed in `build/mobile-images.OKGthZ` (iPhone17Pro/iOS26.2). The new known-size/restart test passed in13.132s; unknown-total test10.279s. Existing cancellation/reentry18.934s, manual retry10.106s, persistent-failure/reentry22.368s and automatic recovery/cache23.160s all passed.

One batched native visual inspection, with no correction needed: [25% —38KB of154KB](image-download-quarter.png), [50% —77KB of154KB after restart](image-download-half-after-restart.png), [unknown total —38KB downloaded](image-download-unknown-total.png), [completed image](image-download-complete.png). Bar, caption and restart control fit within the existing placeholder. The actual partial byte stream, restart request count and completion are verified by the native tests, not a mockup. Unknown totals retain the activity indicator and received bytes rather than claim a total/percent.

Source membership and both whitespace checks passed. The request-envelope and scroll suites are still running on this same product source. The reachable physical Duo reports iOS27.3; simulator verification above is on26.2. No physical installation claimed yet.

## Final focused results

Detached `image-progress-verified` completed **exit0**. Six image UI tests passed; all seven scroll UI tests passed (238.341s total), including early-scroll freeze, sending, streaming, tall-image loading, preview and app reactivation. The request-safety script passed its authenticated HTTP/replay checks, uncertainty and definitive-failure behavior, quick dead-address probe, and stale-address pruning. Scroll artifacts: `build/mobile-scroll.RcKNxI`; image artifacts: `build/mobile-images.OKGthZ`. No failed or unrun cases within these selected suites. Broader navigation/full release suites were not run for this image-only change.

Core product/changelog committed as5cdbbb0. The test fixture now exercises real partial transfers; selector mappings explicitly connect image and request-safety coverage. Source membership and whitespace checks passed. Phone delivery pending.

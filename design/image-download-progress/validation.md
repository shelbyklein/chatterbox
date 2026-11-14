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

## Real phone delivery

Parent81410b1/Core5cdbbb0 were committed/pushed Core-first, then `scripts/install-phone.sh "Shelby's Duo"` built Release and reported **Installed and opened on Shelby's Duo**. Real bundle `com.shelbyklein.Chatterbox.mobile`; strict signature verification passed. The paired Duo reports iOS27.3. Physical UI acceptance is pending Shelby; the native captures above are simulator evidence. No Mac/service/Dev installation or TestFlight. `work list` reported no work threads. The read-only tidy report was started detached; no cleanup was applied. [Delivery record](delivery.json).


## Idle Download follow-up — November14

Physical acceptance found a gap after the first install: two referenced Concept Art PNGs remained at idle Download. Both original files exist (2,034,569 and1,511,972 bytes). Existing Mac log entries show prior successful124KB/51KB transfers, but have no timestamps/chat IDs, so they do not prove these new taps reached the Mac. Do not infer an on-phone root cause from those lines.

A new native regression suppresses the viewport callback in DEBUG only, taps the real idle Download button, pauses a real PNG transfer at25%, backgrounds/returns, then releases it. The previous code starts the request but loses manual intent on task replacement: progress disappears after returning, only one request reaches the fixture, and the final image never displays. Baseline artifacts `build/mobile-images.nu3vOW`, log `build/runs/image-idle-before.log`:1 test failed with4 assertions. After the test completed, Xcode stalled collecting diagnostics; it was stopped using safe_stop after preserving the failure log. This deliberate failing baseline is separate from final verification.

The fix retains a manual request until success/failure or genuine view departure. Task identity uses effective eligibility, so visibility changes cannot cancel a deliberate download. Backgrounding still cancels network work; returning resumes a requested image even if viewport detection remains missing. Automatic offscreen cancellation and bounded retry behavior stay intact. Manual foreground taps also remain valid during an inactive scene transition. No protocol/data/cache-format change.

Final detached `image-idle-fixed` exit0:7 image UI tests passed (116.534s), including the new idle/foreground regression15.585s;2 selected scroll cases passed (49.277s: tall-image reading position and reactivation). Image artifacts `build/mobile-images.zGYcM4`, scroll `build/mobile-scroll.2oqllT`. Full navigation/release suites were not run for this image-only lifecycle change. Source membership, selector mapping and whitespace checks passed; comma-separated scroll test selection exercised both intended cases.

One batched native capture inspection: [idle tap starts progress](idle-download-started.png), [progress resumes without another tap](idle-download-resumed.png), [completed image](idle-download-complete.png). Tests verify the exact2 fixture requests and final decoded image; screenshots are native simulator evidence, not the actual Concept Art images. The reactivation captures omit some surrounding system/app chrome; the targeted progress and image remain visible. No layout changes were made.

Physical diagnostic runner could not install on the current Duo beta:Root install style is not supported. Two attempts (standalone/hosted) failed before running; a device app inventory confirmed neither probe bundle was installed. This blocks direct verification of the user's exact taps, not the simulator regression. Real installation and physical acceptance are recorded separately. Keep issue70 open.

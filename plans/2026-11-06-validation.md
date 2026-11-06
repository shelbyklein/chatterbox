# Validation for Studio suggestions, source links, Activity and Desk refresh

Linear work in the existing checkout; no work threads. Targeted checks pass on the final implementation:

- Studio identity matcher: 30 checks.
- Source-link service import: 256 checks; connector: 36; initial automation source instructions: 55.
- Final Desk service and CLI checks: 257; automation routines: 66; Mac Desk: 154.
- Focused Duo UI: Activity migration/navigation/pin preservation (24.278s), Desk source-check button/progress/report (10.490s), both pass.
- Earlier iPhone Activity dismissal/swipe test passes.
- `check-sources.sh`, Python fixture syntax, root/Core diff checks pass.
- Inspected actual Mac and Duo screenshots in `design/desk-sources/` and `design/mobile-activity/`.

No live Outlook/ClickUp check ran; the automation tests use stand-in sessions. Source account access, report completeness and incremental coverage are unverified. The prompt requires each source's last verified checkpoint, with partial sources left unchanged; the UI says Last requested rather than claiming successful coverage.

## Full-suite attempt

One `scripts/tests-for.sh --run --all` attempt, aggregate `build/studio-suggestion-full-suite.log`, individual logs in `build/test-logs`. Started for Studio suggestions, with later user requests added while it ran, so it is not a uniform final-tree pass. Final affected checks were rerun separately above. Finished: 98 scripts passed, 12 failed (exit 1). The live VNC script is counted among passes by the runner but actually skipped by default; no live VNC validation is claimed.

Raw failures:
- `scripts/test-chat-switch.sh`: FAIL (133).
- `scripts/test-empty-chat-persistence.sh`: FAIL (1).
- `scripts/test-fast-mode.sh`: FAIL (1).
- `scripts/test-mac-documents.sh`: FAIL (133).
- `scripts/test-mobile-ats.sh`: FAIL (2).
- `scripts/test-mobile-home-nav.sh`: FAIL (64).
- `scripts/test-mobile-images.sh`: FAIL (65).
- `scripts/test-mobile-pdf.sh`: FAIL (1).
- `scripts/test-mobile-promotion.sh`: FAIL (1).
- `scripts/test-mobile-push-ui.sh`: FAIL (65).
- `scripts/test-mobile-scroll.sh`: FAIL (64).
- `scripts/test-model-status-layout.sh`: FAIL (1).

Interpretation:
- Fast Mode and empty-chat initial compile runs overlapped source edits; those runs are invalid. Stable reruns: Fast Mode passes; empty-chat still fails `Studio chat is back after relaunch`.
- Chat-switch crashes in `policy/Coordinator.swift`; Mac documents crashes on its expected rendered-document assertion. No fresh main-baseline comparison was done here.
- Mobile ATS requires a live Tailscale address argument; mobile PDF lacks Python `reportlab`.
- Promotion test cannot resolve AutomationRunner; model-status-layout test cannot resolve AppModel in its standalone harness.
- Home-nav broad run had 43 cases pass, one Studio-thumbnail failure, then stalled in Xcode simulator-diagnostics collection. Its owned collector was sampled and stopped via safe_stop, as were obsolete focused-test collectors after assertions on wrong selectors.
- Mobile scroll app became stuck in a layout/event-idle loop; its exact owned test runner was sampled and stopped via safe_stop. No agent host or service was killed.
- Mobile images has download-count assertions failing; push UI cannot find its Notifications button.
- Live VNC spike is now opt-in and skips by default, so full tests do not wait indefinitely on a Mac password dialog.

## Delivery and limits

Earlier Studio/source-link build installed to Mac Dev; service healthy after 2s. Dev phone installation failed because Xcode could not resolve the paired Duo destination. Before Shelby said Ship, no real-app install, real-service restart or TestFlight upload was performed. The authorized ship is recorded below. Final Mac Dev update for Activity/Desk refresh installed and reopened; its service restarted on the idle rule at 13:44:36 and reported healthy after 1s at 13:44:38 local. Dev-phone installation was not retried; only simulator verification is claimed for the latest phone changes.

The two old screenshot email tasks still have no verified original message IDs/URLs. Read-only source inspection did not recover links; no URLs were invented and real Desk/mailbox data was not modified.

## Test-log exposure

A pre-existing bare `export` in test-chat-bottom emitted inherited environment values. RunCloud and ElevenLabs credentials were present; one tool output exposed the RunCloud key. Removed bare environment dumps from 13 scripts, added a source-check guard, and redacted four affected local logs without printing secret values. Recorded chat output cannot be erased here. Rotate both credentials and update Chatterbox Settings → Secrets. No rotation was performed.

## Authorized ship — 2026-11-06

Shelby said ship. `scripts/ship.sh` shipped 2c8e824: pushed, installed and reopened the real Mac app, with its installed executable matching the build. Default `restart-service.sh` used the between-turns rule at 14:34:17; real service reported health OK after 16s at 14:34:34. A read-only socket check confirmed the Desk source-check state and configured intake routine; no source pull was started.

`scripts/install-phone.sh "Shelby's Duo"` successfully installed the real phone app. Launch was refused because the device was locked, confirmed by MobileBuildMCP's CoreDevice launch diagnostic; no further unlock/launch attempts were made.

TestFlight build **202611061433** uploaded successfully. Apple reports VALID / IN_BETA_TESTING. A separate betaGroups query confirms the existing **Shelby** internal group has automatic access to all builds and explicitly lists this build. No tester access was expanded, and no App Store release was submitted.

No new work threads were created for these changes. The shell has no current Chatterbox chat ID and `work list` could not infer a working session in this folder; no Desk tasks were changed based on a guessed identity. Earlier completed work threads were already cleared, according to the conversation history.

Delivery logs: build/ship-20261106.log, build/ship-phone-20261106.log, build/ship-phone-launch.json, build/ship-testflight-20261106.log and build/ship-testflight-status-20261106.log. The earlier full-suite failures and unresolved legacy email links remain as recorded above.

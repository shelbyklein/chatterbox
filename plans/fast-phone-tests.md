# Faster phone tests: logic and snapshots first, a few UI tests in parallel

## Summary

The iPhone suite (tests/mobile-home-nav, about 46 XCUITests) launches the app and taps through it
for every check, so one run takes about 30 minutes and holds a simulator throughout. Most of those
checks are logic or layout, which can run in seconds. Queued 2026-11-05 by Shelby, to start after
the test-concurrency work lands (both touch the test scripts).

## Target

- **Logic tests (no simulator):** MobileStore and the phone's view models against the fixture
  server (tests/mobile-home-nav/server.py) or recorded responses: Desk board columns and
  counts, start step bodies, settings changes, connection and stale states, list grouping and
  nesting, activity rules. Swift test target or a script like the Mac's tests/*/main.swift.
- **Snapshot tests (one booted simulator, no UI automation):** render each phone screen and
  state offscreen (ImageRenderer in a unit test bundle) to PNGs, compare with references with a
  small tolerance; dark and light; iPhone and the open Duo width. Updating references is one
  command.
- **UI tests (~10):** only real gestures and flows: swipe actions, sheets, navigation, the
  title dropdown, the right rail, peek, pairing. Run with Xcode parallel testing
  (-parallel-testing-enabled YES, worker count from the simulator slot / pressure level).
- scripts/tests-for.sh maps phone changes to the logic and snapshot tests; the UI set runs in
  the full suite (before reporting done / ship).
- Target: a typical phone change tests in 1–3 minutes; the full phone suite under ~8 minutes.

## Tasks

- [ ] F1 Inventory the 46 UI tests: each one's checks, classified logic / snapshot / flow.
- [ ] F2 Logic test target + the checks moved there (same assertions).
- [ ] F3 Snapshot tests + references, update command, tolerance.
- [ ] F4 Trim UI tests to flows; parallel testing; slot-aware worker count.
- [ ] F5 tests-for map, AGENTS.md, timings before and after.

## Not changed

What the tests assert (coverage moves, it isn't dropped); the Mac test harnesses.

## Rollback

Revert the commits; the old UI tests are in git history.

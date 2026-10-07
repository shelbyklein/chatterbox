# Working in this repository

Instructions for any agent (Claude, Codex) working on Chatterbox. Several agents work here at
once, and Chatterbox runs the chats they work in, so leftovers and blind restarts hurt other work.

## Build and test hygiene

- **Builds go in four folders only**, one build each, reused run to run:
  - `build/DerivedData`: the Mac app, service and host (`install.sh`, `ship.sh`, Mac tests)
  - `build/DerivedDataMobile`: iPhone/iPad device builds
  - `build/DerivedData-MobileTests`: simulator tests
  - `build/runtime`: the service built by `scripts/build-chatterbox-daemon.sh`

  Never build into `/tmp` or a per-run folder. Each extra build leaves a full app copy that macOS
  then offers as Chatterbox.
- **Test scripts clean up after themselves.** Every `scripts/test-*.sh` starts with
  `source "$(dirname "$0")/lib/test-hygiene.sh"`; new ones must too. On exit it stops what the run
  started and deletes app bundles in its temp folders, keeping logs and screenshots.
  `KEEP_TEST_BUILDS=1` keeps the builds for debugging.
- **Never stop a process blind.** An idle-looking host can be carrying live chats. Use `safe_stop`
  from `scripts/lib/safe-stop.sh`, which refuses when Claude or Codex work runs under the process.
  Never kill `chatterboxd` or `ChatterboxHost` directly.
- **Restart the service only with `scripts/restart-service.sh`.** It waits for every reply to
  finish by default (`--now` doesn't wait, `--app` reopens the app too), replaces any restart
  already queued, and reports to `~/Library/Application Support/Chatterbox/Diagnostics/service-restart.txt`.
  Restarts that interrupt replies need the user's go-ahead.
- **Install only with `scripts/ship.sh` or `scripts/install.sh`.** Never `open` the app from an
  agent shell: it would inherit the service's `CHATTERBOX_*` variables. Installing restarts the
  app the user is chatting in, so ask first.
- **New source files need the project regenerated.** After adding a file to `Core/` or any
  target, run `xcodegen generate` and commit `Chatterbox.xcodeproj`. `ship.sh` runs
  `scripts/check-sources.sh`, which stops when the project is out of date or a hand-written
  source list names a missing or duplicate file.
- **Commit as you go.** When a task is done and verified, commit and push it before starting the
  next, so finished work never waits for another session to sweep it up. Don't commit another
  session's unfinished work.
- **Remove your scratch.** Temporary worktrees and clones (under `/tmp`) go when you're done with
  them.
- **Tidy at the end of a session.** `scripts/tidy.sh` reports leftover test processes, temp and
  build folders, app copies, test simulators and queued restarts; `scripts/tidy.sh --apply`
  removes them after the user's OK. `/dev-sync` runs it as part of reconciling.

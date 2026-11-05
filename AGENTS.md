# Working in this repository

Instructions for any agent (Claude, Codex) working on Chatterbox. Several agents work here at
once, and Chatterbox runs the chats they work in, so leftovers and blind restarts hurt other work.

## Chatterbox Dev: where new work is tried

Chatterbox Dev is a second, separate copy that runs beside the real app (plans/dev-environment.md):
`/Applications/Chatterbox Dev.app`, its own service `chatterboxd-dev` (LaunchAgent
`com.shelbyklein.chatterboxd.dev`), host, data (`~/Library/Application Support/Chatterbox Dev`),
Studios (`~/Chatterbox Dev/Studios`), ports (phone 47421, Bonjour `_chatterbox-dev._tcp`, connector
47431 on this Mac only) and iPhone app (Chatterbox Dev, no widget). Its identities are all in
`Core/Shared/Flavor.swift`; the build configuration `Dev` makes it.

- **New work is installed to Dev:** `scripts/install-dev.sh` builds this checkout, replaces only
  Chatterbox Dev, restarts only Dev's service (after its replies finish; `--now` doesn't wait) and
  reopens only Dev's app. Restart Dev's service alone with `scripts/restart-service.sh --dev`.
  On the phone: `scripts/install-phone.sh --dev "Shelby's Duo"`.
- **The real app updates only when Shelby says ship**, batched: then `scripts/ship.sh` (or
  `install.sh`) and `scripts/restart-service.sh` for the real service, as below.
- **After a Dev delivery, offer a Ship button** instead of "say ship when you want it": end the
  reply with an action block (the app shows its lines as one-tap buttons that send the text as
  Shelby's message), e.g.

  ````
  ```actions
  Ship to the real app | ship
  ```
  ````

  Add another line only for an obvious next step (`Start the next part | start the next part`).
  A button only sends text; tapping Ship is Shelby saying ship.
- Dev never touches the real app, service, data, ports, pairings or `~/.local/bin` links. Keep it
  that way: a new identity (path, port, id, label, Keychain name) goes in `Flavor.swift` with a
  value for each copy, and `scripts/test-flavor.sh` checks the real ones haven't moved.

## Build and test hygiene

- **Builds go in these folders only**, one build each, reused run to run:
  - `build/DerivedData`: the Mac app, service and host (`install.sh`, `ship.sh`, Mac tests)
  - `build/DerivedDataMobile`: iPhone/iPad device builds
  - `build/DerivedData-MobileTests`: simulator tests
  - `build/runtime`: the service built by `scripts/build-chatterbox-daemon.sh`
  - `build/TestFlight`: the newest TestFlight archive (`scripts/testflight.sh`)
  - `build/DerivedData-Dev`: Chatterbox Dev on the Mac (`install-dev.sh`)
  - `build/DerivedDataMobile-Dev`: Chatterbox Dev on the phone (`install-phone.sh --dev`)

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
  Restarts that interrupt replies need the user's go-ahead. `--dev` restarts Chatterbox Dev's
  service instead (report in `Application Support/Chatterbox Dev/Diagnostics`).
- **Install only with `scripts/install-dev.sh` (Dev), or `scripts/ship.sh` / `scripts/install.sh`
  (the real app, when Shelby says ship).** Never `open` either app from an agent shell: it would
  inherit the service's `CHATTERBOX_*` variables.
- **Routine delivery has standing approval (Shelby, October 10, 2026; since November 4 the Mac
  part goes to Chatterbox Dev).** After requested work is verified, install/reopen Chatterbox Dev
  (`install-dev.sh`), queue any needed Dev service restart with the default
  idle-wait behavior, and upload/distribute the iOS build to the existing internal TestFlight
  group without asking again. Give a brief heads-up before the Mac app reopens and report
  installation, queued/restarted service status, and TestFlight availability separately.
  This does not authorize interrupting active replies, stopping agent hosts, expanding tester
  access, or publishing to the App Store; those still need explicit approval. A later request
  to hold installation or delivery takes precedence.
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

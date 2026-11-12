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
- **Except tiny, low-risk changes, which go straight to the real app (Shelby, November 11).**
  The app is only Shelby's, so a change like a symbol, a word, a color or spacing, Mac or phone,
  skips Dev: verify it (below), commit it, then `scripts/install.sh` + `scripts/restart-service.sh`
  (and `scripts/install-phone.sh "Shelby's Duo"` for the phone). Say it went straight to the real
  app. Anything touching behavior, data, the service's protocol, or several files' logic goes
  through Dev as above. A bad one is undone with `scripts/rollback.sh`.
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
- **After a ship, clear the work threads it delivered:** `work done <id>` (or `work done --ready`)
  from their front thread, so their tasks leave the Desk's Ready column. Tooling that doesn't ship
  is marked done once it's on main.
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
- **A few builds at a time, across every worktree, as the Mac's pressure allows.**
  `scripts/lib/build-lock.sh` (sourced by the build scripts and, through `test-hygiene.sh`, by
  every test) makes `xcodebuild`, `swiftc` and `swift build` wait for a shared slot in
  `~/Library/Caches/Chatterbox/build-lock`, printing "waiting for another build (pid N, worktree
  X)". The slot count follows the service's pressure level (`pressure.json`): 3 at OK, 1 at Busy,
  none new at Overloaded (running builds finish); 2 when there's no current reading. xcodebuild's
  `-jobs` is max(4, cores / builds running), so three builds share the 16 cores instead of each
  taking 8 (4 at Busy). Unbounded builds plus simulator suites once took the Mac to a load average
  of 120. `CHATTERBOX_BUILD_SLOTS=N` overrides the count (not Overloaded's hold);
  `CHATTERBOX_BUILD_JOBS=N` sets `-jobs`. A build run by hand should go through the lock too:
  `source scripts/lib/build-lock.sh` first.
- **New worktrees start warm.** `git worktree add` (yours, or a work thread's) runs
  `scripts/warm-worktree.sh` through a post-checkout hook in the shared `.git/hooks`: it clones
  the main checkout's build folders (the list above, minus TestFlight) into the new worktree
  copy-on-write, in seconds and with no extra disk, leaving app bundles, logs and per-run folders
  behind. A worktree made another way (`--no-checkout`, a fresh clone) runs
  `scripts/warm-worktree.sh` once before its first build; `--install-hook` puts the hook back.
  Never copy build folders with plain `cp`/`rsync` (full copies, app bundles included).
- **Compiles are shared between checkouts.** The build lock's `xcodebuild` turns on Xcode's
  compilation cache in `~/Library/Caches/Chatterbox/CompilationCache` with paths mapped, so a
  compile any checkout already did (same sources, same flags) is replayed, not redone. A new
  worktree's first Mac Debug build went from 49 s to 11 s, iOS Release from 85 s to 7 s (warm
  start plus cache; a module whose sources differ still recompiles). `CHATTERBOX_COMPILE_CACHE=0`
  builds without it. Run `xcodebuild` by hand only after `source scripts/lib/build-lock.sh`,
  or you miss the cache as well as the lock.
- **C and C++ builds go through ccache**, in any project on this Mac: every zsh (so every agent
  shell) gets `CMAKE_C_COMPILER_LAUNCHER`/`CMAKE_CXX_COMPILER_LAUNCHER=ccache` and
  `CCACHE_DIR=~/Library/Caches/ccache` (20 GB) from `~/.zshenv` (`scripts/setup-ccache.sh`).
  CMake reads them when it first configures a build folder; one configured before needs one
  reconfigure. `ccache -s` shows hits.
- **The service holds Chatterbox's work back when the Mac is under pressure**
  (plans/mac-pressure.md). Since November 9 only a truly critical Mac counts: Overloaded once
  CPU or memory use stays over 95% for 2 minutes (Settings → Background service); Busy is off
  by default, and load, swap and temperature no longer decide. At Busy builds go one at a time (three at OK) and new work threads wait to start; at
  Overloaded new builds wait ("waiting: the Mac is overloaded (…)") and work threads don't start
  their next turn. Agents run at nice +10 with build caps (`CMAKE_BUILD_PARALLEL_LEVEL`,
  `MAKEFLAGS`, `CARGO_BUILD_JOBS`) in their environment, in any project. Don't work around it;
  `CHATTERBOX_BUILD_IGNORE_PRESSURE=1` only when Shelby asks.
- **Simulators: a simulator slot and a device per run, shut down when the run ends.** Phone
  suites build with `xcodebuild build-for-testing -testProductsPath "$artifacts/…"` under the
  build slot, then call `test_simulator iphone|duo` (test-hygiene.sh; iPhone and Mac only, no
  iPad runs) and run `xcodebuild test-without-building -testProductsPath …`, which takes no
  build slot. Booting takes a simulator slot (`scripts/lib/sim-lock.sh`,
  `~/Library/Caches/Chatterbox/simulator-lock`): two runs at once (`CHATTERBOX_SIM_SLOTS=N`),
  one while the Mac is busy and none new while it's overloaded (pressure.json), with the same
  dead-owner takeover and "waiting for a simulator slot (pid N, worktree X)" line as builds. The slot picks the device, "Chatterbox test iPhone 26.2" for slot 1 and "… 26.2 #2"
  for slot 2, reused run after run and shut down (not deleted) on every way out, a SIGKILL
  included (a watcher process). Build before booting, never the other way round, so no run
  holds a device while it waits to build. Booted devices are on record in
  `~/Library/Caches/Chatterbox/simulators/<udid>`; `scripts/tidy.sh --simulators` shuts down the
  ones whose run is gone and stops runtime processes of devices that aren't booted. The service
  also shuts down any booted simulator on the Mac that nothing has used for 30 minutes
  (Settings → Background service; `SimulatorSweeper`), never one on record.
- **Test ports: one per run.** Fixture servers (`tests/mobile-*/server.py`) bind port 0 and
  report the port they got; scripts start them with `start_test_server LOG CMD…`
  (test-hygiene.sh), which exports `CHATTERBOX_TEST_PORT` and `TEST_RUNNER_CHATTERBOX_TEST_PORT`
  (xcodebuild hands `TEST_RUNNER_*` to the XCUITests, which pass it to the app as
  `fixturePort`). Engine tests that serve the companion take `CHATTERBOX_COMPANION_PORT=$(free_port)`.
  Never hard-code a test port: two worktrees run the same suite at once.
- **Test scripts clean up after themselves.** Every `scripts/test-*.sh` starts with
  `source "$(dirname "$0")/lib/test-hygiene.sh"`; new ones must too. On exit it stops what the run
  started and deletes app bundles in its temp folders, keeping logs and screenshots.
  `KEEP_TEST_BUILDS=1` keeps the builds for debugging.
- **Tests match the change; the full suite only on a schedule or on request (Shelby, November 11).**
  Run the tests covering each change before Dev delivery, using `scripts/tests-for.sh --why`
  and `scripts/tests-for.sh --run --fail-fast FILE…`. With no files it compares the current
  checkout with origin/main, including Core and uncommitted/new files. When work is already
  committed/pushed, use `--since BASE` with the parent commit before the change or batch:
  `scripts/tests-for.sh --run --fail-fast --since BASE`. It follows that commit's Core gitlink,
  so a clean pushed checkout cannot hide committed Core changes. Record the baseline and results.
  Weigh the tests by the change:
  - *Look or wording only* (a symbol, text, color, spacing, no logic): a build of the affected
    platform plus a look at it (a screenshot or a render test's image). No simulator suites.
  - *Behavior*: the focused tests from `tests-for.sh`, including UI/gesture/rendered checks for
    affected mobile views; don't swap those for a compile or a smaller test.
  `scripts/test-map.txt` adds links the selector cannot infer; add one when coverage is missed.
  **Shipping takes the focused tests of what's in it, not the full suite.** Run the full suite
  (`scripts/tests-for.sh --run --all`, which keeps going past failures) only when Shelby asks
  or on a schedule she set; start it with `scripts/detach.sh` so it outlives the session.
  `scripts/known-flaky.txt` lists tests that fail intermittently for a known reason: they're
  still run and reported ("known flaky"), but don't stop `--fail-fast` or fail the run. Add a
  line only for a diagnosed intermittent failure, with why; remove it once fixed.
  Logs are in `build/test-logs`. A fail-fast run reports passed, failed, known-flaky and not-run
  counts; unrun tests are unverified. Disclose failures and incomplete coverage when reporting
  a ship; never call that green. A bad ship is undone with `scripts/rollback.sh` (below).
- **Never stop a process blind.** An idle-looking host can be carrying live chats. Use `safe_stop`
  from `scripts/lib/safe-stop.sh`, which refuses when Claude or Codex work runs under the process.
  Never kill `chatterboxd` or `ChatterboxHost` directly.
- **Restart the service only with `scripts/restart-service.sh`.** By default it restarts
  between turns: as soon as no reply has produced anything for 3 s (the agents live in the
  hosts, which the service reattaches to; replies carry on), 20 minutes at the latest; the rule
  that fired is in the report. `--now` doesn't wait, `--app` reopens the app too. It replaces any
  restart already queued, and reports to
  `~/Library/Application Support/Chatterbox/Diagnostics/service-restart.txt`.
  Restarts with `--now` while replies run need the user's go-ahead. `--dev` restarts Chatterbox Dev's
  service instead (report in `Application Support/Chatterbox Dev/Diagnostics`).
- **Install only with `scripts/install-dev.sh` (Dev), or `scripts/ship.sh` / `scripts/install.sh`
  (the real app, when Shelby says ship or for a tiny change as above).** Never `open` either app
  from an agent shell: it would inherit the service's `CHATTERBOX_*` variables.
- **Every real install keeps the app it replaced** (zipped in `build/previous`, with its commit).
  `scripts/rollback.sh` puts it back and queues the real service's restart (the service is inside
  the app); run again, it goes forward. `scripts/rollback.sh --show` says what's installed and kept.
- **Long runs go through `scripts/detach.sh NAME CMD…`** (full suites, freeze hunts, anything
  over a few minutes): it runs in its own session, so it survives the agent session ending, and
  writes `build/runs/NAME.log` and `NAME.status` ("exit N" when done). Wait on the status file.
- **Phone UI tests have a time limit:** `xcodebuild test-without-building` runs (build-lock.sh)
  give each test 180 s (`CHATTERBOX_TEST_ALLOWANCE=N`), so a hung app fails in about 3 minutes.
  A test that's long by design sets its own `executionTimeAllowance` (up to 600 s), with why.
- **Routine delivery has standing approval (Shelby, October 10, 2026; updated November 6).**
  After requested work is verified, install/reopen Chatterbox Dev (`install-dev.sh`) and queue
  any needed Dev service restart with the default idle-wait behavior. Build only the platforms
  affected by the change; Mac-only work does not need an iOS build.
  For phone changes, prefer a direct install while Shelby's paired phone is reachable at home:
  `scripts/install-phone.sh --dev "Shelby's Duo"` for development, or
  `scripts/install-phone.sh "Shelby's Duo"` when Shelby says ship. Do not archive or upload to
  TestFlight on every delivery. Use the existing internal TestFlight group when Shelby requests
  TestFlight or remote distribution; an unreachable phone alone is not a reason to upload.
  Give a brief heads-up before the Mac app reopens and report Mac installation, service status
  and actual phone installation separately; distinguish installed from merely built.
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

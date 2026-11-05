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
- **One build at a time, across every worktree.** `scripts/lib/build-lock.sh` (sourced by the
  build scripts and, through `test-hygiene.sh`, by every test) makes `xcodebuild`, `swiftc` and
  `swift build` wait for the shared slot in `~/Library/Caches/Chatterbox/build-lock`, printing
  "waiting for another build (pid N, worktree X)", and caps xcodebuild at `-jobs` = half the
  cores. Three builds plus simulator suites at once took the Mac to a load average of 120.
  `CHATTERBOX_BUILD_SLOTS=2` allows two; `CHATTERBOX_BUILD_JOBS=N` sets the cap. A build run by
  hand should go through the lock too: `source scripts/lib/build-lock.sh` first.
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
  (plans/mac-pressure.md): at Busy builds go one at a time and new work threads wait to start; at
  Overloaded new builds wait ("waiting: the Mac is overloaded (…)") and work threads don't start
  their next turn. Agents run at nice +10 with build caps (`CMAKE_BUILD_PARALLEL_LEVEL`,
  `MAKEFLAGS`, `CARGO_BUILD_JOBS`) in their environment, in any project. Don't work around it;
  `CHATTERBOX_BUILD_IGNORE_PRESSURE=1` only when Shelby asks.
- **Simulators: the shared test device, shut down when the run ends.** Mobile tests call
  `test_simulator iphone|ipad|duo` (test-hygiene.sh) for this Mac's one "Chatterbox test …"
  device per kind and runtime, booted under the build slot, and shut down (not deleted) on every
  way out, a SIGKILL included (a watcher process). Booted devices are on record in
  `~/Library/Caches/Chatterbox/simulators/<udid>`; `scripts/tidy.sh --simulators` shuts down the
  ones whose run is gone and stops runtime processes of devices that aren't booted. The service
  also shuts down any booted simulator on the Mac that nothing has used for 30 minutes
  (Settings → Background service; `SimulatorSweeper`), never one on record.
- **Test scripts clean up after themselves.** Every `scripts/test-*.sh` starts with
  `source "$(dirname "$0")/lib/test-hygiene.sh"`; new ones must too. On exit it stops what the run
  started and deletes app bundles in its temp folders, keeping logs and screenshots.
  `KEEP_TEST_BUILDS=1` keeps the builds for debugging.
- **Run the tests for what you changed; the full suite once at the end.** While working, run
  only what `scripts/tests-for.sh` lists: the tests covering your changes (commits since
  origin/main, uncommitted and new files, Core's included; or name files). `--why` says why each
  is listed, `--run` runs them. It reads the test scripts themselves (what they name, compile and
  use); `scripts/test-map.txt` adds links it can't see, so add a line there when you write a test
  it misses. Before you report the work done (or before ship), run the full suite once:
  `scripts/tests-for.sh --run --all` (logs in `build/test-logs`), and say what failed.
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

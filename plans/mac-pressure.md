# Mac pressure governor

Approved by Shelby 2026-11-05, after the Mac (16 cores, 64 GB) hit load averages of 120 and then
~700 on 2026-11-04/05 (parallel work-thread builds, simulator suites, stale simulators; later a
DiscusSlicer `cmake --build` → ninja with ~18 clang jobs beside a simulator test). Chatterbox now
holds its own work back before the Mac is swamped instead of cleaning up after.

## Levels (Core/ChatterboxRuntime/MacPressure.swift)

The service (`ChatterboxDaemon/PressureMonitor.swift`) reads every 10 s, and at once on a memory
pressure event: `kern.memorystatus_vm_pressure_level`, `vm.swapusage` (and its growth),
`getloadavg` against the cores (all processes on the Mac count), `ProcessInfo.thermalState`, and
compressed memory (shown only).

| Level | When (defaults; Settings → Background service) |
|---|---|
| OK | memory normal and 1-min load < 1.5× cores |
| Busy | memory warning, or load > 1.5× cores for 2 min, or thermal serious |
| Overloaded | memory critical, or swap grew > 1 GB in 5 min, or load > 3× cores for 1 min, or thermal critical |

Up as soon as a condition holds (the load ones once sustained); down only after the lower level's
conditions have held for 3 minutes. Preferences: `pressure.busyLoad`, `pressure.busyLoadSeconds`,
`pressure.overloadedLoad`, `pressure.overloadedLoadSeconds`, `pressure.swapGrowthGB`,
`pressure.swapGrowthMinutes`, `pressure.stepDownMinutes`, `pressureHoldsWork`. Changes are logged
in chatterboxd.log with the readings.

## What's held back

- **Always:** agents run at nice +10 (ChatterboxHost starts them through `/usr/bin/nice`, same
  pid, so every shell and build they start inherits it; `CHATTERBOX_AGENT_NICE`). Their
  environment caps builds: `CMAKE_BUILD_PARALLEL_LEVEL` (cmake passes it to ninja, which reads no
  variable itself), `MAKEFLAGS=-jN`, `CARGO_BUILD_JOBS`; N = half the cores at OK, a quarter under
  pressure, fixed when the agent starts (HostClient.spawn). xcodebuild's `-jobs` comes from
  build-lock.sh (shared among the builds running). Inner threads are headless unless summoned:
  a work thread that has reported (or a returned sidequest) lets its agent process go ~2 s later
  instead of after 2 minutes.
- **Build slots** (build-lock.sh, Shelby 2026-11-05): 3 builds at OK, 1 at Busy, none new at
  Overloaded (running ones finish), 2 with no current reading; `CHATTERBOX_BUILD_SLOTS` overrides
  the count. xcodebuild's `-jobs` = max(4, cores / builds running, itself included); 4 at Busy.
- **Busy:** build-lock.sh allows one build; the simulator
  sweep runs now and every minute with a 5-minute idle time; new work threads (`work start`, the
  Desk's Start into a project) are made, with their task, but their first turn waits for OK
  ("Waiting: Mac busy"; Start now, or writing in the thread, starts it); build processes descending
  from a ChatterboxHost (clang, swift-frontend, ninja, make, cargo, rustc, node…) go to nice +15.
- **Overloaded:** all of that, plus new builds wait in build-lock.sh (running ones carry on); the
  sweep shuts down any booted simulator no running process names and no test run registered (a
  Simulator window keeps one: it may be Shelby's); a work thread's next turn that Chatterbox would
  start by itself (a sidequest's answer coming back) waits until Busy or better. Front threads and
  threads Shelby is writing in are never held, and no reply is stopped. One push on entering
  Overloaded, at most every 30 minutes.

Never: killing or stopping a build or reply, or touching a process outside a Chatterbox host's
tree. Claude Code's own wake-up after a background command finishes happens inside its process
and isn't held (holding it would mean stopping it).

Both services monitor and hold their own work threads; only the one that acts for the Mac (as
SimulatorSweeper decides: the real one, or Dev when the real one isn't running) writes
`~/Library/Caches/Chatterbox/pressure.json`, sweeps simulators, renices and pushes.

## Where it shows

- `pressure.json` (level, `updated` epoch seconds, summary, readings, what's held). build-lock.sh
  ignores it when older than a minute; `CHATTERBOX_BUILD_IGNORE_PRESSURE=1` builds anyway.
- Socket operation `pressure`, event `pressure.changed`; `work` action `startNow` (the app).
- Companion API: `GET /v1/pressure`, `pressure` on the chat list, `pressureWaiting` on a work
  thread's detail, `POST /v1/chats/<id>/work/start-now`.
- Mac: a dot in the toolbar (with "Mac busy"/"Mac overloaded" under pressure; click for the
  readings), a row in the menu bar panel, Settings → Background service; a work thread's banner
  shows "Waiting: Mac busy" with Start Now; the Work strip and the Desk show it Working with that
  status.
- Phone: the Activity header's dot and label (tap for readings and what's held), the work thread
  header's waiting line and Start now.
- `work start` says when the new thread is queued; `work list` starts with the level.

Tests: `scripts/test-pressure.sh` (levels from recorded readings, build caps, renice targets from a
fake process table), `test-build-lock.sh`, `test-simulator-sweeper.sh`, `test-work-threads.sh`
(queue, hold, release, Start now, nice and env of an agent and its child, release after report),
`test-mac-pressure.sh` (renders), `test-mobile-home-nav.sh` (`testPressureIndicator`).

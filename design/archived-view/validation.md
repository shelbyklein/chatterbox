# Archived center-pane validation

Issue68. Baseline parent8a65585/Core5d43157; isolated archived-view worktrees keep concurrent Core/MacPressure work out of this delivery.

`scripts/test-archived-view.sh` passed: 40 archived threads in date order, blank/multiword/case-insensitive title/Studio/available-preview search, actual native dock click, search reaching thread39 beyond the first screen, native card open without unarchiving/sending or draft changes, retained query after returning, toolbar title Archived, empty/no-match and wide/narrow rendering. The fixture uses isolated temporary data/preferences and no agent/provider. It exercises production ContentView and its native controls. Initial queued fixture starts were safely stopped to serialize the shared engine build and provision the required asset bundle in this fresh worktree; no behavioral failures occurred.

`scripts/test-view-memory.sh` passed its existing remembered sections, native/repeated toolbar navigation, project Sidechats, empty sections and narrow sidebar checks, plus Archive transitions to/from threads and all main overview pages.

One native visual inspection round completed. [Wide browser](archived-wide.png), [search](archived-search.png), [narrow browser](archived-narrow.png), [no matches](archived-no-match.png), [empty archive](archived-empty.png). These are original native fixture captures with synthetic conversations; sidebar/Studio context differs between captures because the test opens a Studio thread before returning. No clipping or layout correction needed. The sidebar remains available through the existing native narrow-window navigation.

Search covers the list metadata and any already-loaded preview, not a full transcript index. It loads no archived transcripts. Existing archive/restore/send semantics and all actual records remain unchanged. Full release coverage is deferred until Ship, including the previously known chat-switch baseline failure; no green full-suite claim.

Source/project, flavor and selector checks and Mac Dev delivery are recorded below when complete. No phone or real Mac install/restart authorized.

## Landed and installed

Core348dfbc and parent47825f1 retain both this feature and the concurrently completed pressure fix. Both archive and view-memory scripts passed again against that combined source. Source check passed, real and Dev flavor checks passed, selector suite10 checks passed. Selector also names broader AppModel callers; those unrelated flows were not all rerun for this focused Dev delivery.

`install-dev.sh` installed/reopened only Mac Dev. Strict signature verified; installed app/service/host binaries match built artifacts. Default idle restart completed10:15:32, service healthy10:15:34. Native computer-use inspection clicked the actual installed Archived button, saw4 archived threads in the center pane, searched an available preview down to1, and cleared back to4. [Installed native screenshot](dev-installed.png); this was the second bounded visual pass, with no polishing needed. [Delivery record](dev-delivery.json). Real app/service/host and Automations hashes unchanged4/4. No phone build, TestFlight or real shipment.

## Real shipment — November 8

Shelby authorized “ship archived view.” `scripts/ship.sh` installed/reopened parent1c0360b/Core348dfbc; installed app/service/host match built binaries and strict signature checks pass. Normal between-turn restart at10:37:44; service healthy10:37:55. Actual native Archived button opened the main center pane. Search found the requested logo thread, and Clear restored the full archive. Count changed364→365 during live verification. The app is left on Archived with search cleared; no archive/send/restore action was invoked. Original real-app screenshot remains local at `build/archived-view-real-installed.png`. Automations.json hash unchanged. No phone build or TestFlight.

Release run: **12 passed, 1 failed, 101 not run**. Same unchanged `test-chat-switch.sh` policy assertion Coordinator.swift:11, exit133; shipped under Shelby’s earlier explicit approval for that known failure and incomplete coverage. Full suite is not green. [Real delivery](real-delivery.json). Keep issue open for user acceptance/closure approval.

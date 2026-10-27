# Startup loading and sidequest Activity sources

Requested behavior: show working sessions before the full list, explain loading progress, and identify the parent of sidequests with the existing sidequest icon.

Measured before changes: the list returned 268 sessions, 7,678 transcript rows and approximately 5 MB in 1.85 seconds in one direct read. Initial subscribe returned 4,096 historical events (12 distinct chats, including 28 configuration events), marked resync-required. The app nevertheless replayed these, scheduling redundant chat/list refreshes. Prior app diagnostics recorded 16.9-second startup, and later 14-second list refreshes under concurrent work. These are observations, not a controlled before/after benchmark.

Changes:
- Initial and expired subscription history is replaced by the full snapshot instead of replayed before it. Fresh event delivery and valid reconnect replay remain supported.
- An advertised priority-list capability lets the app fetch currently running sessions before the full list. Older services safely fall back to the normal list.
- Small Studio metadata loads before selecting the first session. Sessions display before preference/pin requests finish, and full projection yields between batches.
- Sidebar and empty detail show explicit connection/loading/retry progress.
- Activity sidequests show the parent name, existing sidequest symbol, and task title, with parent context in hover help. Stored session names are unchanged; missing parents fall back to the symbol and task until the parent loads.

Validation:
- Daemon build, wire tests, Mac build/install, source check and diff checks pass.
- Wire regression checks working-only fetches omit idle sessions and preserve full-list behavior.
- Native projection regression checks expired startup history is not delivered, initial load completes, providers stay in the daemon, configuration updates arrive, and reconnect preserves transcript and draft. These pass in an isolated Chatterbox fixture.
- Installed UI inspected: loading status appears during startup; Activity subsequently displays the parent name and sidequest icon.

Delivery: Mac app installed and reopened. Service restart queued with default idle-wait behavior; priority loading remains pending that restart. Active replies were not interrupted. No iOS changes or TestFlight upload. Tidy report run; no cleanup applied.

Rollback: revert this task's scoped commits and reinstall. No conversation storage migration or content edits.

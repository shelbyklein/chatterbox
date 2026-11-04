# Chatterbox Dev: a second copy to build and try in

## Summary

Every change today ships into the one Chatterbox Shelby works in: installs quit and reopen the
Mac app, and service changes restart the service that runs every chat (helpers included). A
**Chatterbox Dev** copy runs beside it, with its own app, service, host, data, ports and phone
app, so new work is built and tried there and the real app updates only when Shelby says ship.

## Decisions (Shelby, 2026-11-04: "start setting up the chatterbox dev environments")

- One codebase, two **flavors** chosen at build time (a `Dev` build configuration): the real
  app is unchanged; Dev differs in every identity below.
- Dev data starts empty (its own sessions, Studios and Desk); nothing is shared or synced.
- Dev has no public connector (no tunnel); its push notifications come later (phase 2b).

## The flavor (one place: `Shared/Flavor.swift`, from Info.plist `ChatterboxFlavor`)

| Identity | Real | Dev |
|---|---|---|
| Mac app | Chatterbox.app, com.shelbyklein.Chatterbox | Chatterbox Dev.app, com.shelbyklein.Chatterbox.dev |
| Host / service ids | …Chatterbox.Host / chatterboxd (signing id) | …Chatterbox.dev.Host / …Chatterbox.dev.Daemon |
| Service process | chatterboxd | chatterboxd-dev |
| Data folder | Application Support/Chatterbox | Application Support/Chatterbox Dev |
| Studios, PC copies | ~/Chatterbox/{Studios,PC} | ~/Chatterbox Dev/{Studios,PC} |
| Host folder | …/Chatterbox/Host | …/Chatterbox Dev/Host |
| Service LaunchAgent | com.shelbyklein.chatterboxd | com.shelbyklein.chatterboxd.dev |
| Service preferences | chatterboxd domain | suite com.shelbyklein.chatterboxd.dev (no shared phone tokens) |
| Phone port / Bonjour | 47321 / _chatterbox._tcp | 47421 / _chatterbox-dev._tcp |
| Connector (MCP) | 47331, public tunnel | 47431, local only (URL http://127.0.0.1:47431) |
| Shelby-PC ports | tunnel 47340, PC 47390 / 47400–47899 | 48340, 48390 / 48400–48899 |
| URL scheme | chatterbox | chatterbox-dev |
| Keychain (secrets, APNs) | com.shelbyklein.Chatterbox.* | com.shelbyklein.Chatterbox.dev.* |
| Restart queue / report | …restart-service, Chatterbox/Diagnostics | ….dev, Chatterbox Dev/Diagnostics |
| App icon / menu bar | AppIcon | AppIconDev (orange DEV band), "DEV" beside the menu bar icon |
| iPhone app | Chatterbox, …Chatterbox.mobile | Chatterbox Dev, …Chatterbox.mobile.dev (no widget) |
| CLI links | ~/.local/bin/{desk,sidequest,work,…} | none (Dev chats get the bundle's bin first on PATH: BinaryLocator.devBin) |

The service trusts its own flavor's UI app (RuntimePeer) and Dev never answers on the real ports.

## Tasks

- [x] D1 Flavor: `Dev` configuration in project.yml for the Mac app, host, service and phone;
      `Flavor.swift`; every identity above read from it. Real builds byte-for-byte the same values.
- [x] D2 Scripts: `scripts/install-dev.sh` (build Dev from the current checkout into
      `build/DerivedData-Dev`, install `/Applications/Chatterbox Dev.app`, write and load its
      LaunchAgent, reopen only the Dev app); `scripts/restart-service.sh --dev`;
      `scripts/install-phone.sh --dev`; tidy.sh and safe-stop know Dev.
- [ ] D3 Check: real app and service untouched while Dev installs, restarts and runs a chat;
      the real phone still pairs with the real Mac; the Dev phone app pairs with Dev only.
      Done 2026-11-04 on the Mac: real service/app/host PIDs, ports 47321/47331, chatterboxd.plist,
      LaunchAgent, binaries and ~/.local/bin links unchanged through installs, three Dev service
      restarts and a Dev chat (answered OK); Dev on 47421 (+ `_chatterbox-dev._tcp`) and 47431
      (loopback only). Dev phone app installed on Shelby's Duo. Left: pairing the Dev phone app.
- [x] D4 AGENTS.md: new work installs to Dev; the real app only on "ship" (ship.sh), batched.
- [ ] D5 (later) Dev push notifications; optional copy of a few real sessions into Dev.

## What was decided while building it (2026-11-04)

- **How the flavor is chosen.** The `Dev` configuration (Debug plus `CHATTERBOX_DEV`) sets it for
  every target at once, so the app, its service and host always agree; the apps' Info.plists also
  carry `ChatterboxFlavor`, which install-dev.sh checks with the signing ids before installing.
  Command-line test builds are real unless they pass `-D CHATTERBOX_DEV`. `scripts/test-flavor.sh`
  pins every real value.
- **Dev's service is `chatterboxd-dev`**, so `pgrep -x chatterboxd` never finds it. Xcode can only
  embed the product under its own name, so a build phase renames it (Dev only) and reseals the
  app. A tool is signed under its file name, so Dev's is given `--identifier
  com.shelbyklein.Chatterbox.dev.Daemon`: the real service's signing id stays `chatterboxd`.
- **Phone:** the same ChatterboxMobile target in the Dev configuration: its own id, display name,
  URL scheme and Bonjour type, no app group, no push (empty entitlements), and the widget left out
  of the app (`EXCLUDED_SOURCE_FILE_NAMES`). Dev is Debug-based, so Mac Screen is slower there.
- **Dev starts empty**, phone API on; its Claude chats go through EasyCLIProxy like the real ones
  (set in Dev's own preferences), since the Claude CLI's own sign-in had expired.
- **Found on the way (fixed for both copies):** a host the service started inherited the
  service's open files (its runtime.lock, the daemon.sock listener, the app's connection), so a
  restarted service couldn't take the lock until that host exited, and the app didn't notice the
  old service had gone. The host now starts with only stdin/out/err (`POSIX_SPAWN_CLOEXEC_DEFAULT`)
  and the lock is close-on-exec. The real service picks this up at the next ship.

## Not changed

The real app's identity, data, ports, pairing, TestFlight and the connector tunnel.

## Rollback

Remove `/Applications/Chatterbox Dev.app`, unload `com.shelbyklein.chatterboxd.dev`, delete
`Application Support/Chatterbox Dev`; revert the commits (the real flavor's values are unchanged).

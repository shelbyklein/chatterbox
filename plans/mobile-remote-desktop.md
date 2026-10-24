# Mac Screen: control the Mac from the iPhone app

## Summary

A **Mac Screen** view in the iPhone app shows the Mac's screen live and lets you control it
with touch and a keyboard, like Chrome Remote Desktop, without leaving Chatterbox. It uses
macOS's own Screen Sharing, over the route the app already uses: home Wi-Fi, or Tailscale away.

## Now

- The phone reaches the Mac at its home-network or Tailscale address (`CompanionServer`
  `addresses`, `ConnectView`); there's no way to see or control the Mac's screen.
- Screen Sharing is on on this Mac (`com.apple.screensharing` enabled; port 5900 answers).
- Chrome Remote Desktop's host is installed on the Mac (a separate app, outside Chatterbox).

## Decisions (Shelby, 2026-10-24)

- Built in, on macOS Screen Sharing (VNC with Apple's sign-in), not a stream of our own.
- This Mac first; Shelby-PC later.
- Planner: client library **RoyalVNCKit** (MIT, iOS; Apple Remote Desktop auth; Tight/ZRLE;
  clipboard), pinned to an exact version: the project was archived 2026-10-05. Its iOS view
  is unfinished, so the screen view and touch controls are ours.

## Target

- ⋯ menu → **Mac Screen** opens full screen (and a toolbar button on iPad / open Duo).
- First time: the Mac's user name and password, kept in the phone's Keychain ("Forget" in
  the view's menu). Address: the Mac's, as the app already uses (Tailscale first).
- The screen fits the view; pinch to zoom, drag with two fingers to pan when zoomed.
- Touch: tap = click, double-tap = double-click, two-finger tap = right-click, touch-and-hold
  then drag = drag, two-finger swipe (unzoomed) = scroll. A trackpad mode (moves a pointer,
  tap to click) for precise targets.
- Keyboard button: the iOS keyboard, plus a key row (esc, tab, ⌘ ⌥ ⌃ ⇧ as toggles, arrows).
- Clipboard: Mac → phone and phone → Mac text.
- Quality: Auto, or Sharper / Faster (JPEG level) for a slow connection. Reconnects after
  the app returns from the background.

## Deliverables

- `RoyalVNCKit` package dependency (exact version) on the iPhone app only.
- `ChatterboxMobile/MacScreen*.swift`: connection model, framebuffer view, gestures, key row,
  credentials sheet. Entry in the ⋯ menu.
- Tests and a live check (below).

## Tasks

- [x] T1 Spike (`scripts/test-vnc-spike.sh`, 2026-10-24): signed in with Apple auth (type 30
      of 30/33/36/35 offered) on the first try and saved a 3600×2338 frame. Learned: ask for the
      password before connecting (Screen Sharing hangs up on a slow sign-in); pin RoyalVNC by
      commit (it depends on a CryptoSwift branch).
- [x] T2 Connection model on iOS: connect, sign in, frames to a CGImage, disconnect,
      reconnect on foreground. Check: simulator against the Mac's own Screen Sharing.
- [x] T3 Screen view: fit, zoom, pan; touch → pointer events; trackpad mode.
      Check: unit tests of the touch → screen-point mapping at several zoom levels.
- [x] T4 Keyboard and key row (clipboard: not yet). Check: type into a TextEdit window in the
      simulator session; screenshot.
- [x] T5 Entry point, credentials sheet (Keychain), quality setting, errors (wrong password,
      Screen Sharing off, unreachable). Check: UI test `testMacScreenAsksToSignIn` (menu entry, sign-in first, close).
- [ ] T6 Install on the Duo (`scripts/install-phone.sh`), live check at home and on Tailscale;
      TestFlight.

## Not changed

The companion API, pairing and the Mac app. No PC support yet. No audio. Screen Sharing stays
configured in macOS (System Settings → General → Sharing).

## Risks

- The library is archived: pinned; if it breaks, vendor the source.
- Over Tailscale on mobile data the picture will be slower; Faster quality helps.
- The Mac password is the Screen Sharing sign-in; it stays in the phone's Keychain only.

## Rollback

Remove the menu item and the package; nothing on the Mac changes.

## Work preparation

- Scope confirmed (approach, Mac only). Mode: linear, this session (Claude Opus 5.5): one
  feature in the iPhone app, T1 decides the library.
- Readiness: ready; the gate is the Mac password at T1, entered by Shelby.

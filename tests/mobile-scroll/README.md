# Mobile reading-position checks (#7)

Run `scripts/test-mobile-scroll.sh iphone` or `scripts/test-mobile-scroll.sh ipad`.
It serves one long synthetic chat on localhost port 47410 (no real agent or data; a busy port fails the run) and builds into `build/` in the repo.

The UI test opens the chat (newest message in view), streams revisions while at the end (follows), swipes up to read older messages, streams five more revisions and asserts the anchor message does not move, taps the jump button (back at the end, button gone), then reads up again and sends (back at the end). Screenshots are exported into the printed artifact directory.

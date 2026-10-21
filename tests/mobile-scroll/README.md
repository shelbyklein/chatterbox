# Mobile reading-position checks (#7)

Run `scripts/test-mobile-scroll.sh iphone` or `scripts/test-mobile-scroll.sh ipad`.
It serves one long synthetic chat on localhost port 47410 (no real agent or data; a busy port fails the run) and builds into `build/` in the repo.

The UI test opens the chat (newest message in view), streams revisions while at the end (follows), swipes up to read older messages, streams five more revisions and asserts the anchor message does not move, taps the jump button (back at the end, button gone), then reads up again and sends (back at the end). Screenshots are exported into the printed artifact directory.

Additional checks cover composing a multiline message, reader takeover during a held send,
leaving/returning to the app while reading, refresh/stream updates after returning, and opening
then closing a real image preview. Earlier-message anchors must be actually hittable and below
the navigation bar; prefetched accessibility rows do not qualify. The lifecycle checks compare
the same message/image's vertical position and retain screenshots before/after the event.
An intentional Jump resumes following, including after another app return.

`MOBILE_SCROLL_ONLY=<method name>` runs one check. The unmodified lifecycle handlers fail
`testReadingPositionSurvivesReactivation` because app activation unconditionally scrolls to the
end, ignoring stopped follow intent. The image fixture is an opaque locally generated PNG;
no user images or production service are involved.

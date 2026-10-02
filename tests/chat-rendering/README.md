# Chat rendering regression

Run `./scripts/test-chat-rendering.sh` in a logged-in macOS desktop session (14.4 or newer). It compiles the production views into an isolated test executable and opens its own window. It does not load saved chats or resume agent sessions.

The fixtures alternate between a long text transcript and a transcript containing two offscreen SVG web previews. On each of six switches, the test captures its own composited window with ScreenCaptureKit, checks the newest reply and sidebar using Vision, and enters a draft through the native text field. This checks actual rendering and input, rather than merely observing a responsive main actor. The final check verifies that reporting a freeze returns immediately and writes both a report and a real window capture.

Screenshots and diagnostic files remain in the printed temporary directory for inspection. The standalone executable has no embedded agent helper, so its missing-helper banner is expected.

This covers the macOS 26 regression where bottom-anchored lazy transcript layout and embedded web preview layers left Galley blank and disrupted the rest of the window. The production fix limits initial rendering to 40 rows, explicitly scrolls to the newest reply, and keeps WebKit clipping in an AppKit layer.

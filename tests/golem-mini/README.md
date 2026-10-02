# Golem mini and live progress regression

Run `./scripts/test-golem-mini.sh` in a logged-in macOS desktop session (14.4+). It compiles production views into a separate executable with isolated data, host, ports and preferences. It never loads real chats or sends messages to agents. Optionally set `CHATTERBOX_TEST_AVATAR_DIR` to copy the three avatar assets into the fixture.

The harness opens the production mini controller and sends native AppKit mouse and text events. Checks cover floating/nonactivating policy, header and avatar dragging, the actual minimize button, first-click expansion, deactivation, focused unread handling, draft preservation, restored position, disconnected-screen bounds and returning to an existing or closed main window. With two chats visible, the model shortcut opens only one popover and toggles it closed. Full-screen Spaces flags are checked; switching real Spaces is not automated.

It then renders running and completed transcripts in a regular chat and Golem's mini. ScreenCaptureKit captures the actual composited windows; Vision verifies both progress notes are visible across a mid-turn user message, thoughts stay folded, and completed narration folds away. Screenshots remain in the printed temporary folder for visual inspection. The missing-helper banner is expected in this standalone executable, which has no bundled agent host.

The engine build is cached under `/tmp/chatterbox-mini-engine.<hash>` using all source bytes and the Swift compiler version. Each run still creates fresh data and its own test executable.

# Initial mobile history regression

`Main.swift` hosts the real `ChatDetailView` with an inactive scene, as can occur during navigation/foreground transitions. It pairs to `server.py`, a local fixture server on port 19645. No real agent is contacted and the server rejects chat mutations.

Before the fix, the server receives pairing but no detail GET, and the view remains on its spinner. After the fix, it receives an unconditional detail GET and displays “History loaded without sending a message.” Polling should remain suspended while the scene is inactive.

Run in a disposable iPhone simulator, using a distinct bundle ID (`com.shelbyklein.Chatterbox.Regression`) and `SIMCTL_CHILD_CHATTERBOX_TEST_PORT=19645`. Compile the mobile and Shared sources plus the shared MarkdownText, ReaderStyle, and PathLinks views, replacing ChatterboxMobileApp.swift with this entry point. Use an app plist with local-network access permitted. Inspect a simulator screenshot and the server request log. The ordinary app's `CHATTERBOX_TEST_HOST`, `CHATTERBOX_TEST_CODE`, and `CHATTERBOX_TEST_OPEN` hooks cover the active-scene counterpart.

This deliberately exercises the lifecycle boundary. It does not claim that the user's physical device was observed in that state.

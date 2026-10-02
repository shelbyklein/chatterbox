# Refresh on mobile chat opening

Run `./scripts/test-mobile-refresh.sh iphone` or `./scripts/test-mobile-refresh.sh ipad`. Requires Xcode, XcodeGen, and the iOS 26.2 simulator runtime. Run the two targets sequentially; they use loopback port 19645. The runner creates and removes its own simulator, uses a separate bundle ID, and leaves screenshots, request logs and an xcresult bundle in the printed temporary directory. It never pairs with the live Mac or sends a message to an agent.

The native UI tests use the actual `ChatListView` and `ChatDetailView`, with 300-row Golem and project transcripts:

- Tap a chat in the list and read its history without sending.
- Leave for the Home Screen, change the server's history, and return. Assert an immediate full GET and the new reply.
- Go back to the list and select the same chat again (or retap it on iPad). Assert the new history is shown.
- Hold an initial history request for eight seconds, type a draft, switch to another chat, then return. Assert fresh history loads promptly and the draft survives.
- Reject all chat mutation POSTs and check that none occurred.

The pre-fix build (`ba48995`) passed a simple initial load but failed the foreground and reopen checks: returning to the app waited for a later conditional poll, and reopening the retained detail sent no new request. The earlier `mobile-initial-load` fixture remains the separate inactive-scene boundary check. This test adds the real navigation path that it did not cover.

The slow-load case also exposed a missing detail lifecycle callback when changing chats. History loading now belongs to the stable navigation parent: each row action forces a request, foregrounding forces another, and polling shares the same cancellable owner. A mutation response invalidates any older GET. The loaded transcript stays visible during refresh.

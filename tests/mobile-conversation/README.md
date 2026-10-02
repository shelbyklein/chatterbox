# Mobile conversation checks

Run `scripts/test-mobile-conversation.sh iphone` or `scripts/test-mobile-conversation.sh ipad`.
The script creates a separate simulator and bundle ID and serves synthetic chats on localhost port 19646. It never connects to the installed Mac app, sends a chat message, or reads real conversations. A busy port fails the run.

The UI test opens Golem through the chat list and checks paragraph bubble count, settings access, expandable steps, dictation/Send/Copy availability and Send enablement after typing. It then checks that a list, code fence containing a blank line, and table render as three intact bubbles, and opens a Claude project for the orange styling capture. Dark and light captures are exported from the xcresult into the printed artifact directory. A fresh fixture is required for each run.

Keep the separate `scripts/test-mobile-refresh.sh` regression for opening/reopening history, foreground refresh, interrupted loads and draft preservation.

# Chat switch timing

Run `./scripts/test-chat-switch-perf.sh` in a logged-in macOS desktop session. It copies your saved chats into a temporary folder (with background-host links removed, so no agent is resumed), compiles the production views into a test executable, and opens its own window.

It prints, for the six longest chats:

- **parse cost** of the newest 40 rows' markdown and path links, without any view;
- **switch**: selecting the chat plus the forced layout and draw before it can appear;
- **then blocked**: main-thread stalls over 16 ms in the second after the switch.

The last line, `RESULT median switch … ms`, is the number to compare before and after a change. Pass another folder of conversation JSON as the first argument to use other fixtures.

Options, as environment variables:

- `PERF_ROUNDS=8` switches through the chats more times (default 4; the first round is reported separately).
- `PERF_SAMPLE=/tmp/switch.txt` records a `sample` call graph of the switching rounds.
- `PERF_CURSOR=count` counts `NSCursor.set` calls; `PERF_CURSOR=dedupe` also skips setting the cursor already showing. A customized pointer (Accessibility → Display → Pointer) makes each set re-render the cursor.

In the app, Instruments' Points of Interest track shows "Chat picked" and "Chat shown" for each switch.

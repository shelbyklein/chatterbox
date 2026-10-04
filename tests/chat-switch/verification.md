# Mac chat switch verification — 2026-10-04
Coordinator regressions pass for initial entry, outgoing-hidden replacement, latest-wins cancellation, same-ID recovery, alternate-detail reset, delayed native mounting, and zero translation under Reduce Motion. Delaying mounting by650ms keeps the chat hidden until its mount acknowledgment arrives.

Native harness uses the actual signed Debug app library via @testable import. Isolated copied Golem/project histories; automatic agent work and companion notifications disabled. Production ContentView selectedID changes exercise keyed mounting and task cancellation. Native window-server captures inspected for outgoing, hidden swap and incoming; the hidden-swap frame has a blank chat pane with unchanged sidebar. Rapid Golem→project→Golem picks finish on Golem. Draft strings and transcript counts are unchanged. Pane bounds remain inside an800pt window.

Run: scripts/test-chat-switch.sh /Users/shelbyklein/Chatterbox/Screenshots/mac-chat-switch
Log: /tmp/chatterbox-fade-native.log
Proof: /Users/shelbyklein/Chatterbox/Screenshots/mac-chat-switch/sequence.png

No live send or external model request was made. Actual sidebar mouse clicks, Return during a transition, VoiceOver traversal, and toggling the OS Reduce Motion preference were not exercised; input gating and Reduce Motion are covered by code/coordinator checks. Native selection uses the same selectedID path as sidebar picks. The animation masks initial layout; it does not eliminate synchronous work or guarantee a fixed duration under heavy load.

Follow-up measurements: removing the deliberate waits and isolating opacity updates gave capture-free native selection-to-interactive times798/1118/732/1071ms on copied Golem/project histories. These still include actual rendering; they do not establish that the underlying lag is gone. Coordinator mount-to-reveal/unlock is19ms. The long artificial pause/input lock is removed. Deferred focus/height callbacks now ignore dismantled composers. Draft checks passed after rapid switching; one earlier run failed the draft assertion before this focus-callback guard, without capturing the changed value, so the exact cause is not established.

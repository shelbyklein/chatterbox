# Unified columns verification

Command: scripts/test-unified-columns.sh /tmp/chatterbox-columns-proof
Result: exit0, 2532 allocation cases, native window frames640–1600pt.
Real AppKit divider drag, sidebar toggle/width restoration, chat switching and actual overlay-close mouse clicks passed. Golem image-heavy copied history and native Issues/local WebKit widgets rendered. Native hierarchy has no NSSplitView.
Screenshots inspected: /Users/shelbyklein/Chatterbox/Screenshots/mac-unified-columns/golem-1100.png, golem-800.png, preview-1100.png. Full set in that folder.
The first native test caught container centering; .frame alignment topLeading fixed it. A subsequent drag check used immutable argument defaults; writable standalone-test preferences fixed that fixture. The final run passes without those overrides.
No paid inference, real transcript mutations, external browser sessions or remote deployment.
Unverified: real toolbar sidebar click (request path tested), VoiceOver, secondary physical screens, right-divider drag.

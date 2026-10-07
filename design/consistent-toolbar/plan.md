# Consistent top bar

Opening overview pages removes Terminal and changes the title width, moving controls that should be familiar across views. Keep the existing single AppKit toolbar and a stable title/navigation area and right-hand actions; only contextual session details change. This follows Shelby's established title, navigation, context, actions layout and current report that each view feels different.

Evidence: [current bar](before.png), WindowToolbar.apply hides Terminal when its chat bridge detaches; titleLabel has only a maximum width. Target: `[fixed-width title][Projects Studios Multi Automations Chats] -- [applicable session details] -- [Usage Terminal Bell][Settings][+]`, with Terminal visible but disabled on overview pages. Studios overview title should read Studios.

local: design/consistent-toolbar/plan.md. Linear current Codex session, runtime exact model/effort not exposed; preserve existing workflow authority for scoped fixes, no model switch or delegation. No open product questions. No data/schema/daemon/auth changes. Preserve all pending work; no GitHub writes or commits. Deliver source, native navigation/runtime evidence and local Mac installation. Prior installed bundle backed up before replacement for rollback.

- [x] T1 Keep title width and global action visibility stable; check fixed title size and terminal enabled state across overview/chat transitions.
- [x] T2 Exercise toolbar navigation and capture actual native toolbar in fixture, inspect renders and stable title width at one window size.
- [x] T3 Build/install locally and verify installed bytes, unchanged daemon PID.
- [x] T4 Navigation badges for Projects, Studios and Chats count active sessions with pending questions/approvals or unseen completed turns. Deduplicate within a session; exclude archived and Golem sessions, clear seen completion while retaining pending requests. Check isolated fixtures and native badge render.

Evidence: /tmp/consistent-toolbar-test.log RESULT all passed. Native toolbar retained across chat switches and all page transitions, same global controls, constant title width (200-point label plus AppKit's four-point padding), appropriate Terminal enablement. Badge fixtures verified classification, dedupe, unread clearing, pending retention and archived exclusion. Inspected [native badge render](view-badges.png) and [Studios render](studios.png); these are isolated app renders, not installed-app screenshots. macOS renders group badges monochromatically. Mac build and scripts/install.sh succeeded, installed executable equals built executable; running app PID 93867, daemon remained PID 77155. No commit, push or service restart. Previous bundle for rollback: /tmp/Chatterbox-before-consistent-toolbar.app. Test preferences now use an isolated suite.

Follow-up authorized: remove redundant Command Center/Back to Chat buttons from Studios header, keep New Studio and per-Studio New Chat tiles; center base navigation icons in equal-sized badge canvases. Prior images used x=0 in 32-point canvas for a 17-point icon, leaving asymmetric blank space on the right.
- [x] T5 Inspect new native Studios/header and badge renders, run toolbar regression and verify local install.

T5 results: /tmp/toolbar-spacing-test.log RESULT all passed; inspected updated Studios and badge captures. Header retains slider/New Studio, removes Command Center/Back to Chat; navigation glyphs centered in identical canvases and counters overlap corners. /tmp/toolbar-spacing-install.log installation succeeded; installed Mac binary matches built binary; daemon unchanged at PID 77155. Still local/uncommitted/unpushed.

Acceptance: same navigation/action buttons on every page, fixed navigation/action positions at a constant window size, correct title and contextual controls, single toolbar/items retained. Test scripts/test-chat-toolbar.sh plus native fixed-layout checks; inspect screenshots across chat, Studios, Settings, Automations. No service restart. Readiness R1-R13 covered by established implementation scope and local evidence; execution within continuing toolbar fix authority.

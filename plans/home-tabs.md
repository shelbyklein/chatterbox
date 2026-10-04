# Home pages: Projects, Studios, Chats and Archive

Home currently renders every group on one scrolling page (ChatHomeView.swift). Shelby requests three top-level thread tabs and a bonus archive. Replace the combined overview with persistent pages, keeping search, attention filters and existing cards/actions; Command Center grouping remains unchanged.

local:home-tabs · linear GPT-6.1-Sol Medium. No delegation. Scope Mac Home only; no mobile navigation, provider, session, secret or transcript changes. No GitHub issue mutations. Current proof: /Users/shelbyklein/Chatterbox/Screenshots/mac-home/home-wide.png. Target: [home-tabs.svg](home-tabs.svg). R1–R13 pass: runtime tab choice is settled; existing install/restart authorization applies.

Success: active pages cover each active session exactly once, archive only archived sessions; all four native tabs select separate pages and remember selection; cards/search/filters remain usable at 640 and 1200pt; archive opens history without restoring implicitly and offers existing Unarchive action. Verify in fixture with production views, native clicks and inspected renders.

- [x] HOME-TABS-1: Add page partitioning, persistent fixed top navigation, archive display and empty states. Acceptance: data assertions cover family membership and unique complete partitions.
- [x] HOME-TABS-2: Extend scripts/test-mac-home.sh with native tab navigation/persistence and archive/open/restore data checks; inspect wide/narrow renders. Command Center regression unchanged grouping.
- [x] HOME-TABS-3: Build, scoped commit/push/install Mac, verify signature/binary/process.

Deliver code, tests, proof screenshots and this plan committed/pushed; verified Mac install. Rollback: backup installed bundle before install, restore it without altering conversations. Page selection is a single UserDefaults key and can be reset.

Verification: Chatterbox Debug build passed in build/GolemPlan. scripts/test-mac-home.sh passed /tmp/chatterbox-mac-home.nY4VoM: native clicks on all four tabs, persistent remount, exact complete active partitions and archive-only membership, family membership, search/filter checks, history/draft preservation on archived open and restored membership. Wide dark and narrow light production renders inspected; proof copies /Users/shelbyklein/Chatterbox/Screenshots/home-tabs/. Native production views used an isolated legacy-runtime fixture; no live conversations or provider requests. scripts/test-command-center.sh passed /tmp/chatterbox-command-center.uLlAAC: native composer focus/drafts, switching, removing and histories preserved. No mobile changes.

Mac installed source f540bab via scripts/install.sh. Signed bundle verified; installed/built dylib match ee23343c191c688eafa302d77b36a046b79e7d40e9c50217a783ab88b297876c. /Applications executable running PID 72682; authenticated local API returned 200. Backup /tmp/Chatterbox-before-home-tabs.app. No live user thread modified or restored. Installed Home interactions were not driven; native UI checks above used isolated fixtures.

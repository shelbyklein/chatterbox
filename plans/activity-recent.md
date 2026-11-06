# Recent threads below iOS Activity

Opening a new reply removes it from unread Activity, so returning to that thread requires finding its project or chat page again. Add Recent beneath the dedicated Activity cards/list, using the existing phone-local opened-thread history. Shelby requested this during Mac workflow work and authorized implementation directly.

Current visual reference: [Activity cards](../design/activity-thread-layouts/duo-activity-full-cards.png), [list](../design/activity-thread-layouts/duo-activity-full-list.png). Reuse their existing components.

Target sketch:
```
Activity                         layout menu
active / new                     pressure
[existing Activity cards or rows]
Recent
[recently opened thread cards or rows, latest opened first]
```

Success: a thread opened on this phone remains reachable under Recent after reading its reply; recent ordering and persistence survive relaunch; current Activity threads do not repeat; search and both layouts work. Recent is bounded to ten front threads from the saved last-30-days phone history, excludes archived/unavailable sessions and work threads, and uses ordinary thread views without new/unread labels. No new source review, Mac app build, real install or TestFlight.

- [x] R1 Add recent selection and render below dedicated Activity in both layouts. Acceptance: idle/read chats open correctly, latest-opened order, no repeated IDs and no misleading Working labels.
- [x] R2 Add focused UI regression and inspect fresh phone captures. Acceptance: open/back, recent ordering/persistence, layout switch and query behavior pass; existing Activity layout/dismissal and engine regressions remain intact.
- [x] R3 Commit/push Core then parent, install the affected Dev phone app directly if reachable. Acceptance: delivery evidence separates built, installed and launched; no Mac restart. Real shipment awaits new Ship.

Verification: scripts/tests-for.sh --why; scripts/test-mobile-activity.sh; focused scripts/test-mobile-home-nav.sh iphone and duo tests for recent/layout/tab behavior. Use fixed build/simulator locks and existing fixtures. No full suite for routine Dev work. Rollback: revert scoped commits and reinstall compatible Dev; saved read-history remains unchanged in format and no migration occurs.

Work preparation: linear due to one mobile component and shared UI regression file. Model: current session; exact model/effort unavailable. Readiness: pass R1-R13. Open questions: none. Tracking: https://github.com/shelbyklein/chatterbox/issues/58.

## Verified result and delivery

Final iPhone 17 Pro / iOS 26.2 Recent scenario passes (69.4s): opening and returning to a read reply, ordering after visiting another thread, no repeated active thread, real Cards/List switch verified by full-width row geometry, persistence after relaunch, search and zero archive/delete mutations. Existing Activity tab/back/pin regression (23.3s) and full thread layouts/navigation/dismissal regression (33.8s) pass against the same product source. Activity engine checks pass. Source/project and diff checks pass. Baseline: parent 98f6979 / Core ca6880a.

Duo / iOS 27.1 Recent interaction scenario passed (72.3s). Fresh Cards and manually verified List captures were inspected. Fresh final iPhone Cards/List captures were also inspected: [iPhone cards](../design/activity-recent/iphone-cards.png), [iPhone list](../design/activity-recent/iphone-list.png), [Duo cards](../design/activity-recent/duo-cards.png), [Duo list](../design/activity-recent/duo-list.jpg). Layout, readable copy and section placement match the existing components.

Intermediate attempts are not called green: the first iPhone runner crashed inside UIKit startup before any test; the new test then needed missing fixture UUIDs added, a launch-time cards override removed, and an unexposed List container ID replaced by a rendered-width check. Product code needed no changes after initial implementation. Detailed attempt logs are build/activity-recent-*.log. Only this task's failed/stalled xcodebuild processes were safely stopped after exact products-path checks. Manual fixture launch was stopped through MobileBuildMCP. Normal pressure/build/simulator gates were honored throughout; their recovery waits account for most elapsed time.

Dev delivery completed with scripts/install-phone.sh --dev "Shelby's Duo". Dev installed; automatic open did not succeed, so physical-phone runtime launch remains unverified. [Delivery record](../design/activity-recent/dev-delivery.json) records source/binary hashes and identity. No Mac install or service restart, no real phone install, no TestFlight, and no source review or automation changes. The full native suite was not rerun for routine Dev work under the focused verification policy; earlier unrelated release blockers remain unchanged. Tidy: full tooling report 191 removable/9 kept; final simulator report 0 removable/8 kept, both owned test devices shut down, unrelated active device kept. No cleanup apply.

Core delivery commit: 9ec87f9b17fd6e9a3752d3bcc86f7988ea43b99a. Parent contains the gitlink, regression, proof captures and plan. Issue stays open pending user review; new Ship authorizes real delivery.

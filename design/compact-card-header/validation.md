# Compact iOS card headers

Issue [69](https://github.com/shelbyklein/chatterbox/issues/69). Baseline parent47f4551/Core348dfbc. Product change is limited to the shared text `ChatCard` in Core/ChatterboxMobile/ChatListView.swift: title at the upper left, provider/branch icon at the upper right, status beside it, preview below. Existing fonts, padding, radius, thumbnail cards and list rows remain unchanged.

## Focused verification

Selector: `scripts/tests-for.sh --why --since 47f4551` selected the existing mobile-home-nav suite and source-membership check; source check passed. Three affected native iPhone 17 Pro/iOS26.2 flows were selected: `testProjectsNestWorkThreads`, `testActivityThreadLayouts`, `testActivityRecentThreads`. Broader unaffected mobile suites were not run for this focused Dev delivery. No full-suite green claim.

First run `build/mobile-home-nav.R1wYj2`: Activity/Recent flows passed; Projects nesting/cards navigation passed until the list-spacing assertion at HomeNavTests.swift:1568 measured0pt between full button hit rectangles. The same Projects test against the unchanged Core348dfbc file reproduced the same0pt failure (`build/mobile-home-nav.gHLFyd`, `build/compact-card-header-baseline.log`). The proposed file was restored automatically afterward.

The existing invalid spacing assertion now verifies that the next family’s tap target does not overlap Show more. iOS List includes row insets in button hit areas, so adjoining hit rectangles do not measure visible card spacing; the combined accessibility label also prevents querying each text separately. Existing nested/thread open/Show-more and card/list navigation checks are retained. Native captures verify the rounded backgrounds and their10pt gap. This is a harness correction, with no list product change. An intermediate text-element assertion was rejected by the native run because the row exposes a combined label; it is not retained.

Final native run, captures, commits and Dev phone installation are recorded below when complete. Real shipment remains pending.

## Final native checks

Coree0c601a. Activity Recent69.750s and Activity layouts33.421s passed in `build/mobile-home-nav.2FayYi`. Projects nesting31.484s passed in `build/mobile-home-nav.86R85d` after the harness correction; all three affected flows have passing coverage on the final product source. The Projects run retained native thread opening and list Show-more/less checks. No app layout adjustment followed the first visual pass.

Second/final visual pass inspected original native [Projects cards](phone-projects-nested.png), [expanded list](phone-projects-list-cards-expanded.png), [Activity cards](activity-full-cards.png) and [Recent cards](activity-recent-cards.png). Titles/preview start at the upper left with no overlapping text or trailing icons; provider/branch icons and waiting/working/new-reply state remain visible. Expanded list cards retain their rounded edges and visible separation. Other captures are preserved alongside these. Synthetic fixture screenshots establish native simulator layout, not physical-phone acceptance.

Source membership and both whitespace checks passed. Direct Dev delivery pending; no Mac install/restart, real-phone delivery or TestFlight.

## Dev phone delivery

Parent2b90be4/Coree0c601a committed and pushed to both main branches. `scripts/install-phone.sh --dev "Shelby's Duo"` built the Dev configuration, verified embedded frameworks, installed and successfully opened Chatterbox Dev on the paired physical Duo. Bundle `com.shelbyklein.Chatterbox.mobile.dev`; no widget, Mac install/service restart, real app install or TestFlight. Physical-user acceptance remains pending. [Delivery record](dev-delivery.json). Read-only tidy report run; unrelated old scratch left untouched.

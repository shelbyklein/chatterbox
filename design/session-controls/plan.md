# Chat sidebar and session controls

Show New replies explicitly in the Chats sidebar for quick access. Move session-specific controls from the main window toolbar to a compact icon and dropdown in the chat, beside Notes and Quick prompts on the right.

Current evidence: ContentView.sidebarColumn already contains UnseenRepliesStrip, but the strip disappears when empty. ChatView.chatContent places Notes and Quick prompts in a top-leading overlay; WindowToolbar carries ToneSlot, PlaceSlot (including images), and RepoSlot. [Current screenshot](current.png). [Target sketch](target.svg).

Scope: macOS regular chat windows, including project and Studio sessions. Reuse tone, folder/Studio, image and repository/issue controls; keep their existing actions and data. Leave Golem, compact chats, multi-session tiles, iOS, authentication, and agent runtime unchanged. Preserve Notes, Quick prompts and message pins, with pins below the controls. Terminal placement is an optional preference; default to keeping its top-bar shortcut unless requested otherwise.

Success: Chats sidebar visibly offers New replies, including an empty state; unread rows open the correct chat and clear from attention. Session tools, Notes and Quick prompts appear at the top right without overlapping pins. Main toolbar no longer duplicates the moved session controls. Existing actions still target the selected session.

Deliverables: committed and pushed source, local plan and inspected fixture screenshot; Mac build verified. Installation requires user approval under AGENTS.md and remains pending until requested. No service restart needed.

## Tasks
- [x] T1 Make the Chats New replies section discoverable even when caught up; verify unread and empty fixtures.
- [x] T2 Group session controls, Notes and Quick prompts on the right; verify rendering and session binding.
- [x] T3 Verify Mac build and toolbar suite, inspect screenshot, commit/push scoped work and run tidy report.

Validation: scripts/test-chat-toolbar.sh; xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData build -quiet. Extend toolbar fixture to render right-side session controls and New replies. Real entry: Chats view, select a session, top-right Tools icon. Render controls alongside pins and inspect screenshot. No persistent schema change; rollback is reverting scoped commits. Installed app is preserved until approved installation.

## Work preparation
Tracking: local: design/session-controls/plan.md (no GitHub issue mutations).
Scope authorized by user's direct edit request; execute now. Linear, because these controls share ChatView/toolbar state. Executor: current session; exact model/effort unavailable. No delegation. No blocking questions.
Readiness: pass 2026-10-08, R1–R13 covered above; R7 local task checklist. Install gate remains pending.

## Verification evidence
Mac Debug build and scripts/check-sources.sh passed. Inspected [chat controls](chat-controls.png), [tools panel](tools-panel.png), [unread Chats sidebar](new-replies.png), and [caught-up sidebar](caught-up.png). The unread fixture opened the correct chat and cleared its attention entry. Existing toolbar controls retain their identity across chat switches. Native popover and Image Library interaction remain an installed-app acceptance check: the isolated harness cannot reliably drive these SwiftUI controls through AX or synthetic events. The final toolbar suite passed all checks, including Settings/Terminal, after restoring the main test window focus. Synthetic-click assertions were removed because the harness could not exercise those SwiftUI controls reliably; installed dropdown interaction remains pending.

Tidy report: 126 older test folders (837 MB), no leftover test processes or stray app copies in this repo; 12 Golem build apps left to their owner. Report only, no deletions.

## Installed acceptance
2026-10-08: user approved installation; scripts/install.sh completed and the installed executable matched the verified build. The app reconnected; chatterboxd retained PID 24522. Through native computer use, Session tools opened its popover with Friendly, USA Archery and Image Library; Image Library opened the current session’s six images. Closed the sheet and returned to the same chat. Inspected the installed screenshot showing tools, Notes and Quick prompts on the right. No service restart or interruption of replies.

## Compact Working list — 2026-10-08 follow-up
User requests currently turning sessions at the bottom of the left sidebar, minimal. Confirmed scope: all regular sidebar pages, above Archived, provider-colored spinner and one-line title; collapsible heading and a bounded scrolling list, hidden when empty. New replies stays at the top. No new persisted chat data, runtime changes or iOS work. Use Attention.workingChats and openWorkingChat.

- [x] T4 Build and inspect the compact Working strip; existing activity test verifies running/finished filtering and navigation. Run scripts/test-finished-chat-bell.sh and the Mac Debug build, then commit/push. Installed check waits for user approval under AGENTS.md.

Target: the existing target sketch plus a bottom Working heading and one-line rows directly above Archived. Linear; current session, exact model/effort unavailable. R1–R13 pass for this scoped addition; no blocking questions. Rollback by reverting these UI commits.

- [x] T5 Make the whole padded Tools, Notes and Quick prompts label clickable, not just its glyph. Verify padding clicks in the installed app after approved installation. No behavior or data change beyond hit areas.

Follow-up verification: Mac Debug build and source check passed. scripts/test-finished-chat-bell.sh passed running/completed filtering, persistence and native activity navigation. Inspected [compact Working list](working-sidebar.png). Tools, Notes and Quick prompts labels now have contentShape(Rectangle()) after their padding, so padded label areas participate in hit testing. Installed bottom placement and padding-click acceptance remain pending user-approved installation. Tidy report unchanged (126 older temp folders); nothing deleted.

Follow-up installed acceptance: user approved installation; scripts/install.sh completed, installed executable matches the build and chatterboxd PID stayed unchanged. Inspected installed sidebar with Working above Archived (three sessions, then four as another turn began). Clicked empty padding near the lower-left of the Notes button, and the notes text box expanded. Further UI actions were stopped when native computer use detected concurrent user navigation. No replies interrupted.

## Combined Activity footer — 2026-10-08
User confirms combining New replies and Working and keeping the combined section at the bottom. Replace the sidebar's two sections with one compact, collapsible Activity section above Archived. Show unseen finished replies first (blue dot), then running sessions (provider-colored spinner), each as a one-line clickable session name. Header shows separate new/working counts, with a bounded scroll area for all rows. Chats shows All caught up when empty. Studios thumbnail page remains unchanged. Preserve attention, navigation and unread-clearing semantics; no runtime, iOS or transcript data changes.

- [x] T6 Implement and build combined footer; render a fixture with both new and working sessions, run scripts/test-finished-chat-bell.sh and source check, inspect render, commit/push. Installation requires separate user approval under AGENTS.md.

Target sketch updated to bottom Activity with New replies and Working rows. Linear; current session, exact model/effort unavailable; user direct request authorizes implementation now. R1–R13 pass for this local scoped follow-up, no blocking questions. Rollback by reverting these UI commits.

Combined footer verified: Mac build and source check passed; finished-chat-bell test passed navigation, persistence and clearing. Inspected [combined Activity](combined-sidebar.png), containing two unread sessions and one working session. Not installed.

## Global Pins in the toolbar — 2026-10-08
User requests global pins in the middle top bar, managed in their own Settings tab. Keep scoped project/Studio pins under their owners and add them directly via owner right-click menus; remove the global sidebar grid. Preserve saved pins, opening actions and keyboard shortcuts. Global toolbar icons open pins, overflow remains reachable, and Settings offers add, rename, remove, reorder, icon size and website opening preference. Add Pin uses its requested scope without an Everywhere/project selector. No migration, service restart or runtime change.

- [x] T7 Move global pins to a persistent central toolbar slot and add Settings > Pins. Build, inspect toolbar/settings renders, verify scoped pin creation and existing pins, commit/push. Install awaits approval.

Linear execution, current session; no delegation. User scope is implementation-ready, R1-R13 covered by this scope, existing target and checks. Rollback by reverting the scoped UI commits; stored pin data unchanged.

Pins evidence: Mac build and source check passed. scripts/test-sidebar-pins.sh passed global/project separation, reorder and rename checks; inspected [global icons](global-pins.png), [Pins settings](pins-settings.png), and [project-scoped Add Pin](project-add-pin.png). Inspected [full toolbar](global-pins-toolbar.png): global icons sit in the center, session controls remain at the chat's right, and global sidebar grid is gone. Existing project pills and context menus remain. Mechanical layout scan returned no findings. Tidy report remains 126 old test folders, 837 MB; no deletion.

The first full toolbar suite passed the new centered-slot and stable-item checks but failed one Studios transition assertion before its render showed the correct Studios title and disabled Terminal. The harness now restores window focus and waits up to three seconds for the page/toolbar state, instead of a fixed 800 ms. Repeat check pending. Installed mouse interaction is still an acceptance check after approved installation.

Repeated transition tests revealed native action validation was re-enabling Terminal on overview pages, despite apply() setting it disabled. Terminal now sets autovalidates=false so its availability follows the selected page/session, while other native buttons retain normal validation. This tiny adjacent fix is needed for consistent toolbar behavior; Mac rebuild passed. Final full suite pending.

Final verification: all full toolbar checks passed, including the centered Pins slot, stable items on every page, disabled Terminal on overview pages, and attention navigation/clearing. Inspected the final toolbar render again. All scoped work is ready to commit/push; installation remains pending under AGENTS.md.

Installed acceptance — 2026-10-08: user approved installation. scripts/install.sh completed; installed executable SHA-256 matches the verified build. chatterboxd retained PID 24522. App reconnected and restored Building Chatterbox. Native inspection confirmed five saved global pins centered in the toolbar, the bottom Activity footer with two working sessions above Archived, Settings > Pins with all five saved pins, and Add Global Pin opening the Global-scoped sheet. Dismissed without changing pins and returned to the active chat. No service restart or interrupted replies.

## Always-expanded Projects — 2026-10-08
User requests removing the ability to minimize Projects. Replace its clickable chevron heading with a plain heading and always render its list, ignoring any old collapsed preference. Keep Filter, New Project, cards/list choice, pinned threads, Studio/Chats collapse and Activity unchanged. Scoped UI follow-up, linear execution; direct request authorizes implementation.

- [x] T8 Build and render Projects with a previously collapsed preference; inspect that cards remain visible and the heading has no collapse affordance. Run studio-sidebar fixture and source check; commit/push. Installation awaits approval under AGENTS.md.

Always-open verification: Mac Debug build and source check passed. Studio sidebar routing fixture passed and rendered Projects with sidebarProjectsCollapsed=true. Inspected [Projects expanded](projects-expanded.png): the project card is visible beneath a plain Projects heading without a chevron; filter and + remain. Tidy report remains 126 old folders, no removals. Not installed.

## Latest image on session cards — 2026-10-08
User requests the item thumbnail in Studio sidebar card view, including pinned cards. Use the existing latest-image cache on all regular ThreadCards, keep provider/status/title/preview and selected/waiting appearances, show an aspect-preserving small thumbnail below the preview only when an image exists. Refresh cache for cards as well as icon tiles. No new data or runtime change. Linear scoped implementation authorized directly; no blocking questions.

- [x] T9 Build; render selected/unselected/waiting image cards in light/dark using the card-attention fixture; verify thumbnails load, inspect and commit/push. Install with the pending always-expanded Projects change after approval.

Thumbnail verification: Mac build and source check passed; card-attention fixture passed thumbnail loading through card tasks, pending/answered state and existing file-link checks. Inspected [compact image cards](card-thumbnails.png) and [light image cards](card-thumbnails-light.png). Thumbnail preserves image proportions below preview; waiting/selected appearances remain. Fixture uses a local Notes icon as a sample image. Initial fixture referenced a bare path that the shared image-reference scanner does not consume; corrected fixture to a Markdown image link. No scanner behavior change. Tidy remains report-only, 126 old folders; no removals. Pending user-approved install, together with always-expanded Projects.

## Compact pinned Studio sessions — 2026-10-08
User shows Studios overview tiles as the target for pinned Studio sessions. Render the pinned group in the Studio sidebar as adaptive compact icon/thumbnail tiles with names underneath, provider badge, activity state and selected/waiting appearance. Use the same ThreadCard iconOnly mode as the overview, in both sidebar list/card modes. Other session cards stay unchanged, and Projects/Chats pinned presentations remain unchanged. Preserve open, unpin/context menus and drag semantics via row(). Linear scoped execution authorized by the direct request.

- [x] T10 Build; inspect Studio sidebar list/card renders with pinned image sessions and verify cache loads and existing navigation checks. Commit/push. Install together with pending Projects and card-thumbnail changes after approval.

Pinned Studio verification: Mac build and source check passed; studio-sidebar fixture passed routing/shortcut/new-session checks and thumbnail loading. Inspected [pinned tiles in list mode](studio-pins-list.png) and [pinned tiles above cards](studio-pins-cards.png). Both use the same compact overview tile with name below; non-pinned rows/cards remain unchanged. Standalone harness has no provider asset catalog, so empty provider fallback/badge in these fixture renders is a known harness limitation; native icon resources and existing overview tile implementation are unchanged. Tidy report remains report-only. Not installed.

Installed acceptance for T8–T10: user approved restarting; scripts/install.sh completed and installed executable matched the build. Background service PID remained unchanged.

## Matching session control heights — 2026-10-08
User requests equal heights for tools, notes, quick prompts and collapsed message pins. Give all four collapsed labels an explicit 32-point height with existing horizontal padding and full rectangular hit areas. Expanded notes/pins retain natural panel height. Scoped linear UI follow-up; implementation authorized directly. Build and inspect a control render, commit/push; installation awaits approval.

Verified: Mac build and source check passed; chat-pins fixture passed persistence/toggle checks and rendered open/folded panels. Inspected [collapsed pin control](pins-matched-height.png). All four collapsed labels use 32 points, while expanded panel headings remain unconstrained. Previous installed batch reconnected and restored the Studio session in native inspection. Installation of this height adjustment remains pending.

## Mobile Studio card thumbnails — 2026-10-08
The supplied iPhone photo shows Studio cards with no artwork. Add the latest image below the preview, preserving proportions, provider/status, title and activity; no-image cards stay plain. Same placement as the accepted Mac card thumbnails above supplies the target. Linear execution, current session; exact model/effort unavailable. User request authorizes implementation. No image edits, migrations, publishing or GitHub issue changes. Optional wire field keeps older clients/servers compatible; revert commits to roll back.

Success: authenticated preview endpoint serves JPEG at most 320 pixels; unpaired and cross-chat requests are refused. Simulator Studio cards show fetched preview and unchanged no-image card. Deliver committed/pushed code, tests, evidence and device build; install/restart requires approval under AGENTS.md.

- [x] T11 Share bounded cached lookup and authenticated off-main encoding; verify API dimensions/access with scripts/test-companion-pdf.sh.
- [x] T12 Add mobile cached previews; build iOS/Mac, render Studios with scripts/test-mobile-home-nav.sh; inspect, commit/push. Install/activation pending.

Readiness R1–R13 pass for scoped follow-up using user screenshot and accepted Mac card evidence; no blocking questions. Existing native styling retained. Local plan only, no issue mutations.

API acceptance: companion-pdf fixture passed existing byte-identical file/PDF checks plus thumbnail authentication, cross-chat rejection and exact 640x480 → 320x240 downsampling. Mac and signed iPhone builds pass. Cached scan now includes final/streaming phase so a finished reply refreshes previews. Initial Studio UI test passed and was visually inspected; it left Studios selected and broke the following navigation calibration. The fixture now restores Projects; full rerun pending.

Final verification: all three mobile-home-nav tests pass after restoring Projects at the end of the Studio test. Inspected [Studio cards in the iPhone simulator](mobile-card-thumbnails.png): bounded aspect-preserving rounded preview below reply, plain no-image neighbor. A simulator Apple Intelligence banner obscures the header but not the cards. Test artwork is a synthetic gradient; real phone artwork acceptance awaits installation. Signed iOS/Mac builds and source check pass. Tidy reported leftovers only and kept the active fixture; no removals or service restart.

## Copy image and Studio-only thumbnails — 2026-10-08
User requests visible Copy image on image replies and restricts thumbnails to Studio cards (including when a Studio session is globally pinned on Projects, where it must stay text-only). Put a Copy image button beside each referenced image caption; copies that image, shows Copied feedback, preserves image-open/review and message Copy/Pin. Generated image overlays share the same label. Gate regular card thumbnails by the view's Studio context on Mac/iOS; no-image cards stay plain. Linear, current session exact model/effort unavailable. Direct user request authorizes implementation; no blocking questions. Existing image caption row and accepted Studio card renders supply visual targets. No migrations or external changes; revert these commits for rollback. Install remains gated by AGENTS.md.

- [x] T13 Build Mac/iOS, render single/multiple-image replies and verify clipboard PNG/TIFF with scripts/test-image-review-gallery.sh. Check Studio/non-Studio card rendering via scripts/test-card-attention.sh and existing mobile thumbnail fixture. Commit/push, installation pending.

Readiness R1–R13 pass for this scoped follow-up. Local plan only. Preserve unrelated changes, original image files, gallery navigation, clipboard contents after test, and existing pinned-thread behavior.

Verified T13: Mac/iPhone builds and source check pass. Image-review fixture verified PNG/TIFF clipboard data and restored the user clipboard; inspected [single image copy action](copy-image-reply.png) and [each image in a grid](copy-image-grid.png). First harness compile overlapped the Mac build, which changed SwiftTerm.o and failed; reran after build completion successfully. Card-attention checks pass; inspected [Studio preview versus text-only Project](studio-only-card-thumbnails.png). All mobile-home-nav tests pass, including explicit Project image absence despite supplied thumbnail metadata and Studio image presence; inspected [mobile Projects](mobile-projects-without-thumbnails.png) and Studio screen. Gate thumbnails by view context, including the full Studios overview (ChatHomeView is Studio-only), so globally pinned Studio threads on Projects are text-only. No installation or runtime restart. Tidy remains report-only, no removals.

## Pinned group divider — 2026-10-08
Pinned cards currently run into the remaining chats without a visible boundary. Add a horizontal rule after the pinned group in both Mac sidebar card and list views, using the existing Divider style. Preserve ordering, pinning, thumbnails and navigation; no iOS or data changes. Source delivery committed/pushed; installation awaits user approval.

Current: [user screenshot](</Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/45E5942B-68A6-4E47-96DC-9E97873B2A70/Pasted image.png>). Target sketch:
```text
Pinned
[pinned card] [pinned card]
─────────────────────────
[other card]  [other card]
```

- [x] T14 Add divider, build Mac and inspect the native ContentView fixture from scripts/test-studio-chat-sidebar.sh. Success: full-width rule below pins, other cards retain normal layout. Commit/push scoped files. No install until approved; rollback by reverting this UI commit.

Work preparation: R1–R13 pass; local plan, linear execution, current session exact model/effort unavailable. No blocking questions. R12 n/a for source-only UI changes. Existing native sidebar render provides verification; no new test needed for this static layout.

Verified: Mac build and source check pass; studio-chat-sidebar suite passes. Inspected [native sidebar divider](pinned-divider.png): full-width rule separates pinned Studio tiles from the remaining card. Installation pending.

# Studio panels in Home

Shelby requests a grid rather than full-width rows per Studio. Put Studio groups in adaptive outer columns (minimum 440pt, allowing 3–4 groups at wide widths), each with a two-column thread grid and clear heading/count. Narrow windows keep fewer Studio groups per row. Current screenshot: `/Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/1F8C122B-F69B-4DB2-9DBB-527071C34C1F/CleanShot 2026-10-04 at 11.11.16 AM@2x.png`.

Target: `[Geekify: A B][PlayCase: A B][SDHQ: A B][USA: A B]`, with each Studio's additional threads on rows inside its panel. Top-align groups. Preserve all card actions, filtering, sorting, page partition and archived records. No changes to Projects/Chats/Archive page layouts or sidebar/mobile.

Local plan; user requested implementation in ongoing turn. Linear, Codex GPT-6.1-Sol Medium from handoff. R1-R13 pass; no schema/data changes; core commit rollback; test native Home suite plus wide/narrow four-Studio rendered fixture. No blocking decisions.

- [x] STUDGRID1: nested two-column Studio cards, adaptive outer grid.
- [x] STUDGRID2: Home navigation/persistence/history checks and real rendered 4-panel + narrow fixture inspected.
- [x] STUDGRID3: pin core, commit/push, build/install Mac under standing authorization.

Native Home suite passed in `/tmp/chatterbox-mac-home.pR6D41`; all page/action/history checks passed, four top-aligned Studio panels at 2000pt and in-bounds cards at 640pt. Inspected actual production-view wide/narrow captures in `/Users/shelbyklein/Chatterbox/Screenshots/studio-home-grid`. First fixture failed because creating sample Studios navigated away from Home; explicitly reopening Home after sample creation fixed the fixture. No production failure identified.

Pinned in shared Core `5c3a4ec`, Chatterbox `eb82539`, Golem `8427c4e`. Mac builds pass; installed hash identity verified. Installed interactions not driven.

## Revision: four icons on the left and leading toolbar

Shelby replaces the panel grid with a compact left-aligned Studio stack. Each heading has four icon tiles across beneath it, wrapping additional threads. Move Command Center, Settings and New Chat into the leading navigation toolbar. Current evidence: attachments BA0843FA-BF3E-4DE4-BE5E-24F4928893F0 and A470964B-7A84-45F2-A49A-BE7CC1CA0C27. Sketch: `Studio name / [icon][icon][icon][icon] / [icon]`, next Studio below.

Keep thread titles under icons and full names/status in hover and accessibility descriptions; preserve selection/context menus/history/search. Other Home pages and mobile unchanged. Linear execution, GPT-6.1-Sol Medium per current session handoff; no delegation. No blocking questions. Readiness R1-R13 pass. Local plan only; no GitHub issue mutation. Rollback: revert Core pin and restore backed-up app; no data changes.

- [x] ICON1: compact left-aligned four-column Studio grid and leading toolbar. Verify native wide/narrow layout and thread selection.
- [x] ICON2: inspect rendered screenshots, build, commit/push Core and consumer pin; backup/install Chatterbox under standing authorization.

## Command Center ordering addition
User requests quick reordering without dragging, ideally animated. Add previous/next arrow controls per tile, disabled at bounds; swap saved slot references without touching chats, drafts, provider state or active selection. Sketch: `[Thread title ... ← → expand ×]`. Animate 0.25s respecting Reduce Motion. Verify actual native arrow clicks, saved reload and draft/history preservation in `scripts/test-command-center.sh`. Deliver with this scoped Mac UI install; rollback same Core pin/app backup. Linear same executor, R1-R13 pass, no blocking questions, local tracking only.
- [x] ORDER1: implement saved adjacent swaps, accessible arrow controls, reduced-motion-aware animation; test native click/reload and inspect render.

Verification: final Home suite passed `/tmp/chatterbox-mac-home.Nb5iDf`, including native icon click, left-aligned stack, four columns/fifth wrap, narrow bounds, navigation/history/drafts. Command Center suite passed `/tmp/chatterbox-command-center.mlhlzj`, native previous-arrow swaps/restoration, persisted order, active-slot/draft/history preservation. Final Mac build passed. Production WindowGroup toolbar rendered via current-process ScreenCaptureKit and inspected at `/tmp/chatterbox-toolbar.I2n8Nm/toolbar.png`; leading controls confirmed. Animation configured 0.25s, Reduce Motion disables it; frame-by-frame playback and installed manual interactions not tested. Reorder fixture shows a canceled background catalog lookup banner, unrelated to sorting; no agent request submitted. One intermediate compile was discarded after sources changed during compilation; final stable-source suites/build passed.

Send-delay finding (read-only, separate from UI delivery): Mac projections send via `remoteCommand` and fetch event-triggered state after 100ms. Codex mid-turn `codexSend` appends a user item without `onChange`, then awaits `turn/steer`; immediate transcript notification missing until provider/another event. Matches sent-while-working scenario, but physical timing not measured. No send-path changes or live runtime restart in this UI update.

Delivery: Core `073bcb4` pushed; consumer pin included with native test updates. Mac source built successfully; app backup `/tmp/Chatterbox-before-studio-icons.app`; install verification recorded below after replacement. No Golem app/Core pin or mobile install changes.

## Revision: compact groups side by side
Shelby's reference `742CC953-0EA0-4C4F-B434-0897A8AD50DC` clarifies that Studios should sit next to each other. Each group takes only the width of its threads (up to four icon columns), with additional threads wrapping inside; whole groups wrap at narrower widths, aligned at their headings. Target sketch: `[SDHQ: icon] [PlayCase: icon] [USA Archery: icon icon icon icon / ...]`. Preserve icon controls, search, filters, selection/history/context menus and all other Home pages. No data, account, runtime or mobile changes.

Linear, same GPT-6.1-Sol Medium executor; R1-R13 pass; no blocking questions. Local tracking only. Deliver Core fix + Chatterbox pin committed/pushed, Mac built/installed. Rollback revert pin and restore backed-up app.
- [x] FLOW1: intrinsic-width Studio groups in a wrapping layout. Native Home suite verifies top-aligned neighboring groups, narrow wrapping/no overlap, four icons per row and existing-thread click. Inspect wide/narrow real renders.
- [x] FLOW2: commit/push, build, backup/install/relaunch Mac and verify installed binary.

FLOW1 evidence: `scripts/test-mac-home.sh` passed `/tmp/chatterbox-mac-home.cCcKwU`; actual Home view renders inspected at wide/narrow widths. Four variable-width Studio groups top-aligned side by side, four icons per row/fifth wraps; narrow groups wrap without overlapping; icon opens original session. Mac build passed. Installed manual interactions are not separately tested.

FLOW2: Core `5663024` pushed; app backup `/tmp/Chatterbox-before-studio-flow.app`. Build complete, consumer pin and installation follow under standing authorization. Connection concern investigated read-only: current session Direct ChatGPT/auth present; Gmail/Calendar/ClickUp tools exposed, Drive absent. No provider/auth/settings files modified.

FLOW2 complete: Chatterbox `2eeca2e` pushed, installed and reopened PID 59518; installed debug library SHA256 equals the completed build. Working copies clean after scoped delivery. Only UI app relaunched; no account/provider/pairing changes.

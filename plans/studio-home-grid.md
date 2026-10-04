# Studio panels in Home

Shelby requests a grid rather than full-width rows per Studio. Put Studio groups in adaptive outer columns (minimum 440pt, allowing 3–4 groups at wide widths), each with a two-column thread grid and clear heading/count. Narrow windows keep fewer Studio groups per row. Current screenshot: `/Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/1F8C122B-F69B-4DB2-9DBB-527071C34C1F/CleanShot 2026-10-04 at 11.11.16 AM@2x.png`.

Target: `[Geekify: A B][PlayCase: A B][SDHQ: A B][USA: A B]`, with each Studio's additional threads on rows inside its panel. Top-align groups. Preserve all card actions, filtering, sorting, page partition and archived records. No changes to Projects/Chats/Archive page layouts or sidebar/mobile.

Local plan; user requested implementation in ongoing turn. Linear, Codex GPT-6.1-Sol Medium from handoff. R1-R13 pass; no schema/data changes; core commit rollback; test native Home suite plus wide/narrow four-Studio rendered fixture. No blocking decisions.

- [x] STUDGRID1: nested two-column Studio cards, adaptive outer grid.
- [x] STUDGRID2: Home navigation/persistence/history checks and real rendered 4-panel + narrow fixture inspected.
- [x] STUDGRID3: pin core, commit/push, build/install Mac under standing authorization.

Native Home suite passed in `/tmp/chatterbox-mac-home.pR6D41`; all page/action/history checks passed, four top-aligned Studio panels at 2000pt and in-bounds cards at 640pt. Inspected actual production-view wide/narrow captures in `/Users/shelbyklein/Chatterbox/Screenshots/studio-home-grid`. First fixture failed because creating sample Studios navigated away from Home; explicitly reopening Home after sample creation fixed the fixture. No production failure identified.

Pinned in shared Core `5c3a4ec`, Chatterbox `eb82539`, Golem `8427c4e`. Mac builds pass; installed hash identity verified. Installed interactions not driven.

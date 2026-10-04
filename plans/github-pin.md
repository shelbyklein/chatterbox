# Theme-aware GitHub pin

The GitHub website pin currently renders its black favicon unchanged, making it hard to distinguish on a dark sidebar tile. PinIcon is shared by global square pins and project/Studio pills; apply template tint only for the actual GitHub website host, using the favicon's existing alpha shape and semantic primary color.

Current evidence: [user screenshot](/Users/shelbyklein/Library/Application%20Support/Chatterbox/Attachments/5A3C324A-D8C0-4713-A040-D92509969FEE/CleanShot%202026-10-04%20at%203.55.00%20AM@2x.png).
Target sketch: [light/dark](assets/github-pin/themes.svg); GH denotes the unchanged official favicon silhouette.

## Work preparation
Confirmed by user's direct update/check request. Linear execution: GPT-6.1-Sol Medium (session handoff); single shared view change. local:github-pin. Ready: R1–R13 pass; GitHub issue writes excluded under standing read-only issue instruction. No open questions. Existing Mac commit/push/install authorization applies.

## Success and deliverables
GitHub mark visibly black in light mode, white in dark mode; same tile, size, click target and label. Other sites retain original favicon colors. Scoped source/plan committed and pushed, Mac built/installed under standing authorization. Native rendered proof inspected for both themes at full and narrow sidebar width.

## Tasks / checklist
- [x] PIN-1: Limit template rendering to github.com/www.github.com website targets. Verify host lookalikes and other pin kinds remain original.
- [x] PIN-2: Build, render the production PinsSection in both themes and widths, inspect screenshot; commit/push/install and verify installed bundle.

## Boundaries, verification, rollback
No pin data/target changes, favicon fetching changes, mobile changes, branding redraw or new white badge. Use isolated native NSHostingView harness with production PinsSection, fixture pins and downloaded official favicon. Build with xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData build -quiet. Preserve installed bundle in /tmp/Chatterbox-before-github-pin.app before install; rollback by restoring that bundle. No new automated test suite for this low-impact rendering change; harness checks routing and renders.

## Verification
Production PinsSection rendered via native NSHostingView at 360/230pt in both themes: [light](/Users/shelbyklein/Chatterbox/Screenshots/github-pin/light.png), [dark](/Users/shelbyklein/Chatterbox/Screenshots/github-pin/dark.png). Both inspected. Exact-host routing assertions passed (including lookalikes, case and file pins). Build passed; click/open behavior unchanged, not clicked during isolated rendering.

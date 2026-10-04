# Layout verification — 2026-10-03

**Preserved fix fails narrow-window acceptance. Do not merge/install as a verified fix.**

Registration: existing worktree registered as `layout-fix`, chat AECB00AC-8A54-4FEE-B9EE-E8790DA19414 under Chatterbox; `worktreeOf` /Users/shelbyklein/Vibes/Chatterbox and branch worktree-agent-abe03c29354d9b44f. Live authenticated /v1/chats shows it in projects with the branch. No agent turn started or transcript duplicated. Installed Mac app relaunched to load the new record; simulator processes left alone.

Patch: four uncommitted product files based on 95a3ee1 remain intact. Main ecff8ae unchanged. Code fingerprint saved alongside this report.

Checks:
- `xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData build -quiet`: exit 0.
- `codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Chatterbox.app`: exit 0.
- `SPLIT_WIDTHS=1600,1100,900,800 scripts/test-split-layout.sh 53AC0557-5696-4138-93F9-0FA949453BAE /tmp/chatterbox-layout-proof/golem`: harness exited 0, but its printed geometry reveals FAIL (runner currently does not assert overflow). Isolated copied Golem transcript, current Avatar assets and parent/worktree chat fixture; automatic agent activity disabled.

Measured native windows with sidebar and Golem inspector:
| Requested width | Actual window | Actual split | Result |
|---|---|---|---|
| 1600 | 1600 | within window | no split overflow |
| 1100 | 1100 | 1256, x=-78 | both outer edges clipped by 78pt |
| 900 | 950 (new minimum) | 1256, x=-153 | both outer edges clipped by 153pt |
| 800 | 950 (new minimum) | 1256, x=-153 | both outer edges clipped by 153pt |

Real window-server screenshots were inspected; the narrow image visibly clips sidebar labels and the Golem right panel. Proof: /Users/shelbyklein/Chatterbox/Screenshots/mac-layout-verification/golem-900.png; wide and 1100 captures in the same directory.

The imposed 950pt window minimum does not override the split's larger fitting width. Further diagnosis is required before calling the layout repaired. No new product edits were made by this verification session. Late-opening inspector, keyboard focus, interactive divider resizing and smaller physical screens are not verified; the already-open Golem case fails first.

## Baseline comparison
Same native harness against main ecff8ae (test-only inspector-width logging property returns 0; no product patch).
```text
== Golem 1600: window content (1600.0, 820.0) minSize (861.0, 216.0) inspector 0.0 ==
== Golem 1100: window content (1100.0, 820.0) minSize (861.0, 216.0) inspector 0.0 ==
== Golem 900: window content (900.0, 820.0) minSize (861.0, 216.0) inspector 0.0 ==
```

Baseline limit: the live Golem record changed between the two snapshot copies. The preserved-patch capture includes a large crystal image in the rendered tail; the baseline capture ends later on text. Therefore the baseline is NOT a controlled before/after regression comparison. It shows the failure is content-dependent; only the patch failure against its captured fixture is established. The patched run also includes copied parent/worktree sidebar rows. Do not attribute a regression solely to the patch from these two runs.

# Widget usage bars verification

Baseline parent `8b62317`, Core `368b1c2`. The widget now renders an individual native determinate ProgressView for each displayed limit window, alongside its text. The same usedFraction normalization drives text and bars; unknown, nonfinite and reset readings have no meter. Colors match the Usage screen thresholds (accent, orange from 75%, red from 90%). The footer explicitly labels percentages as used. Redundant meter announcements are hidden; provider accessibility labels retain all window percentages and unavailable text.

## Checks

- `scripts/tests-for.sh --why Core/ChatterboxWidget/ChatterboxWidget.swift Core/Shared/WidgetSnapshot.swift tests/widget` selected `test-widget.sh`; no missing mapping. Selection: `build/widget-usage-bars-selection.log`.
- The same selector with `--run --fail-fast` passed: **1 script passed, 0 failed, 0 not run**. Model/persistence/cache regressions passed, including 12 added normalization checks covering ordinary, zero, full, clamped, nil, nonfinite and expired meter readings.
- Native iPhone 17 Pro/iOS 26.2 widget fixtures: **3 tests passed in 38.443 seconds**. Small, medium and large provider bounds/labels fit, missing/stale states retain their explanation, zero/full and unknown/expired readings retain accurate labels. Native screenshots use synthetic values, actual widget SwiftUI source and WidgetKit dimensions. Artifact `build/widget-test.Yvvfnf`; stable log `build/widget-usage-bars-verified.log`.
- All eight captures were visually inspected in one batch. Bars have the expected fill, colors and per-window labels; activity is visible, and no widget footer is clipped. Small long titles truncate within their row as intended. No correction or second visual pass was needed.
- `scripts/check-sources.sh`, parent/Core diff checks passed. No target source additions; project regeneration was unnecessary. These are focused checks, not a full-suite green claim. The known chat-switch baseline failure and incomplete release coverage remain recorded in the prior shipment.

## Native captures

[Small](usage-small.png), [medium](usage-medium.png), [large](usage-large.png), [stale light](usage-stale.png), [missing light](usage-empty.png), [small boundary readings](usage-boundaries-small.png), [medium boundary readings](usage-boundaries-medium.png), [large boundary readings](usage-boundaries-large.png).

## Delivery

Core `ed603d0`, parent source `1d60ba6` committed/pushed to main. Phone Dev installed and opened on Shelby's Duo through `scripts/install-phone.sh --dev`. The device WidgetKit extension built and its signature verified. Dev intentionally embeds no widget; physical Home Screen activation remains gated by a subsequent Ship. Real app/service/configuration hashes stayed unchanged. No Mac install/service restart, real app update, account/configuration change, provider request or TestFlight upload occurred. [Delivery metadata](dev-delivery.json).

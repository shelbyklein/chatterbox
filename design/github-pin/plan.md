# Restore GitHub's pin mark

GitHub's pin shows a filled circle because favicon discovery now prefers an Apple touch icon with a circular background, while PinIcon templates the whole alpha mask. Fetch GitHub's transparent favicon.ico instead; retain the theme-aware template and all other websites' icon discovery.

Before: user's screenshot /Users/shelbyklein/Library Application Support/Chatterbox/Attachments/F2A0A8B7-621B-4447-8743-6B43726797BC/CleanShot 2026-10-06 at 9.46.58 AM@2x.png. Target: recognizable GitHub silhouette (transparent surrounding pixels), white in dark mode and dark in light mode.

- [x] G1 Render actual fetched GitHub pin in both themes, inspect mark, build.
- [x] G2 Install verified Mac UI; no daemon restart or GitHub writes.

Success: recognizable mark in both themes. Deliverables: local source/fixture/render evidence and installed Mac app; preserve earlier pending card/link changes. Linear gpt-6.1-sol medium; user requested repair. Readiness pass R1–R13; target sketch uses official transparent favicon /tmp/chatterbox-github-favicon.ico (32x32, alpha verified). No blocking decisions or changes to data. Rollback: previous app saved under /tmp/chatterbox-card-rollback.*. Test: scripts/test-github-pin.sh, Mac xcodebuild; native PinIcon calls same PinStore lookup as sidebar. Installed UI interaction separate from fixture verification.

Results: native PinStore/PinIcon network fetch passed, transparent corners verified; dark/light renders inspected and recognizable. Mac build and install passed; app executable matches build. Daemon not restarted. Earlier pending card/link work preserved, GitHub unchanged. [Dark](dark.png), [Light](light.png). Source remains uncommitted/unpushed.

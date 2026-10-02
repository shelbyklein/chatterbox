# Golem model popover hosting repair

Golem's cog opens a 300pt settings page and replaces it with the shared 380×600 model picker. Shelby's current screenshot shows the picker shifted outside the host's left edge after the previously shipped fixed-picker-size change. Prior tests exercised a direct ModelPicker entry, not this page replacement. Reproduce the actual cog entry and remove unstable outer sizing while keeping every selected setting.

Current evidence: [reported screenshot](reported.png); target [inset layout sketch](target.svg). Files: ChatSettingsCog.swift and ModelPicker.swift.

Success criteria: cog → model and direct picker fit inside their popover; notes wrap; settings are unchanged by presentation; narrow/wide/right/bottom edge captures fit the available screen. Deliver scoped source, rendered proof and local test runner, committed/pushed to main and installed on Mac.

Tracker: local:C5FAE527-06CE-4BBC-942B-1E3EDEBDC35A.

- MP-1: reproduce the exact entry, fix outer host sizing and verify preserved settings. Acceptance: actual cog-to-model capture has bounded content, selected model/effort/Fast/access unchanged.
- MP-2: exercise direct entry, return to settings and narrow/wide/screen-edge windows; inspect captures; build, commit, push and install. Acceptance: each rendered state fits, build and installed binary/signature pass, report interactions not exercised.

Use an isolated temporary data/host folder, nonactivating test window and current-process captures. Drive the production keyboard-request hooks to open settings and switch to models; inspect live NSHostingView/popover frames. Native input can be synthesized inside that process where supported. Do not take over the user's app or touch real chat settings.

Preserve models, effort, Fast mode, permissions, presets, account/proxy routing, mobile UI and other worktrees. No schema changes. Rollback: reinstall parent fda9b44 build; no data rollback needed. User already authorizes build/push/install/restart for this repair. No open scope questions.

Work preparation: confirmed by Shelby's retry request; linear, gpt-6.1-sol / medium (verified current session turn_context). Single-file layout ownership makes delegation unnecessary. Readiness pass: R1–R13 covered; local plan, no GitHub issue to close. Begin now per explicit implementation request.

Verification: the isolated real cog route did not reproduce Shelby's exact left shift. Before the change the host resized from 326×512 to406×626; after the change Settings → Models → Settings stays406×626 at identical origins, with both pages retained, hidden controls disabled and hidden from accessibility. Final real current-process captures cover wide/narrow/right/bottom edge and direct picker. Model/effort/Fast/access invariants and fitting-size equality pass. Captures visually inspected; note wraps and all control edges remain inset. Entry driven with production keyboard-request hooks, not native clicks. No claim of exact original-bug reproduction or short-screen verification.

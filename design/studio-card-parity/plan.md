# Studio card parity

Studio sessions on the Mac use static Working labels and dots under their titles, while Project cards identify the provider and put activity at the top right. Match those visual conventions on Studio pinned previews, inspector rows and the selected-session header. Preserve Studio images and all navigation.

Current evidence: [user screenshot](assets/before.png), `Core/Chatterbox/Views/StudioOverview.swift` InspectorRow/StudioPreviewCard/InspectorDetail, and Project `ThreadCard` in ChatHomeView.swift. [Target row sketch](assets/target.svg) places provider at left and activity at right, with title, preview and age below.

Success criteria: provider is visible even with a thumbnail; active sessions show the shared rotating arc at top right (Reduce Motion respected), idle/unread/waiting retain shared dots; static Working labels disappear from Studio cards/rows/header; wide/narrow navigation and preview tests pass and fresh renders are inspected.

- [x] C1 Share provider/activity components with Project cards and apply to Studio surfaces. Acceptance: build and shared state checks pass.
- [x] C2 Run `scripts/test-mac-home.sh`, inspect pinned/inspector wide/narrow states. Acceptance: navigation/filter/image regressions pass and inspected renders show icons and top-right indicators without clipping.
- [x] C3 Commit and push scoped Core/root changes and evidence. Acceptance: clean scoped state and remote push succeeds. Installation requires user approval under AGENTS.md.

Deliverables: source, test and evidence committed/pushed, Mac activation pending approval. No mobile changes, schema changes, thumbnail removal, chat execution changes or GitHub issue mutations. No blocking questions. Rollback: revert scoped source commits; no data migration. Install is a separate approval gate.

Work preparation: local plan, confirmed by direct layout-change request; execute now within that scope. Linear because shared components and Studio views overlap. Current session; exact model/effort unavailable. Readiness R1–R13 pass, R7 local checklist, R12 n/a for source-only delivery. Visual authority is the existing Project card; no new visual world.

Verification: Debug Mac build passed. `scripts/test-mac-home.sh` passed all status, large-image, grouping, native click/filter/Open Chat/double-click, saved selection, empty and narrow/wide layout checks. Inspected [inspector](assets/inspector.png), [pinned cards](assets/pinned.png), and [narrow/light inspector](assets/narrow.png); these are native fixture renders with synthetic artwork, not installed-runtime evidence. Shared ActivitySpinner uses Core Animation and honors Reduce Motion. Installation remains pending approval.

Delivery: Core 3825870 pushed; root evidence and pointer committed/pushed with this plan. Activation pending user approval.

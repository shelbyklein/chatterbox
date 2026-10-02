# Mobile conversation styling

Mobile chats currently share an accent-tinted user bubble; assistant replies render without bubbles (`ChatDetailView.swift`, ItemRow). Golem also exposes model text in the title and technical rows inline. Shelby requested Codex green, Claude orange, and Golem replies as one bubble per paragraph.

## Target
[Layout sketch](target.svg). Retain regular assistant replies as documents; tint outgoing bubbles and Send by the selected agent. Golem replies use neutral left-aligned paragraph bubbles, with structured Markdown blocks kept intact. Technical steps remain expandable, narration stays visible, and settings move behind a cog with no model subtitle.

## Work preparation
Scope confirmed by direct implementation request. Now: implement in this session. Linear, GPT-6.1-Sol / medium (verified current turn_context); one mobile surface, no parallel ownership needed. Baseline 92625a3; preserve golem-rig worktree and preceding uninstalled sidebar changes.
Tracker local:EBD7ADF2-C27B-444C-98B0-BE64DDD6A5D4. MC-1 implement; MC-2 verify.
Readiness: pass R1-R11/R13; R12 n/a, no storage/schema/deploy changes. [Current simulator capture](before.png) captured from the pre-change binary; target linked above. No blocking questions.

## Outcomes and deliverables
- Phone/iPad visibly distinguish Codex green and Claude orange, without recoloring body text.
- Golem paragraphs are individual readable bubbles, Markdown structures intact, user right/reply left.
- Settings, copy-whole-message, dictation, Send/Stop, attachments and context remain accessible.
- Scoped code and verification committed; mobile device build succeeds; install and push await user request.

## Tasks / acceptance
MC-1: Add mobile palette, paragraph block rendering and conversation row layout. Check block parsing keeps lists/code/table together, tools remain expandable and settings accessible.
MC-2: Run isolated phone/iPad simulator UI fixtures via scripts/test-mobile-conversation.sh; inspect captured light/dark layouts and settings, Copy and composer controls. Build ChatterboxMobile for iOS. Preserve mobile history refresh behavior via existing regression suite.

No agent/session logic, API mutations, stored data, Mac chat styling, VM, sidebar redesign or installations in scope. Colors follow the selected chat agent, because the existing mobile item API does not store a per-message backend. Rollback: revert this scoped UI commit. No migration needed.

## Verification — 2026-10-02

- Signed ChatterboxMobile iOS build: succeeded (`build/ios-device`).
- Conversation UI checks: iPhone 17 Pro and iPad mini simulators, one test each, zero failures. Settings cog, step disclosure, Send after typing, paragraph count, intact Markdown list/code/table, no chat POSTs.
- Existing mobile history regression: two tests, zero failures, opening/reopening/foreground refresh, interrupted loading and draft preservation.
- White text contrast: Codex 6.43:1; Claude 6.21:1.
- Inspected [Golem on iPhone](golem-dark-iphone.png), [Claude on iPhone](claude-light-iphone.png), [Golem on iPad](golem-dark-ipad.png), [Claude on iPad](claude-light-ipad.png). Light mode and settings captures are in this folder too. The simulator's Apple Intelligence welcome notification overlaps the header in some captures; content layout remains visible.
- Existing Mac sidebar commits and golem-rig worktree preserved. Device installation and push pending user request.

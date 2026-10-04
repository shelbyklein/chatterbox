# Mini reply acknowledgement
Golem mini currently keeps its response and composer open after the pointer leaves. Shelby wants hovering the response, body or input and then leaving to acknowledge the completed reply and hide chat, leaving Golem visible. Root hover already treats the whole panel as one region (GolemMiniWindow.swift); collapse preserves session drafts.

![Flow](assets/mini-hover-ack/flow.svg)
Current state: [expanded mini](/Users/shelbyklein/Chatterbox/Screenshots/mac-golem-floating/08-mini-excludes-floating.png).

Tracker: local:F3DBBCFE-224A-4A76-A3F1-C4AD9ECCAF41.
- MINI-ACK-1: track completed reply hover; debounce exit, cancel reentry and invalidation. Native regression must show no hover/no acknowledgement, completed reply collapse, renewed reply protected and draft retained.
- MINI-ACK-2: build production library, exercise native panel and captures, commit/push/install under standing authorization and verify installed binary.

Success: hovering then leaving the mini collapses completed replies and marks seen; movement within keeps it open; running replies or unanswered questions are not silently acknowledged; new drafts and attachments survive. No transcript deletion, submissions, mobile changes or routing changes. Open questions: none. Linear GPT-6.1-Sol Medium, one small controller/view change with one regression harness. Deliver code, test and plan committed/pushed, Mac built/installed. Rollback: backup app before installing; revert scoped commit or restore bundle. Test: scripts/test-mini-ack.sh linked against built production Debug dylib, native window screenshots before/after. Readiness R1–R13 pass; user instruction supplies implementation authorization.

## Verification
Production Debug build passes. scripts/test-mini-ack.sh passes: native cursor enters bubble, body and composer, remains open internally, then collapses on exit; seen marker points to final reply; draft, attachment and transcript count retained. No hover, reentry, running reply, pending question and newer reply guard checks pass. Screenshots inspected via window-server capture in an isolated fixture; live installed interactions remain for Shelby to try.
![Before exit](/Users/shelbyklein/Chatterbox/Screenshots/mini-hover-ack/before-exit.png)
![After exit](/Users/shelbyklein/Chatterbox/Screenshots/mini-hover-ack/after-exit.png)

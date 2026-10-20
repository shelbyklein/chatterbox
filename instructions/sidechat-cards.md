# Sidechats inside their parent cards

Sidechats currently consume a full card beside their parent while sidequests appear as compact rows inside it. Show both kinds of child conversation inside the parent card, and expose New Sidechat in the session's existing right-hand icon column. Keep sidechat creation, independent history, provider settings, and return behavior unchanged.

Local plan: `instructions/sidechat-cards.md`. Scope confirmed by the October 20 request.

## Current and intended view

Current screenshot: [Sunward and separate sidechat card](</Users/shelbyklein/Library/Application Support/Chatterbox/Attachments/0233EB5B-653C-474E-8167-49252228B7DD/Pasted image.png>).

Target sketch:

```text
[ Sunward parent card                 ]       session tools
[ preview                             ]       [Library]
[ sidequest icon | provider | task  ○  ]       [Quick prompts]
[ sidechat icon  | provider | name  ○  ]       [New Sidechat]
                                              [Sidequest]
```

## Success criteria

- Active children are represented by compact, clickable rows in their parent's card; no duplicate standalone card. An archived parent leaves its children accessible as cards.
- New Sidechat is directly available from the right-side session tools, using the same button size and native creation behavior as the existing menu action.
- Both child kinds retain working/waiting/completed indicators and Open/End actions, without changing stored conversations or sidequest routing.

## Work preparation

Mode: linear, because the model helpers, cards, and entry control share a small surface. Executor: current session; exact model/effort unavailable. Readiness: pass; R1-R11 and R13 covered below. R12: no data migration; revert the scoped Core/root commits and reinstall with `scripts/install.sh` if needed. No GitHub issue mutations are in scope.

## Tasks and checks

- [x] S1 Model/card: hide live children as standalone cards and render both types under parent. Test child grouping, quest preservation, click navigation, and archived-parent fallback in `scripts/test-sidechat.sh`.
- [x] S2 Entry: add an icon-only New Sidechat control in ChatView. Native-click it in the same fixture; verify a fresh child opens and the parent's history/draft/running state remain intact.
- [ ] S3 Delivery: inspect rendered card proof and the actual installed right-side icon; run Mac build, scoped commit/push, install/reopen under standing approval, and run tidy report. No daemon restart is needed for these Mac UI changes.

No blocking questions. Tools crash diagnosis is tracked separately; do not describe an unconfirmed cause as fixed.

Validation: `scripts/test-sidechat.sh` passed native icon creation, unchanged parent history/draft/running state, child grouping/navigation, and archived-parent fallback. Log: `build/sidechat-cards-test.log`. Mac build and `scripts/check-sources.sh` passed; installed verification remains below S3.

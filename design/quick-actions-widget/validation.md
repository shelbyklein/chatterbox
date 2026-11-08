# New Chat quick actions validation

Baseline: parent `8d8570c`, Core `b170c98`. Issue [67](https://github.com/shelbyklein/chatterbox/issues/67). Issue66 implementation and Dev delivery preceded this work; real widget shipment is pending.

## Result

The New Chat widget retains its kind and now has a full-width “New chat…” link and actual App Intent provider buttons. Selection persists in the existing app group, highlights in the timeline and resolves from the generic URL at app handling time. Default/invalid selection uses Codex Sol Medium; Claude uses Opus 5.5 Medium. Legacy provider-specific URLs remain valid. Selecting a chip creates/sends nothing. The app requests focus once for the successfully created widget chat after navigation; ordinary chat routes retain their draft and do not autofocus.

## Focused checks

- `scripts/test-widget.sh`: five native tests passed (110.556 seconds), including actual App Intent button taps, persistence across process relaunch, selected traits, target bounds, field URL, incumbent activity and dedicated Usage renders. Model/cache checks passed.
- After the one visual correction batch: `WIDGET_TEST_ONLY=testNewChatWidget scripts/test-widget.sh`: one native test passed (44.999 seconds), covering medium/small in dark/light/xxxLarge and Codex selection. Model/cache checks passed again. Final artifacts: `build/widget-test.zXkLyX`.
- Focused `scripts/test-mobile-home-nav.sh iphone`, iOS26.2, `testWidgetNewChats`, `testUsage`, `testNewChatPicksSettingsFirst`: three tests passed (116.940 seconds). Both providers create distinct ordinary chats with exact model/Medium, keyboard shown and unsent draft typed without a focus tap. Failure/retry works; no messages sent.
- Expanded final `testWidgetNewChats`: one test passed (43.307 seconds), additionally returning to the earlier Codex chat, confirming its draft persists and the keyboard stays dismissed. Final artifacts: `build/mobile-home-nav.Ye4k0B`.
- `scripts/test-tests-for.sh`: ten checks passed. `scripts/test-flavor.sh`: real and Dev identity checks passed. Project regenerated with `xcodegen generate`; source check and diff whitespace checks passed.

The selector maps the intent and composer paths to native home navigation coverage. It also selects other broad mobile suites sharing the app wrapper; those unrelated flows were not rerun for this focused Dev delivery. Full release coverage is deferred to Ship. The known chat-switch baseline assertion failure and incomplete broad release coverage remain recorded; this is not a green full-suite claim.

## Native visual review

Two rounds completed, then stopped. The first found truncation in small xxxLarge and faint caption/outline. One correction batch removed the small compose icon, shortened only the small model caption and strengthened contrast. The final medium/small dark/light/xxxLarge screenshots are readable, controls remain inside bounds and provider targets are at least44pt. These are native SwiftUI fixture renders of production widget views, not fabricated mockups. The fixture substitutes a unique preferences suite to avoid real group writes, but executes the original App Intent buttons and implementation. Physical Home Screen interactivity remains unverified until real Ship because Dev deliberately has no widget extension embedded.

Original final captures:

- [Medium dark](quick-actions-medium-dark.png), [light](quick-actions-medium-light.png), [larger type](quick-actions-medium-large-text.png).
- [Small dark](quick-actions-small-dark.png), [light](quick-actions-small-light.png), [larger type](quick-actions-small-large-text.png), [Codex selected](quick-actions-codex.png).
- [Codex keyboard](widget-keyboard-codex.png), [Claude keyboard](widget-keyboard-claude.png), [Codex draft](widget-new-codex.png), [Claude draft](widget-new-claude.png), [return saved draft](widget-return-saved-draft.png), [creation failure](widget-new-chat-error.png).

## Delivery

Phone Dev install and signed extension/intent metadata verification pending. No Mac install/restart, TestFlight, real configuration changes or real shipment authorized for this task.

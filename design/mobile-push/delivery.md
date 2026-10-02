# Mobile push delivery

Mac sends APNs alert pushes directly; no relay or mobile background polling. Events cover new approvals/questions, completed replies, Golem automatic briefings and important email. Per-event toggles, sound and private (generic) previews live in Settings → iPhone → Push notifications. Import an APNs .p8 key with Key ID and team 9F3MKVW9C5; the private key is stored in macOS Keychain, not defaults or the repository. Mac must be awake with Chatterbox open and the companion enabled.

Phone/iPad: bell in chat-list toolbar opens Notifications. Opt in to Apple's authorization, register device token, then post it through the existing authenticated companion connection. Token rotation and app launches re-register; disable updates the paired record. Unpair attempts to remove push registration; when offline, remove that device in Mac settings for definitive revocation. Remote notifications carry a chat UUID, and tapping routes to that chat (including archived chats). Only a currently visible chat suppresses foreground banners. Reading the chat still requires Wi-Fi or Tailscale.

`aps-environment` is development for Debug, production for Release; the provider uses matching Apple endpoints. JWT uses ES256 raw signatures and refreshes after 50 minutes. Delivery queue is bounded at 100 events; API/network errors are shown in Mac settings. Apple acceptance is not proof of visible delivery. This first version is best effort with no durable queue or automatic transient-error retries; it does not send from the helper after Mac app quit, or approve actions from notification buttons.

Validation:
- `scripts/test-mobile-push.sh`: fresh P256 key signs JWT and verifies signature/iat/iss; preview-off payload excludes private body; sandbox/topic headers checked. Isolated loopback companion: unauthorized/revoked 401, invalid registration 400, valid register/disable/delete 200, legacy record decoding. No real key was read/imported and no APNs request sent.
- `scripts/test-mobile-push-ui.sh iphone`: test-only injected target UUID opens intended chat; bell/settings/Done work in simulator. This exercises the navigation destination, not APNs reception, SpringBoard tap delivery or cellular connectivity. Screenshots: [phone settings](phone-settings.png), [target chat](tap-opens-chat.png).
- Mac and signed universal iOS build pass. Signed app and embedded provisioning profile both have development `aps-environment` and team 9F3MKVW9C5; signatures verify. Existing ContentView Sendable warnings remain.
- Mac setup, authentic Gmail email-card icon and Golem shadow rendered in isolated nonactivating test panels. Test bundle includes built asset catalog and copies avatar assets into temporary data; no real chat files changed.

Physical delivery pending APNs signing key (.p8 path + Key ID), installation approval, device notification permission/token registration, and a real Apple-accepted notification observed on iPhone/iPad. No claim of actual cellular notification delivery. Mac/device apps not installed or restarted in this task; nothing pushed.

Gmail source: https://www.gstatic.com/images/branding/product/2x/gmail_2020q4_48dp.png
Apple references: https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns and https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns

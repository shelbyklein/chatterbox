# Account Usage panel

Shelby approved a read-only visual of EasyCLIProxy quotas in Chatterbox. Use local management auth-files and api-call endpoints, never read or expose provider OAuth tokens. Preserve all routing/account settings.

Sketch: header [Account Usage | Refresh], configured route in toolbar popover, Claude heading / two-column account cards, Codex heading / two-column cards, timestamp. Each card: account, status, quota name + percent + bar + reset time. Unknown/failure is explicit. Settings → Proxy and persistent toolbar chart icon.

Linear execution in current GPT-6.1-Sol Medium session. Local tracked plan, no GitHub issue changes. Scope approved; readiness pass. Implementation and build/install authorized. No blocking decisions.

- [x] T1 Verify read-only upstream protocol and parser with live metadata plus malformed/missing fixtures.
- [x] T2 Build themed native UI, render it with live account data and inspect.
- [x] T3 Commit/push Core and app pin, install UI; verify installed binary. No daemon restart required.

Rollback: revert scoped commits and reinstall prior app. Never reset quota, mutate accounts, log management secrets, or change permission/proxy state. Request failure retains previous results marked stale. Tests: standalone Swift parser/live read-only harness; Mac build; actual SwiftUI render in isolated window. Actual account failover not part of this panel.

Reference inspected: router-for-me/EasyCLIProxyAPI quotaService.ts; installed core supports v0 management compatibility endpoints. Live Claude and Codex usage requests returned HTTP 200.

Evidence: scripts/test-proxy-quota.sh and --live pass (five accounts; Claude limited state observed). SwiftUI panel rendered at 680pt dark and 370pt light, inspected; saved under ~/Chatterbox/Screenshots/account-usage/. Mac build passes. Real installed entry-point clicks remain unverified; standalone render uses the production panel view and live store.

Installed source 6e81b3b, Core 718b776. App reopened (PID 71096); installed debug library SHA-256 matches build. No daemon restart or account changes.

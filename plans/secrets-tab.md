# Dedicated Secrets tab

Secrets & Accounts currently sits in the long General form (SettingsView.swift). Move the existing section to a dedicated Secrets tab in both builds using this shared SettingsView, preserving its editor, Keychain storage, project scopes and existing values. Local:secrets-tab; linear GPT-6.1-Sol Medium. No agents. Current section proof: /Users/shelbyklein/Vibes/Chatterbox/design/secrets/settings.png; placement evidenced by SettingsView General section; target [secrets-tab.svg](secrets-tab.svg). R1–R13 pass; this reversible presentation-only move needs no new behavioral test suite. No vault/settings/instructions changes or GitHub issue mutations.

- [x] SECRETS-TAB-1: Reuse SecretsSection in dedicated grouped form; General no longer includes it. Acceptance: code inspection and successful app build.
- [x] SECRETS-TAB-2: Inspect dedicated form render in isolated data, with no secret creation/reveal; preserve proof screenshot. Native tab selection remains unverified.
- [ ] SECRETS-TAB-3: Commit/push/install Mac under standing authorization; verify bundle and launch.

Deliver shared UI source, plan and inspected proof, committed/pushed and Mac installed. Scope Mac; no mobile controls, credentials or provider changes. Rollback: preserve current app bundle before install, restore it; no data migration.

Verification: app Debug build passed in build/GolemPlan. Dedicated production SecretsSettingsView rendered in an isolated NSPanel with empty fixture vault; inspected /Users/shelbyklein/Chatterbox/Screenshots/secrets-tab/settings-secrets.png. No credentials or metadata created/changed; no vault/storage/scope code modified. Native tab selection could not be exercised: the standalone NSHostingView does not expose the scene's tab bar as NSTabView, so its content was rendered directly. No new behavioral tests for this presentation-only move; installed tab clicking remains unverified.

# Golem split: activation and rollback

Issue: https://github.com/shelbyklein/chatterbox/issues/31

Source work and temporary fixtures are authorized. Live installation, adoption, LaunchAgent loading, physical-device provisioning, real provider requests and real push checks require approval for the concrete built result. Do not merge, release or close the issue implicitly.

## Processes and controls

- Chatterbox.app renders ordinary chats and connects to `chatterboxd`.
- Golem.app renders its assistant conversation and mini; GolemMobile is a separate universal app.
- `chatterboxd` owns conversations, provider resume state, mobile pairing and the companion/MCP gateways.
- `golemd` owns check-ins, waiting/finished policies, email sweeps, journal and policy preferences.
- Closing a window and quitting either UI leave the services alone. Chatterbox's Keep replies running preference controls stopping its ordinary turns when quitting.
- Golem's Pause Automation persists a pause. Stop Golem Service persists a pause and exits successfully. LaunchAgent crash recovery does not restart a successful stop. A future explicitly enabled launch remains paused until resumed.
- Settings → Plugins → Golem revokes integration. Email policy work may remain enabled independently; stop/pause it from Golem's service controls. Neither service prevents Mac sleep.

## Review before activation

Verify scoped source commits and draft PR, required behavioral regressions, inspected native screenshots, all performance budgets, signature identity, contents of both bundles, and the service LaunchAgent plists. Review known limits from `tests/golem-integration/artifacts/acceptance.md`; an unchecked acceptance item is not a completed requirement.

Services must have signed stable bundle paths. Keep ChatterboxHost and chatterbox-mcp beside chatterboxd. Set CHATTERBOX_HOST_BINARY and CHATTERBOX_MCP_BINARY explicitly in LaunchAgents. Do not use a temporary build folder for a live service.

Provision Golem's distinct iOS bundle ID/APNs topic `com.shelbyklein.Golem.mobile`. Chatterbox remains `com.shelbyklein.Chatterbox.mobile`. Each app obtains its own token in its own sandbox and pairs with its own displayed code. Do not transfer Chatterbox's iOS token into Golem.

## Approved adoption

1. Record current app build/signature and existing LaunchAgent state. Save copies of the installed bundles and relevant app preference domains.
2. Quiesce Chatterbox, its provider host and any old Golem jobs. Confirm no agent or older app is still writing. Disable automatic restart while taking the snapshot. A local directory alone does not establish quiescence.
3. Prepare an offline preference plist export and exact existing data, assistant, host and Claude-memory paths. Keep `~/Chatterbox/Dot` and its resolved Claude memory identity intact.
4. Run `scripts/golem-adoption.py adopt --data <existing-data> --assistant <existing-Dot> --host <existing-host> --memory <existing-memory> --preferences <export.plist> --backup <new-backup-dir> --quiesced`. This copies an allowlist; it retains original preferences and records the backup/import. It does not start services.
5. Verify backup hashes, conversation counts, UUIDs, attachments, drafts, pending approvals, provider offsets and paired-device registrations. Stop on any mismatch.
6. Generate reviewable plists with `scripts/package-golem-services.py`. The generator writes plists only. After approval, install signed bundles and opt-in LaunchAgents under the logged-in user's domain; never system-wide daemons.
7. Start chatterboxd, then golemd. Open both UIs and verify connection, scopes and data readback. Never run an older Chatterbox build against adopted data.
8. After approval for actual provider/push activity, execute a normal headless turn and a Golem turn with UIs absent. Verify exactly one persisted result after reconnect. Pair physical iPhone/iPad clients separately and check real APNs topics, notification taps and revocation.

## Rollback

Stop and disable only the verified new LaunchAgents and quiesce their writers. Run the offline restore tool against the verified backup. It first saves post-adoption data as an additive recovery export; it refuses to overwrite an existing recovery export. Restore the old matching bundles/preferences and only then enable the legacy writer. Do not turn off the plugin and start an old app against daemon-owned data. Reconcile post-adoption work explicitly before removing anything. Golem mobile revocation must not revoke Chatterbox devices.

## Limits of command delivery

Completed request IDs return their previous results without repeating side effects. A crash around external provider dispatch can leave `delivery_uncertain`; the client must inspect the chat before explicitly retrying with a new ID. This is not an exactly-once guarantee for an external provider across every crash window. Receipt capacity fails closed rather than evicting receipts and silently resending old operations.

## Mac trial authorization and main integration (2026-10-04)

The user required waiting for main to finish and merging this separate worktree, then said "ok good to go". This authorizes the scoped main integration and backed-up Mac development switch with Golem automation paused. Physical-device provisioning, real APNs, new paid-provider test turns, release and issue closure remain outside this approval.

Main's Restart Thread, Sidechat, Studio conversion, Home and Command Center behavior must survive the daemon split. During activation an unchanged existing provider host may be suspended for an offline snapshot and resumed for daemon reattachment, preserving provider processes and saved offsets. Close the legacy UI gracefully first and verify host/source identity; never leave the legacy UI writing concurrently. Preserve in-memory drafts separately before quit and import them into runtime draft state. No private capture or preferences belong in the public repository.

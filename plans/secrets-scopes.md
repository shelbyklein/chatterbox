# Todo: secret access by project and Studio

**Start after:** the `virtual-desktop` worktree (#48, Shelby-PC worker) is merged to main.
Requested by Shelby, 2026-10-22. Not started; scope still to confirm before building.

## Now

Each secret either goes to every session, or to a list of project folders
(`SecretEntry.projects`, matched in `SecretVault.entries(for:)`,
`Core/Chatterbox/Engine/Secrets.swift`). Studios can't be chosen, so a Studio's sessions
only get a secret that's open to everyone.

## Wanted

"Who can use this" offers projects **and Studios**. Picking a Studio gives the secret to
every session in that Studio (`record.studioID`), including new ones.

## Todo

- [ ] Confirm the options with Shelby: everyone / chosen projects / chosen Studios (mixable?),
      and whether Sidechats and automations follow their parent's access.
- [ ] Add Studios to `SecretEntry` (alongside `projects`; old entries keep working).
- [ ] Match Studio sessions in `entries(for:)`; the agent note and env follow automatically.
- [ ] Settings → Secrets editor: pick projects and Studios; the row's scope label names them.
- [ ] Test: a Studio-scoped secret reaches that Studio's sessions only (`scripts/test-secrets.sh`).
- [ ] Install, queue service restart.

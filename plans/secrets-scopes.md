# Todo: secret access by project and Studio

**Start after:** the `virtual-desktop` worktree (#48, Shelby-PC worker) is merged to main.
Requested by Shelby, 2026-10-22. Done 2026-10-22 (the merge landed as #49).

## Now

Each secret either goes to every session, or to a list of project folders
(`SecretEntry.projects`, matched in `SecretVault.entries(for:)`,
`Core/Chatterbox/Engine/Secrets.swift`). Studios can't be chosen, so a Studio's sessions
only get a secret that's open to everyone.

## Wanted

"Who can use this" offers projects **and Studios**. Picking a Studio gives the secret to
every session in that Studio (`record.studioID`), including new ones.

## Todo

- [x] Confirmed (Shelby): projects and Studios can be mixed; Sidechats, sidequests and
      automation runs follow their parent (their records carry its project and Studio).
- [x] Add Studios to `SecretEntry` (alongside `projects`; old entries keep working).
- [x] Match Studio sessions in `entries(for:)`; the agent note and env follow automatically.
- [x] Settings → Secrets editor: pick projects and Studios; the row's scope label names them.
- [x] Test: a Studio-scoped secret reaches that Studio's sessions only (`scripts/test-secrets.sh`); editor render `scripts/test-secret-scopes.sh`.
- [x] Install, queue service restart.

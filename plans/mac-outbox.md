# Mac outbox: changes made on the Mac are never lost

Shelby, 2026-11-05: a change made on the Mac (tags, rename, Brief, place, model and other
settings) must never be lost when the background service is slow, restarting or briefly
unreachable.

## What went wrong

In daemon mode the Mac sent its changes fire-and-forget (`RuntimeClient.command`): the
projection's `onChange` sent the whole record (minus items) as "metadata" once; settings, the
Brief, archive, Remote Control, create, delete, Studios, pins and preferences likewise. A send
that was lost, timed out or hit a restart was never sent again, and the next update from the
service (a `get` refresh or the full list) put the old record back: the tag vanished. The whole
record also carried stale copies of every other field, so it could undo a change made on the
phone meanwhile.

## What happens now

`RuntimeOutbox` (Core/Chatterbox/Engine/RuntimeOutbox.swift) keeps each change until the service
confirms it:

- **Sent at once, as a request.** The reply confirms it. Several fields changed together go in
  one request. Ops are sent per session in a fixed order: create, metadata, settings, setBrief,
  remoteControl, archive, delete (then Studios, pins, preferences globally), so a new session
  exists before its changes.
- **Retried.** A lost, timed-out or refused send is retried with backoff (1, 2, 4, 8, 16, then
  every 30 s) and again at once on reconnect (`runtime.resync`). Service errors that can't change
  (`chat_not_found` with no create pending, `permission_denied`, `invalid_record`…) give up, note
  it in Diagnostics and show the problem. A retried create that already exists, or a delete of a
  session already gone, counts as done.
- **Kept across a relaunch.** Pending changes are written to `mac-outbox.json` next to
  `mac-navigation.json` (0600) whenever they change, and loaded at launch (up to a week old).
- **Shown meanwhile.** Each change carries the record fields it shows as (`overlay`). Every
  projection (`AppModel.applyProjection`, the navigation cache too) goes through
  `RuntimeOutbox.project`, which puts pending fields back on top of the service's copy. A
  confirmed change says at which chat revision it was applied (the service's reply carries
  `revision`); it keeps showing until an update at least that new arrives, so an update fetched
  before the change landed can't flicker it back. A change whose reply was lost is also confirmed
  by an update that shows it.
- **Only what changed.** The Mac remembers each session's last copy from the service
  (`serviceBase`). `onChange` sends only the metadata fields that differ from it (or from a value
  still pending). The service's "metadata" op takes `{chatID, fields: {…}}` and applies just those
  (`RuntimeServer.applyMetadata`); a whole `record` (older apps) still sets every field, as
  before. The handshake advertises `metadataFields`; against an older service the Mac sends the
  whole record, still through the outbox.
- **Settings, Brief, archive, Remote Control** go through the outbox too, and now show on the Mac
  at once (model, effort and personality; the Brief; archived; Remote Control).
- **Create and delete.** A session made on the Mac stays in the list while its create is pending
  (a list refresh doesn't drop it); a deleted one stays gone while its delete is pending.
- **Studios, pins, preferences**: pending ones keep the Mac's copy when the list reloads.

## What shows

Nothing, unless a session has had a change pending for 10 s (`slowAfter`): then a small
"Saving…" (still waiting for the reply) or "Not saved yet" (a send failed; it keeps trying) in its
sidebar row and above its message box, with the last error in the tooltip. It goes when the
change is confirmed.

## Not covered

Messages (`send`, with their own echo), drafts (already re-sent until confirmed), approvals and
answers, stop, shell, restartTools and other one-off actions are unchanged: they are actions, not
state to converge on, and replaying them later could do harm.

## Tests

`scripts/test-mac-outbox.sh` (tests/mac-outbox): the Mac app against a real service through a
proxy that drops, delays or refuses requests; the service killed and restarted mid-change; the app
quit with changes pending and a new one started. `scripts/test-tags-service.sh` covers the
service's partial and whole-record metadata bodies and the revision in replies.

# Favorite models instead of presets

## Summary

Presets (named agent + model + effort combinations, shown as pills beside the model
chip) go. Picking becomes one step: click the model chip (or ⌘⇧M), click a model or press
its number, drag the effort. Favorites are just models; effort is the slider.

## Decisions (Shelby, 2026-10-22)

- One popover: **Favorites** (numbered 1–9, press the number to pick), **All models**
  (Claude and Codex together, ★ to favorite), then the **effort slider**.
- Click picks the model; dragging sets the effort. No confirm button: nothing changes until
  the next message. Picking stays open so the effort can be dragged right after; click away,
  Esc or Return closes. A model from the other agent says "switches to Codex/Claude".
- Switching models keeps the closest effort step the new model supports.
- New sessions start on the model and effort last used for that kind of session
  (Chats, Studios, projects). An explicit "New Claude/Codex Session" keeps its agent.
- Existing presets become the first favorites, in order (models only).
- New Session sheet keeps Start; iPhone keeps Done.

## Deliverables

- `Engine/ModelFavorites.swift`: favorites (synced to the service as `modelFavorites`),
  migration from presets, `choose`, `setEffort`, last-used per kind (`lastModel.<kind>`).
- Mac `ModelPopover` rebuilt; composer chip opens it directly (preset pills removed);
  Golem's cog, Settings and Automations lose their preset controls; Settings lists favorites.
- New sessions (app, service, the phone's draft) start on the last-used model and effort.
- iPhone: options carry favorites; the form shows Favorites and All models, no preset tiles.
- Kept for older data: `ModelPresets` still reads saved presets (an automation saved with a
  preset still runs on it), without any UI.

## Tasks

- [x] T1 ModelFavorites store, migration, sync and last-used. Check: unit test.
- [x] T2 Mac popover and composer chip. Check: render + number-key test.
- [x] T3 New sessions start on last used. Check: unit test per kind.
- [x] T4 Remove preset UI elsewhere (Settings, cog, Automations, New Studio preset).
- [x] T5 iPhone favorites. Check: simulator test.
- [ ] T6 Install, service restart, TestFlight.

## Rollback

Favorites and last-used are new preference keys; presets stay saved, so reverting brings
the old pills back unchanged.

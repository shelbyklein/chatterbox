# Draw on desktop images and send feedback

The desktop image reviewer supports numbered areas and notes but has no freehand pen. Add a simple pen so the user can draw directly on an image and send the annotated copy back to the same session. The user clarified "just a pen"; no arrows, shapes or expanded drawing palette.

Tracking: `local:instructions/image-pen.md`. Scope confirmed by the October 20 request and clarification. Reuse dev-plan/dev-work, with no GitHub issue mutations. Mode: linear, because annotation state, canvas/export and the existing send flow are tightly coupled. Executor: current session; exact model/effort unavailable. Readiness: pass, R1–R13 covered below. No blocking questions.

## Evidence and intended view

Current installed reviewer: ![Numbered notes only](../build/verification/image-annotation-before.png).
`ImageReviewView.swift` currently creates `ImageMark` rectangles/points, exports a numbered copy and sends it plus the original. Inline previews and Library already open this reviewer, but their actions do not explicitly say Annotate.

Target sketch, retaining the current viewer and notes panel:

```text
 image canvas                       filename
 ┌──────────────────────────────┐   [ Pen | Numbered notes ]
 │ freehand orange strokes      │   Drag on the image to draw.
 │ over the original image      │   [ Undo ]
 └──────────────────────────────┘   existing notes / overall feedback
                                    [More] [Cancel] [Send to Session]
```

## Outcomes and deliverables

- Pen is the default image-review tool, and drawing stays aligned across fitted image sizes and full-resolution PNG export. Test real drag input, pixel placement and dimensions.
- Undo removes the latest committed annotation; gallery navigation preserves each image's pen strokes and existing area notes. Cancellation and drawing never overwrite the original.
- Send works with pen marks alone, producing the annotated copy plus original and optional feedback for the same chat. Capture the send callback and inspect attachment pixels/bytes in the native fixture.
- Explicit Annotate actions make the reviewer discoverable from transcript image controls and the Library. Inspect the native fixture and installed Mac entry point.

## Tasks and checks

- [x] P1 Add normalized freehand strokes, undo and per-image draft state, with matching export rendering. Extend `scripts/test-image-review-gallery.sh` to use canonical build outputs and exercise real input and send payload.
- [x] P2 Add explicit annotation entry labels/actions; retain existing numbered notes and clipboard/browse behavior. Inspect before/after native screenshots and verify installed image entry.
- [x] P3 Source check, full Mac build, scoped Core/root commit/push, install/reopen under standing approval, tidy report. No service/API or iOS change; no runtime restart or TestFlight build needed.

Test commands: `scripts/test-image-review-gallery.sh`, `scripts/check-sources.sh`, Mac Xcode build through `scripts/ship.sh`. Native verification: open an image in Building Chatterbox, draw with Pen, undo/redraw, inspect without sending a test message to the live agent, cancel. Native fixture verifies sending separately with an owned callback.

Preserve originals, independent annotation copies, existing notes, same-session send routing, gallery browsing and Copy Image. No new permission, schema, provider, service or mobile changes. Rollback: revert scoped commits and reinstall with `scripts/install.sh`; source images stay untouched, newly attached PNGs are ordinary existing attachments. No bulk data migration or backup rewrite is needed.

## Verification

- `scripts/test-image-review-gallery.sh`: pass. Native mouse input checks drawing, Undo, gallery round trip and resized alignment; Send attaches an annotated PNG then the original, checks PNG dimensions and the orange stroke at the expected source pixel, and verifies the source bytes are unchanged. Existing numbered right-edge marks and PNG/TIFF clipboard checks pass.
- Fixture output: `build/verification/image-pen-fixture.png` and `build/verification/image-pen-reply-controls.png`, inspected. AppKit cache rendering omits some native button labels; installed-screen verification below is required for final visual proof.
- `scripts/check-sources.sh`: pass. Full Mac Xcode build: pass, log `build/image-pen-mac-build.log`.
- Final implementation uses ordinary SwiftUI paths for the pen overlay; More sits beside Undo so the Send label fits in the footer. The complete native fixture passes again after these changes (`/tmp/chatterbox-image-review.ZoLtCs`).
- Installed-screen verification: opened Library in Building Chatterbox and the existing `child-context-handoff.png`; Pen starts selected, clicking paints an orange dot, Undo removes it and disables Send again, and Cancel returns to the chat. Moved the automation pointer off the dot to inspect it. Continuous drag and the Send callback are covered by the isolated fixture; no test message was sent to the live agent. Evidence: `build/verification/image-pen-installed.jpg`.
- Delivered and running through `scripts/ship.sh`: root `e15c5da`, Core `9b9fbd6`. Exact installed executable comparison passes. No background-service restart or iOS delivery needed for this desktop-only feature.
- Tidy report: `build/image-pen-tidy.txt`. Reports 83 older leftovers (mostly previous test/mobile folders), left untouched; this task creates no per-run app builds or test processes to retain.

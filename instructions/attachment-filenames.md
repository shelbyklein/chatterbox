# Preserve dropped attachment filenames

Dropped files should retain their original names in the composer and sent message. The current promised-file path always appends an extension to `suggestedName`, and the image importer treats every name as a stem, replacing extensions or duplicating them. This affects desktop drops and named image uploads that share that importer.

## Work preparation

Tracking: `local:instructions/attachment-filenames.md`; local tracking only, no GitHub issue mutations. Scope and immediate implementation follow the user's filename bug report. Mode: linear, because drop routing and image naming share one importer. Executor: current session; exact model/effort unavailable. Readiness: pass, R1–R13 covered here. No blocking questions.

## Intended flow

```mermaid
flowchart LR
    A[Finder URL / promised file / image data] --> B[Keep supplied original filename]
    B --> C[Import while representation URL is valid]
    C --> D[Sanitized storage path + original display name]
    D --> E[Composer attachment and sent message]
```

Keep existing supported image extensions, including JPG and uppercase forms. Add an extension only when missing, and change an image extension only when the stored format changes. If the sender supplies no name, use the representation filename before a generic fallback. No layout change; the observable UI difference is the attachment's filename.

## Outcomes and deliverables

- Finder URLs, promised files and image-data drops retain supplied names without duplicated extensions; verify actual NSItemProvider callbacks in an isolated native test.
- Supported images preserve names and original bytes. Converted images retain the original stem with an extension matching their output format; test bytes, type and dimensions.
- Original files and existing attachments remain untouched. Only newly imported copies change. Ship scoped Core/root commits, native regression tests and this plan, then install/reopen the Mac app under standing approval.

## Tasks and checks

- [x] F1 Consolidate desktop drop import into the existing attachment helper and correct filename handling. Acceptance: `scripts/test-attachment-filenames.sh` exercises URL, file-representation and image-data providers, no-name fallback, JPEG/PNG, conversion and source-byte preservation.
- [ ] F2 Run source check and Mac build; commit/push only owned changes and install through `scripts/ship.sh`. Acceptance: source/build checks pass and the installed executable matches the build.
- [ ] F3 Record results and run `scripts/tidy.sh` in report mode. Acceptance: evidence and delivery status recorded; no unrelated deletion.

Preserve existing resizing limits, MIME types, original-file safety, transcript attachment schema and clipboard behavior. No historical attachment migration, new UI controls or mobile layout changes. The shared importer also serves named mobile uploads, so queue an idle-safe service restart after installation to activate it there; no mobile binary change or TestFlight upload is required. Rollback: revert the scoped commits and reinstall with `scripts/install.sh`; queue an idle-safe service restart. Existing user files are never rewritten, so no data backup/migration is needed.

Tests: `scripts/test-attachment-filenames.sh`, `scripts/check-sources.sh`, and the full Mac build in `scripts/ship.sh`. Behavioral proof is the attachment name, storage bytes and source bytes from real provider callbacks; this change does not alter rendered layout.

## Verification

- Baseline importer compiled from Core HEAD fails the new regression: `Team photo.JPG` becomes `Team photo.jpeg`.
- Updated importer passes real NSItemProvider callbacks for Finder URLs, PDF/Illustrator promised files and PNG image data. Also verifies missing-extension handling, callback-filename fallback, persisted attachment names, dotted stems, sanitized storage with an unchanged display name, native image bytes, resized JPEG dimensions and truthful TIFF conversion extensions. Original source bytes remain unchanged.
- `scripts/check-sources.sh`: pass. No new target source or project regeneration needed.

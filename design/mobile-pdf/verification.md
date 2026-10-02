# Verified PDF review

Mac and iOS device builds succeeded. Tests used private data/host folders, dedicated loopback ports 19647/19648, and disposable simulators; no real chat messages, pairing changes, installations or restarts.

| Check | Evidence |
|---|---|
| Real Mac transport | `scripts/test-companion-pdf.sh`: authenticated 8 MiB PDF matches original bytes; attachment and existing image transfer also match; list endpoint responds during transfer. Unauthenticated, cross-chat, unknown and missing IDs rejected. |
| Portable links | Absolute, angle-bracket and percent-encoded relative PDF links map to document IDs; original transcript stays unchanged. |
| Cache integrity | `scripts/test-pdf-cache.sh`: save/reopen, valid replacement, bad replacement leaves previous valid PDF intact. Private temporary cache. |
| iPhone | `scripts/test-mobile-pdf.sh iphone`: link and tile open; three pages, scroll to page two, pinch gesture, native Files export and Share sheet; progress/cancel, retry, corrupt refresh preservation; relaunch and offline Saved PDFs reopen without a new file request. |
| iPad | `scripts/test-mobile-pdf.sh ipad`: link and tile open; three pages, native Files export; progress/cancel, retry, corrupt refresh preservation; relaunch and offline library reopen. |

Inspected actual simulator captures: [phone viewer](pdf-review-iphone.png), [tablet viewer](pdf-review-ipad.png), [download progress](pdf-download-iphone.png), [Share](pdf-share-iphone.png), [Files export](pdf-export-iphone.png), [offline library](saved-pdfs-iphone.png). Full-screen documents keep native zoom and scrolling.

The first transfer finishes before PDFKit opens the file; this is streaming to disk, not partial-page rendering. Refresh fetches a full new copy rather than byte ranges. Protected PDFs have an unlock prompt, but that prompt has not been manually exercised. PDF annotations are outside this change.

Committed implementation is ready for separate installation approval; both the Mac and mobile app need updating. Nothing pushed or installed for this task.

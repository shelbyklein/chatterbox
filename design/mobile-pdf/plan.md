# Review PDFs on mobile

The phone renders Review PDF links pointing at Mac paths but cannot open them. The companion file endpoint only serves attachments, referenced pictures and animations, and builds full response bodies in memory. Shelby authorized implementing the PDF viewing/downloading proposal.

[Current mobile layout](../mobile-conversation/golem-dark-iphone.png) and [viewer sketch](target.svg). Add chat-specific PDF metadata and portable links; stream downloads to disk with progress and cancellation. Open in a full-screen PDFKit viewer with zoom/pages, Save to Files and Share. Retain downloaded files in a Saved PDFs library reachable offline.

Work preparation: direct implementation request confirms scope and now. Linear GPT-6.1-Sol / medium, this session (verified runtime). Tracker local:8F8E40A4-87F8-4583-A820-06A9F663A282. PD-1 Mac references/transport; PD-2 mobile viewer/cache; PD-3 verification. Readiness R1-R13 pass; no open decisions. No push or installation authorized by this request.

## Outcomes/deliverables
1. Existing Review PDF links and attached/referenced PDFs open on phone and tablet, including spaces/encoded paths; arbitrary paths aren't downloadable.
2. Bounded file transfers avoid complete PDF buffers on either device. Progress, cancellation, missing/corrupt files and interrupted download are handled.
3. Zoom/scroll pages, export/share, and reopen saved copies with the Mac offline. Updated files refresh the cache; previous valid copy survives failed refresh.
4. Scoped code, plan and tests committed; Mac and mobile built; activation pending approval.

## Tasks and checks
PD-1: Resolve PDFs already present in each chat, map to file IDs and rewrite links. Test attachment/reference IDs, negative auth/unknown IDs, identical large-file bytes and continued server responsiveness during transfer.
PD-2: Native PDFKit viewer, disk download/cache and library, export/share URLs. Simulator opens Review PDF and document button; multiple pages, export/share controls, offline re-open, cancellation/retry and bad-PDF handling pass.
PD-3: Run scripts/test-mobile-pdf.sh iphone and ipad against synthetic PDFs on an isolated port; inspect phone/iPad captures. Run scripts/test-companion-pdf.sh for real Mac route/transport. Build Chatterbox and ChatterboxMobile. Install/restart/push gate comes after review.

Preserve chats, agent processes, other worktrees and existing history/draft behavior. No arbitrary filesystem endpoint, annotations, video range support, web PDF proxy, cloud service or installation in scope. Rollback: revert scoped commit; optional File metadata decodes on older clients, and local PDF cache can remain safely. New cache is under mobile Application Support, excluded from backup; it doesn't overwrite user's Files exports or require server data migration.

# Built-in Mac document viewers

Local `.md`, `.markdown`, `.txt`, `.text`, and `.pdf` links open in a window-sized sheet. PDFs use PDFKit continuous pages, text selection, scrolling and native zoom. Markdown supports Read/Source and whole-document Copy. Text and PDF attachment chips use the same routing. Command-click opens the original external app; HTML/SVG retain their browser inspector. Reload, Show in Finder, Copy File Path and Open in App remain available.

Read-only; no original files or chat records change. Text reads run off the main actor, with a 2 MB safety limit; large Markdown opens as plain source. PDFs requiring a password show an unlock prompt. Missing/unreadable documents show an error. Password entry is implemented but not exercised in the synthetic test.

Validation: `scripts/test-mac-documents.sh` checks local extension routing, a percent-escaped relative Markdown path, text loading, missing file/size limits, three-page PDF navigation, and rendered Markdown/PDF content using Vision. Native views rendered in a nonactivating isolated test panel, not the installed app. Screenshots: [Markdown](markdown.png), [PDF](pdf.png). Mac `xcodebuild` passes; pre-existing ContentView Sendable warnings remain. The actual chat-link click, password entry and gesture zoom still need installed-app acceptance.

Activation pending Shelby's approval for a Mac restart. No installation, push or GitHub mutation in this task.

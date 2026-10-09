# Chatterbox website

A single static page: `index.html`, `styles.css` and `script.js`, with fonts, icons and the app icon in `assets/`. No build step.

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8765 --directory website
```

## What's where

- **Story**: software that feels like an extension of you. Talk to your agents in a chat instead of a terminal, and make, open, collect and review their work in the conversation. Studios and Projects keep it organized. The clients, chats and artwork shown are made up.
- **App mockups** (`.ax-*` in `styles.css`) copy the real Mac app: system font, macOS greys, the toolbar groups, sidebar Pins, tag chips and cards, plain-text replies with folded steps and "Worked for", the composer with mode, model line and preset pills, Home, the Image Library and the Open preview chooser. Claude is orange, Codex is green. Match them to the app when its UI changes.
- **The work** shown in the chats (menu boards, labels, posts, the coach page, the poster, handbook pages) is drawn in CSS by `ART` in `script.js`, sized with container units so one design works at any size.
- **Copy** lives in `index.html`. The hero follow-up, the scroll story's window titles, the handoff lines, the Studio instructions and the tone samples are in `script.js`.
- **Brand marks** are inlined in `styles.css` as data URIs so they work from `file://`. The source SVGs are in `assets/marks/`.
- **Icons** are Phosphor (regular and fill), self-hosted in `assets/vendor/phosphor/`. Fonts are Bricolage Grotesque (display), Geist and Geist Mono; the app mockups use the system font.
- Everything animated settles into its final state under `prefers-reduced-motion`.

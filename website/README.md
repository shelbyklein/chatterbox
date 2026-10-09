# Chatterbox website

A single static page: `index.html`, `styles.css` and `script.js`, with fonts, icons and the app icon in `assets/`. No build step.

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8765 --directory website
```

## What's where

- **Copy** lives in `index.html`. The hero story's reply text is the `data-stream` paragraph; the terminal commands and the Claude/Codex handoff lines are in `script.js`.
- **Colours**: Chatterbox orange (`--accent`) is the one accent. Pink, yellow, mint and blue are reserved for confetti, stickers, review avatars and the two gradient moments (the plan cell and the finale).
- **Brand marks** are inlined in `styles.css` as data URIs so they work from `file://`. The source SVGs are in `assets/marks/`.
- **Icons** are Phosphor (regular and fill), self-hosted in `assets/vendor/phosphor/`. Fonts are Geist and Geist Mono.
- Everything animated settles into its final state under `prefers-reduced-motion`.

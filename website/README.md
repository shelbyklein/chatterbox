# Chatterbox website

A single static page: `index.html`, `styles.css` and `script.js`, with fonts, icons and the app icon in `assets/`. No build step.

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8765 --directory website
```

## What's where

- **Story**: software that feels like an extension of you. Studios and Projects are the spotlight; the Studios, chats and clients shown are made up.
- **Copy** lives in `index.html`. The Studio explorer's instructions, design.md excerpts and chats, the hero board's state changes, the handoff lines and the tone samples are in `script.js`.
- **Colours**: Chatterbox orange (`--accent`) is the brand accent. Orange, blue, pink and mint mark which Studio something belongs to, and yellow always means an agent is waiting on you.
- **Brand marks** are inlined in `styles.css` as data URIs so they work from `file://`. The source SVGs are in `assets/marks/`.
- **Icons** are Phosphor (regular and fill), self-hosted in `assets/vendor/phosphor/`. Fonts are Bricolage Grotesque (display), Geist and Geist Mono.
- Everything animated settles into its final state under `prefers-reduced-motion`.

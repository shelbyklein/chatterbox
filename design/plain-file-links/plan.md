# Clickable standalone file paths

A bold HTML path in a reply renders as plain text even though the file exists. MarkdownText.inline currently auto-links only code spans. Extend the existing disk-verified path lookup to standalone plain/bold runs while preserving explicit links and code styling.

Evidence: [user screenshot](/Users/shelbyklein/Library%20Application%20Support/Chatterbox/Attachments/FAF300B5-0EA1-4C55-A254-BBD053864C73/CleanShot%202026-10-06%20at%209.27.23%20AM.png). Referenced HTML existence verified. [Target](target.svg). HTML click uses existing ChatView openURL preview chooser; Command-click remains external.

- [x] L1 Extend link creation and verify bare/bold/code paths, spaces, missing files and explicit web links using native renderer fixture.
- [x] L2 Inspect resulting linked HTML render and build/install with card fix.

Success: existing standalone plain/bold HTML paths have path links; missing paths remain text; existing links and code styles survive. Actual preview routing unchanged. Deliverables: local source/tests/evidence and installed Mac app; no GitHub changes. Excludes detecting arbitrary prose paths, fenced code, mobile remote file transport, and any site edits.

Work preparation: user authorized fix by “I should be able to open this from a click”; linear, runtime gpt-6.1-sol medium. Readiness pass R1–R13; no blocking decisions. Test: scripts/test-card-attention.sh with native MarkdownText fixture checks. Rollback: previous installed app bundle copied before install. No service restart.

## Results
Native rendering and state/link checks pass. Mac build passes; app installed and executable byte-matches tested build. App PID 37959; daemon PID 60096 stayed running (no restart). Local source remains uncommitted and unpushed; GitHub unchanged. Live click/answer interaction not automated; native shared view renders inspected. Rollback bundle: /tmp/chatterbox-card-rollback.RoT52c/Chatterbox.app.
[Verified after render](after.png)

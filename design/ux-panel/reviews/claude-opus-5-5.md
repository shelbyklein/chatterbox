```json
{"judge": "claude-opus-5-5", "scores": {"C1": 6, "C2": 6, "C3": 5, "C4": 6, "C5": 6, "C6": 7, "C7": 6, "C8": 5}, "overall": 6}
```

## Verdict

Chatterbox has the right ideas for supervising many agents: a Desk that leads with "what needs you", inline approve/deny, a place-first start flow that explains what will happen, and a well-rendered transcript with honest step and failure states. Execution is where it falls down. The same job looks and reads differently on every surface. Approving is "Approve/Deny" in blue/red on the iPhone Desk, "Allow / Allow for This Session / Deny" in orange in the iPhone session, equal-weight grey buttons on the Mac Desk, and small grey chips in the Mac session. The Mac has two navigation models (a Home sidebar and an icon-only toolbar plus a ten-button icon rail). Model, effort and permission names change between screens. The status vocabulary leans on colored dots and agent-colored spinners that an expert has to learn, and the phone Desk is too low-density to triage more than two items without scrolling. It works and it's often pleasant, but it doesn't yet give the "act with confidence at a glance" feeling the job needs.

## Strengths

1. **Place-first start flow** (03-iphone-desk-start-there.png, 20-mac-desk-start-there.png, 04-iphone-desk-change-place.png). The request, the suggested place with a reason ("Camp graphics belong to USA Archery."), the existing sessions with their state ("Working now; it goes next"), and a footer saying exactly where the message goes and on which model. Choose a Place gives each place a one-line description. This is the clearest, most trustworthy flow in the app.
2. **Transcript legibility** (09-iphone-conversation-steps.png, 22-mac-conversation.png). Folded Thought, one-line tool rows with done/failed icons that differ in shape as well as color, a plan checklist, collapsible "3 steps · 12m 34s" groups on Mac, and "Worked for 12m 34s" give a quick read of what the agent did without drowning you in it.
3. **Desk as front door, with sensible wide layouts** (01-iphone-desk.png, 17-ipad-desk-two-columns.png, 19-mac-desk.png). A summary line ("2 need you · 2 incoming · 2 working"), sections that hide when empty, a calm empty state (05) and the two-column iPad/Mac grid put triage first. The Mac Desk's compact cards show the place chip and the actual command (`npm run proof && …`).

## Issues

1. **High. Approvals are inconsistent and the phone Desk hides the command** (01, 11, 19, 23). The iPhone Desk asks you to Approve "Run wrangler deploy…?" without showing `wrangler deploy --env production`, which the session card (11) and Mac Desk (19) do show. Wording (Approve vs Allow), button set (no "Allow for This Session" on the Desk), color (blue/red, orange, neutral grey) and emphasis all change by surface. Approving a production deploy from a phone without seeing the command undermines confidence.
2. **High. Two Mac navigation models with unlabeled icons** (19, 21 vs 22, 23, 24, 25). Home uses a sidebar (Activity, Desk, Studios, Pinned). The main window uses a five-icon toolbar segment, seven more unlabeled toolbar icons and a ten-button right rail. Where Desk, Pinned and Command Center live isn't discoverable, and it doesn't match the phone's five labeled tabs.
3. **High. Status is coded by color alone, and color also means agent identity** (06, 07, 15, 22). Spinner color is orange for Claude and green for Codex, so the same hue encodes "who" and "working". Dots are blue for new, yellow for needs you and grey for idle. SDHQ's last line turns yellow. Tracker Trapper has a question on the Desk but shows only a blue "new" dot in Activity. You have to learn a legend to triage.
4. **Medium. Phone Desk density is too low for triage** (01, 16). Two Needs-you cards fill the screen. Incoming starts below the fold, and its Start There / Change Place / Ignore buttons sit under the floating tab bar. With 8 to 10 items this becomes a long scroll.
5. **Medium. Model, effort and permission naming drifts** (08, 10, 13, 20, 24, 25, 27). The model is "Claude · Opus" in the header and "Opus 5.5 · Most capable" in the picker, while Settings calls Fable "Most capable" and Opus "Best for everyday". Effort is "X-High" on the phone and "Extra High" on the Mac, plus a "Default" option. Permissions are "Manual / Bypass permissions / Full access". Session-chip formats vary ("Opus (default) · Default effort").
6. **Medium. The dangerous permission is the loudest control** (13). In New Chat, the selected Bypass option is a big orange tile labelled only with icons until the caption below. The safe Manual option has no text label at all.
7. **Medium. Connection error leaves stale "live" status** (15). The banner is clear, but Activity still spins "3 working · 1 new" from cached data, and there's no Retry button or "last updated" time. You can't tell what's true.
8. **Medium. Selection and needs-you treatments on Mac sidebar cards** (22, 28). The selected card is solid white in dark mode, which glares, and in light mode it disappears against the white background. The needs-you card is a muddy olive fill. Two-column cards truncate summaries to two lines, a poor fit for scanning many sessions.
9. **Low. Light-mode and secondary-text contrast** (16, 19, 21, 26). Yellow "Permission needed" on white, pale yellow card borders, dim grey metadata ("From Claude · 25m", "now"), and a dimmed Run Now that reads as disabled.
10. **Low. Gaps and dead space** (14, 22, 23, 05). The Automations sheet has no visible Add button and no failed-run state. The Mac conversation has a large empty band above the first message (flagged as a possible harness artifact). On iPhone and iPad, the empty Desk leaves most of the screen blank with no recent results.

## Suggestions

1. **Use one approval component everywhere** (fixes 1). Header: place › session. Then the plain-language ask, then the exact command in monospace (always shown, truncated in the middle, tap to expand). Buttons: filled primary "Allow", secondary "Allow for session", destructive-tinted "Deny". Same labels, order and colors on the Desk and in the session, on all platforms. Impact high, effort medium.
2. **Give the Mac one labeled navigation spine** (fixes 2). A source-list sidebar with Desk, Pinned, Projects, Studios, Chats and Command Center, plus badges, matching the phone tabs. Move the right-rail tools into a labeled inspector or an overflow menu with hover labels. Impact high, effort large.
3. **Separate status from identity** (fixes 3). Keep the agent mark as a small fixed glyph. Show status as one shape-coded badge in a fixed spot: hand for needs you, ring spinner for working, filled dot for new, exclamation for failed. Use one status palette regardless of agent. Impact high, effort medium.
4. **Add a compact Desk density on iPhone** (fixes 4). One- or two-line rows (session, kind icon, ask), with inline Allow/Deny on approvals and swipe actions for the rest. Expand a row on tap. Keep content clear of the tab bar's inset. Impact high, effort medium.
5. **Write a naming glossary and apply it** (fixes 5). Always show the full model name ("Opus 5.5"), one effort scale ("Extra high"), and one permissions pair ("Ask first / Allow all"). Use one chip format: "Opus 5.5 · Medium". Impact medium, effort small.
6. **Make New Chat permissions a labeled segmented control** (fixes 6): "Ask first" (default) and "Allow all". Selecting Allow all shows a one-line warning, and the orange tint marks risk rather than selection. Impact medium, effort small.
7. **Make offline state honest** (fixes 7). Swap spinners for grey "last seen 9:12" labels, add a Retry button in the banner, and dim Activity counts. Impact medium, effort small.
8. **Restyle the Mac session list** (fixes 8). Make list mode the default, with single-column rows: title, one-line summary, status badge. Use the accent-tinted system selection in both modes, and show needs-you as a badge plus a left accent bar instead of a full fill. Impact medium, effort medium.
9. **Run a contrast pass** (fixes 9). Use darker amber for light-mode warning text and borders, raise secondary text to at least 4.5:1, and show enabled Run Now at full strength. Impact medium, effort small.
10. **Fill the gaps** (fixes 10). Add "+" to Automations, show a red "Last run failed" row linking to the run, and give the empty Desk a "Recently finished" list. Impact medium, effort medium.

## Quick wins

1. Show the command on the iPhone Desk approval card and rename its buttons "Allow / Deny" to match the session (01, 11).
2. Label the Manual permissions tile in New Chat and stop showing Bypass as the eye-catching default (13).
3. Unify "X-High" and "Extra High", and resolve which model is "Most capable" (10, 27).
4. Add Retry and "Last updated" to the "Can't reach" banner and freeze the spinners (15).
5. Add tooltips or labels to the Mac toolbar and rail icons, and fix the selected-card color in light mode (22, 28).

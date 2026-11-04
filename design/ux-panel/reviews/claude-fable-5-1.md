```json
{"judge": "claude-fable-5-1", "scores": {"C1": 6, "C2": 7, "C3": 5, "C4": 7, "C5": 7, "C6": 6, "C7": 7, "C8": 6}, "overall": 6}
```

## Verdict

Chatterbox has the right spine for its job: the Desk puts approvals and questions first with inline actions, sessions render agent work (tool rows, plan, failed and passing runs, elapsed time) more legibly than most agent clients, and the phone is a genuinely usable remote with a calm offline state. What holds it back is coherence rather than concept. The phone and Mac speak different dialects (Approve/Deny vs Allow/Deny, blue vs orange, yellow vs orange for "needs you", filled vs flat buttons), the Mac navigation hides Projects and a dozen tools behind unlabeled icons, badge counts don't match the summary line, and the Mac conversation window is visibly less finished than the phone. A strong 6: good bones, inconsistent skin.

## Strengths

1. **Triage-first Desk with inline decisions** (01-iphone-desk.png, 19-mac-desk.png). Summary line, Needs you above everything, Approve/Deny on the card, swipe to Silence (02). This is the correct shape for "what needs me" from a phone.
2. **Agent work is readable** (09-iphone-conversation-steps.png, 22-mac-conversation.png). One-line tool rows with done/failed glyphs, a plan checklist with strikethrough, the failed run followed by the fix and the passing run, "Worked for 12m 34s", and the composer that queues while the agent works. Expert density without noise.
3. **Start There sheet** (03-iphone-desk-start-there.png, 20-mac-desk-start-there.png). Request, place with Change, "Continue in X / Working now; it goes next", New session with model only when relevant, and a footer saying exactly what will happen. Few sheets explain a side effect this well.

## Issues

1. **High. Same approval, different words and different information** (01, 11, 17, 19, 23). On the Desk it is "Approve / Deny"; in the session it is "Allow / Allow for This Session / Deny". The iPhone Desk card hides the command entirely (`wrangler deploy --env production` is only visible in 11 and on the Mac Desk 19). A user approving a production deploy from the phone is approving a sentence, not a command, and loses the "for this session" option. For a supervisor this is the one decision that must be exact.
2. **High. Mac navigation model diverges from the phone** (19, 21, 22, 24, 25). The phone has five named tabs. The Mac has a sidebar whose contents change per page (Activity + Desk + Studios in 19; Activity + Projects cards in 22; Studios + a Studio tree in 24), a toolbar segmented control of five unlabeled icons (folder, palette, bubble, grid, inbox), and a separate Command Center. Where "Projects" lives on the Mac is not discoverable from any screenshot, and the inbox icon with a badge duplicates the Desk.
3. **Medium. Badge arithmetic doesn't match the summary** (01, 05, 19). Desk badge says 4 while the heading says "2 need you"; Mac says 7 against "4 need you · 3 incoming". Incoming requests are not things that need the user in the same sense as an approval, and the empty Desk (05) still shows Pinned 1 and Projects 1 with no hint what those count. Badges that overstate urgency get ignored.
4. **Medium. No visual primary action on the Mac** (19, 20, 23). Approve, Deny, Start there, Change place, Allow, Deny are all the same flat grey pill; the phone correctly fills Approve blue and colors Deny red. On a page built for fast decisions, the eye has nothing to land on, and a mis-click on Deny vs Approve is easy.
5. **Medium. Two meanings for one highlight** (21, 22). In the Studio list, Event Logos has an orange outline (needs you) while the inspector shows National Event Ribbons (selected, grey). In the Projects sidebar, SDHQ is orange-tinted (needs you) and Galley is a white card (selected). Selected vs needs-attention must never look alike on a list meant for switching sessions.
6. **Medium. Status glyphs collide** (06, 07, 15). The orange Claude mark and the orange working spinner are near-identical at list size; Galley shows the mark at left and a grey spinner at right, SDHQ shows a yellow dot plus yellow text, Tracker Trapper shows a blue dot. Four encodings for three states, all by color.
7. **Medium. Questions can't be answered where they're asked** (01, 17, 19). "Ring or bar?" needs Open and a session visit; "Which of the two marks?" the same. The Desk promises to be where you act, but only approvals are actionable on it.
8. **Medium. Icon-only tool rail and toolbar on Mac** (22, 23, 24, 28). Nine unlabeled rail buttons plus five unlabeled toolbar icons. Hover tooltips are not a substitute for an expert's muscle memory being built in the first week, and screen-reader users get nothing.
9. **Low-medium. Light mode loses the needs-you cue** (16, 28). The pale-yellow card border on white is barely visible; the SDHQ card tint in 28 reads as "warning" rather than "selected or needs you".
10. **Low. Duplicate and drifting labels** (10, 13, 19, 21). "Effort" header above an "Effort" row, "Start in" above "Start in"; "Needs you" / "Asked you" / "Question" / "Questions" / "Permission needed" / "Approval" for two states; "Silence" on the phone vs the bell-slash with no label on Mac; "Ignore" on Incoming sits next to "Silence" with no explanation of the difference.

Gaps: no Chats or Pinned tab screen, no Mac Activity view, no "Choose a Session" or loading state, no Mac automations list, no phone settings or Mac-pairing flow.

## Suggestions

1. **One approval card everywhere.** Title (session · place), the question, the command in a mono block, then Allow / Allow for session / Deny in that order with Allow filled. Use it on the iPhone Desk, iPad Desk, Mac Desk and docked in the session. Fixes issue 1 and half of 4. Impact high, effort small.
2. **Give the Mac the phone's named sections.** A fixed sidebar with Desk, Pinned, Projects, Studios, Chats (badged), then the current place's sessions under it; drop the icon segmented control from the toolbar. Fixes 2. Impact high, effort medium.
3. **Define a primary button style on Mac** (accent-filled) and apply it to Approve, Start there, Allow, Start, Continue; keep Deny as a red-text secondary. Fixes 4. Impact high, effort small.
4. **Separate selection from attention.** Selection: subtle filled background in the window tint, no border. Needs you: a left-edge 3 pt bar or a colored leading dot, never a full-card tint. Apply to 21, 22, 24. Fixes 5. Impact medium, effort small.
5. **One status glyph set, with the agent mark as a static avatar.** Agent mark in a neutral circle; state shown by a single trailing element: spinner (working), yellow hand or question bubble (needs you), blue dot (new reply), nothing (idle). Fixes 6, helps 8. Impact medium, effort medium.
6. **Badge = needs you only; show incoming as a second count in the summary line.** Pinned and Projects badges should count unread replies and say so in the tab's long-press menu. Fixes 3. Impact medium, effort small.
7. **Inline answers for short questions.** When the agent offers two or three options, render them as chips on the Desk card (Ring / Bar / Open). Free-text questions keep Open. Fixes 7. Impact medium, effort medium.
8. **Label the Mac rail.** Collapse nine buttons into four labeled groups (Files, Tools, Images, Layout) or show text labels under icons at the window's default width. Fixes 8. Impact medium, effort medium.
9. **Strengthen light-mode attention cues:** a 2 pt amber border plus the leading bar from suggestion 4, tested against white. Fixes 9. Impact low, effort small.
10. **Unify the vocabulary:** "Permission" and "Question" as the two kinds; "Silence" on both platforms with a label; a one-line footnote on Incoming explaining Ignore. Fixes 10. Impact low, effort small.

## Quick wins

1. Put the command block on the iPhone/iPad Desk approval card (01, 17).
2. Fill Approve and Start there on the Mac Desk; same blue as the phone (19).
3. Remove the duplicated "Effort" and "Start in" labels (10, 13).
4. Add a text label to the Mac bell-slash and open-session icons, and to the Permissions segmented buttons in New Chat (13, 19).
5. Make Desk badges count only Needs you (01, 05, 19).

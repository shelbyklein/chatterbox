# UX/UI review brief

You are a senior UX/UI designer (10+ years, shipped native iOS, iPadOS and macOS products, led
design reviews). You are one judge on an independent panel. Judge only the product in front of
you; you have no stake in it and don't know who made it. Be candid and specific: a score that
flatters helps nobody.

## The product

Read `screens/INDEX.md` first: what the app is for, and one line per screenshot naming the screen,
its state, and any interaction a picture can't show. Then look at every screenshot in `screens/`.

The screenshots come from the app's test harness with made-up data. Don't judge the sample
content itself (names, text, test strings), only how the interface presents it. Don't guess at
screens you weren't shown; if something important seems missing, say so as a gap.

The users are one or a few expert users who run and supervise many AI agent sessions at once,
from a Mac and from an iPhone/iPad away from the desk. Judge it for that job: fast triage, knowing
what's happening, acting with confidence, and not losing track of work.

## Criteria (score each 1–10; the weights give the overall score)

| # | Criterion | Weight | What to look at |
|---|---|---|---|
| C1 | Information architecture and navigation | 15% | Is it clear where things live (Desk, sessions, Studios/projects, automations, settings) and how to get between them? Same mental model on Mac and phone? |
| C2 | Visual hierarchy and layout | 15% | Does the eye land on what matters first? Density right for an expert? Use of space on phone, iPad/wide and Mac. |
| C3 | Consistency and platform conventions | 15% | Consistent components, patterns and wording across screens and platforms; follows Apple's Human Interface Guidelines where it should, departs from them only for a reason. |
| C4 | Workflow efficiency | 15% | Taps/clicks and decisions for the core jobs: triage what needs you, approve or answer, start work in the right place, switch sessions, change model. Friction, dead ends, hidden actions. |
| C5 | Status, feedback and error handling | 10% | Can you tell what's running, waiting, done or failed at a glance? Are errors, empty and loading states clear, calm and actionable? |
| C6 | Visual craft | 10% | Typography, color, spacing, alignment, iconography, dark-mode quality, polish. |
| C7 | Content and microcopy | 10% | Labels, button text, explanations: plain, short, consistent, helpful. |
| C8 | Accessibility | 10% | Contrast, touch target size, reliance on color alone, text size and Dynamic Type readiness, clear labels. |

Score anchors (use the whole range):
1–2 broken or unusable · 3–4 poor, gets in the way often · 5 works but rough · 6 decent, clear
problems · 7 good, on par with solid shipping apps · 8 very good, few issues · 9 excellent, among
the best in its category · 10 reference-quality, nothing meaningful to fix.

## What to return

1. A fenced ```json block, exactly this shape (integers 1–10):
   `{"judge": "<your model name>", "scores": {"C1": n, "C2": n, "C3": n, "C4": n, "C5": n, "C6": n, "C7": n, "C8": n}, "overall": n}`
   `overall` is your own holistic 1–10, not necessarily the weighted average.
2. **One-paragraph verdict.**
3. **Strengths**: the 3 strongest things, each tied to a screenshot filename.
4. **Issues**: up to 10, most severe first. For each: severity (high / medium / low), the screenshot
   filename(s), what's wrong, and why it matters for this user.
5. **Suggestions**: up to 10 concrete changes, highest impact first. For each: what to change (specific
   enough for a designer to draw it), which issue it fixes, expected impact (high/medium/low) and effort
   (small/medium/large).
6. **Quick wins**: up to 5 changes that are small effort and noticeably better.

Keep it under 1,500 words.

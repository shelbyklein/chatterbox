# Desk confidence: can this run without Shelby? Yes/No, and Yes starts by itself

## Summary

Every task brought onto the Desk is scored against a rubric: can an agent finish it without
Shelby? Yes or No, with a one-line reason on the card. Yes tasks start automatically in their
proposed place; No tasks wait in To do. Shelby, 2026-11-06.

## Rubric (final, Shelby 2026-11-06)

**No** if any of these holds:
1. Creative judgment: needs Shelby's taste or direction (picking between designs, deciding a
   look, writing in Shelby's voice for something that matters).
2. Missing info or access: something needed isn't in the task, its note, its source (ClickUp
   task, email) or its Studio/project folder: a file, a detail, a login, a decision.
3. Outward-facing: finishing it means sending email, publishing, pushing live, changing ClickUp,
   or anything others see.
4. Approvals mid-work: it would hit permission prompts (installs, deleting files, working outside
   its folder, spending money).
5. No clear place: the Desk can't confidently say which Studio or project it goes in.

**Yes** otherwise: a clear deliverable, everything it needs at hand, staying inside Chatterbox and
its folder. The reason names the blocking rule (No) or why it's safe (Yes).

## Who scores

The agent adding the task (`desk add --confidence yes|no --reason "…"`). Tasks added without a
score (typed by Shelby, or an agent that didn't score) get a quick pass by a small model (Claude
Haiku, as Next Steps uses) against the same rubric.

## Auto-start and its guards

- Only Yes with a reason and a proposed place starts; a source that disagrees with the board
  (DeskOriginCheck) holds it.
- At most 2 auto-started tasks work at once; the rest start as those finish.
- New sessions already wait while the Mac is under pressure (sendFirstOrHold).
- The first message says it started automatically and to stop and ask at anything the rubric
  names (the agents' standing instructions already forbid sending or publishing unasked).
- Settings → Background service: "Start Desk tasks that can run without you" (on by default);
  off keeps the scores.
- Cards of auto-started tasks say "Started automatically".

## Tasks

- [x] C1 Service: confidence on tasks, add flags, quick scoring pass, auto-start with guards,
      setting; tests.
- [x] C2 Cards (Mac + phone): Yes/No line with reason; "Started automatically"; screenshots.
- [x] C3 Agent instructions and `desk` CLI: score when adding.

## Not changed

Starting by hand, the board's columns, the source warnings.

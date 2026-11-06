# Desk confidence: can this run without Shelby? Yes/No, and Yes starts by itself

## Summary

Every task brought onto the Desk is scored against a rubric: can an agent prepare it for review without
Shelby? Yes or No, with a one-line reason on the card. Yes tasks start automatically in their
proposed place; No tasks wait in To do. Shelby, 2026-11-06.

## Rubric (final, Shelby 2026-11-06)

Confidence scores whether an agent can prepare a useful, reviewable deliverable without Shelby.
Final outbound approval is a separate gate (Shelby's correction, November 6, 2026).

**No** when preparation is blocked by:
1. A substantive creative decision or direction needed before useful preparation can proceed.
2. Missing source information, files, access, or other required inputs.
3. An outbound-only task with no useful preparatory deliverable.
4. Permission needed before preparation can proceed, such as a required install, deletion or purchase.
5. No clear Studio or project.

**Yes** when the task, source inputs and place are clear and an agent can prepare a reviewable
result. Final approval to send, publish, follow up or change ClickUp does not lower confidence.
For example, prepare a specified website correction from supplied copy = Yes, even when Shelby
must approve publication; missing replacement copy or a needed creative direction = No.
High confidence never authorizes the outbound action. Prepare the work, then request approval
before executing that action. Ordinary final review is not a missing creative decision.

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

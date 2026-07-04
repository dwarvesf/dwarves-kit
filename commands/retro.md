---
description: "Run a retrospective after shipping. Captures what worked, what didn't, and action items for the next cycle. Outputs to docs/retro/RETRO.md."
---

You are a retrospective facilitator. The team just shipped something. Your job is to extract learnings before context is lost.

This is NOT a celebration. This is NOT a blame session. This is a structured extraction of signal.

## When to run

- After `/kit:ship` completes
- At the end of a sprint or milestone
- After a significant bug or incident
- Periodically (weekly or biweekly) for ongoing projects

## Process

### Step 1: Gather data

Collect facts before opinions:

```bash
# Recent commits
git log --oneline --since="1 week ago"

# Files changed
git diff --stat main

# Spec completion
cat docs/specs/SPEC-NNN-<slug>.md  # check task completion rate
```

Present a summary:
- Tasks planned vs completed
- Files added/changed/deleted
- Commits count and pattern (are they atomic or messy?)
- Time span (when did work start vs ship)

### Step 1b: Doc-impact + completeness sweep

Run the pinned diff (the integration branch's merge-base) against the WORKFLOW doc-impact map and list any companion doc the diff should have updated but did not. Also read `~/.claude/dwarves-kit/logs/completeness.log` and surface un-cleared decision/doc warnings from this cycle. Report the gaps as retro signal, not a block; a recurring gap is a candidate to promote the clause to a hook (PHILOSOPHY section 5 bar). Source: SPEC-006.

### Step 1c: Decision-capture nudge (advisory)

Ask once: **did this cycle make a non-obvious, reversible-with-cost decision that is NOT already recorded in a SPEC Decision Log or an existing ADR?** Examples: a storage shape, a library choice, an error contract, an architectural boundary, a deliberate scope cut. A decision already in a spec's `## Decision Log` or an existing `docs/decisions/NNNN-*.md` does not need a second home; this is only for the ones that fell through.

If yes, suggest drafting `docs/decisions/NNNN-<slug>.md` (next number after the highest existing; match the style of the existing ADRs in `docs/decisions/`, there is no separate template file) capturing: context, the decision, why, and the rejected alternatives in one or two lines each.

This is **advisory, never a block** (PHILOSOPHY "Detect, don't dictate": the kit reports completeness as retro signal, never a mid-flight gate). If the operator declines, log one line to `~/.claude/dwarves-kit/logs/completeness.log` (`decision-capture: declined <cycle/slug>`) so a recurring skip is visible as retro signal, exactly like Step 1b. Source: SPEC-051 (absorbed from repository-harness's decision-capture flow, A4-lite).

### Step 1d: Lane telemetry sweep (SPEC-061)

Run `bash lib/lane-telemetry.sh report` and `bash lib/lane-telemetry.sh misfires`. Surface
the aggregates (per-lane runs, misroute count, gate skip/override counts, ship rate, untracked
runs) as retro signal. **Disposition contract:** every misfire line MUST leave the retro as one
of (a) a classifier keyword fix + truth-table pin (the SPEC-057/SPEC-060 pattern: a real
misfire becomes a test row), (b) a kit BACKLOG row, or (c) one recorded "accepted noise:
<reason>" line in the retro doc. A misfire that leaves as nothing is the open-circuit this
step exists to close.

### Step 2: Three questions

Ask each question one at a time. Wait for the user's answer before moving on.

**Q1: What worked?**
Not "what did you build" but "what process, tool, or decision made this smoother than it could have been?" Be specific. "Claude Code was helpful" is not useful. "The spec prevented 3 misunderstandings with the contractor" is useful.

**Q2: What hurt?**
Where did you lose time? What surprised you? What was harder than expected? Common answers:
- Spec was too vague on [specific area]
- Claude hallucinated [specific API/pattern]
- Context window filled up during [specific task]
- Review caught issues that should have been in the spec
- Missing test for [specific edge case] caused a regression

**Q3: What will you change next time?**
One concrete action item per pain point. Not "be better at testing." Instead: "add integration test requirement to spec template for API endpoints."

### Step 3: Generate retro document

Write to `docs/retro/RETRO-[date].md`:

```markdown
# Retro: [feature/milestone name]
Date: [date]
Sprint: [date range]

## Metrics
- Tasks planned: [N], completed: [N], deferred: [N]
- Commits: [N]
- Files changed: [N]
- Key commits: [list notable ones]

## What worked
- [item with specific evidence]

## What hurt
- [item with specific impact]

## Action items
- [ ] [concrete change] -- owner: [person] -- deadline: [date]
- [ ] [concrete change] -- owner: [person] -- deadline: [date]

## Kit feedback
[note any dwarves-kit friction: hooks that false-positived, commands that were awkward, missing workflows]
```

### Step 4: Update kit if needed

If action items relate to the kit itself (e.g., "anti-rationalization hook was too aggressive", "spec template needs a testing section"), suggest specific changes.

If learnings are reusable knowledge, remind the user they can capture them:
- For coding patterns: update CLAUDE.md
- For API gotchas: `chub annotate [api] "[learning]"`
- For general knowledge: use the knowledge-capture skill to push to GitHub

### Step 5: Feed forward

Check if any action items should become:
- New tasks in the next spec
- Updates to the CLAUDE.md quality rules
- New entries in docs/decisions/
- Adjustments to hook configuration

Ask: "Any of these action items worth adding to the project CLAUDE.md or kit config?"

After the retro document is written, record it for lane telemetry (SPEC-139), one line
(the matrix row this command owns is `Reflect`, not `retro`):
`bash lib/gate-ledger.sh record <rid> Reflect ran "action-items=<N>"`.

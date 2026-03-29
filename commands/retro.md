---
description: "Run a retrospective after shipping. Captures what worked, what didn't, and action items for the next cycle. Outputs to .planning/RETRO.md."
---

You are a retrospective facilitator. The team just shipped something. Your job is to extract learnings before context is lost.

This is NOT a celebration. This is NOT a blame session. This is a structured extraction of signal.

## When to run

- After `/user:ship` completes
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
cat .planning/SPEC.md  # check task completion rate
```

Present a summary:
- Tasks planned vs completed
- Files added/changed/deleted
- Commits count and pattern (are they atomic or messy?)
- Time span (when did work start vs ship)

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

Write to `.planning/RETRO-[date].md`:

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
- New entries in docs/decisions.md
- Adjustments to hook configuration

Ask: "Any of these action items worth adding to the project CLAUDE.md or kit config?"

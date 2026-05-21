---
description: "Parallel multi-lens critique of a solution design (the active spec if present, else the decision brief). Dispatches 5 engineering lenses, merges findings, reports a verdict. Report-only, never blocks."
---

You are a design-critique coordinator. Your job is to stress-test a solution DESIGN from 5 engineering angles in parallel, merge the findings, and report a verdict. This mirrors `/user:review-team` (which critiques code) one altitude up: it critiques the design before the spec hardens. It is an opt-in lane, report-only; it never blocks `/user:spec`.

## Process

### Step 1: Find the design to critique

Read the design's `## Solution`, **spec-first**:

1. The active `docs/specs/SPEC-NNN-<slug>.md`'s `## Solution` section IF a spec exists. Resolve the active spec the way `/user:next` does (branch-aware, SPEC-005); if several specs match, ask the user which one, do not auto-pick.
2. ELSE `docs/specs/DECISION-BRIEF.md`'s `## Solution` section (the pre-spec window, before a `SPEC-NNN` exists).

The spec is the carrier once it exists; the brief is the home only pre-spec (before `/user:spec`). If neither has a `## Solution` (no active spec with one, AND the brief is absent or has no `## Solution`), say so, suggest the user run `/user:design` or `/user:spec` first, and stop. Do not invent a design to critique.

Note which doc holds the design; you will write the critique back to that same doc.

### Step 2: Dispatch 5 lenses in parallel

Dispatch these 5 subagents via the Task tool in a single batch. They run simultaneously since they are all read-only and modify nothing. Pass each lens the design's `## Solution` text and the relevant problem context.

Each lens returns 2-5 findings (each with a severity CRITICAL / HIGH / MEDIUM / LOW and a concrete fix) plus a 0-10 score for the design under that lens.

1. **Simplicity** -- is this the least-machinery solution that solves the problem? Flag speculative features, premature abstraction, accidental complexity.
2. **Performance** -- where does this design get slow or expensive at scale? Hot paths, N+1 patterns, unbounded growth, wasted work.
3. **Boundaries / composability** -- are the units cleanly separated (one purpose, a defined interface, testable independently)? Flag leaky boundaries and tight coupling.
4. **Data-model & correctness** -- is the data model sound? Flag invariants that can break, ambiguous states, race conditions, lost updates.
5. **Operability / failure-modes** -- what happens when a dependency fails, times out, or returns garbage? Flag missing failure handling, silent failures, hard-to-debug paths.

### Step 3: Merge findings

After the lenses complete:

1. Collect all findings from every lens that returned.
2. On partial lens failure (a subagent errors or times out), merge from the lenses that DID return and note which lenses are missing. Never block on a partial failure.
3. Deduplicate (same concern caught by multiple lenses = one finding; note which lenses caught it).
4. Sort by severity (CRITICAL > HIGH > MEDIUM > LOW).
5. Compute a combined verdict from the merged findings and the lens scores.

### Step 4: Write the critique back to the design doc

Append a `## Design critique` section to whichever doc holds the design (the active spec if present, else the pre-spec brief, the same doc you read in Step 1). One critique section per doc: if a `## Design critique` already exists, REPLACE it; do not stack duplicates.

```markdown
## Design critique
Date: [date]
Design source: [DECISION-BRIEF.md ## Solution | SPEC-NNN ## Solution]
Lenses run: [list]; missing: [list, or "none"]

### Critical findings
1. [finding] -- found by: [lens(es)] -- fix: [concrete fix]

### High findings
1. ...

### Medium findings
1. ...

### Low findings
1. ...

### Scores
- Simplicity: [X]/10
- Performance: [X]/10
- Boundaries/composability: [X]/10
- Data-model & correctness: [X]/10
- Operability/failure-modes: [X]/10

### Verdict: SOLID / REVISE / RECONSIDER
```

### Step 5: Report, do not block

Present the merged critique to the user. The verdict is report-only:

- SOLID: the design holds; suggest proceeding to `/user:spec`.
- REVISE: list the specific findings to address; the maintainer revises `/user:design` or the spec, or proceeds anyway.
- RECONSIDER: explain what is fundamentally wrong with the design.

Never block `/user:spec`. The maintainer decides whether to revise or proceed.

Under bypassPermissions the per-section `AskUserQuestion` approvals auto-resolve; if you detect that, say so plainly. This lane delivers its full value in interactive (non-bypass) mode.

## Source
Mirrors the parallel multi-lens pattern in `commands/review-team.md` + `agents/reviewer.md`, one altitude up (design, not code). Lenses adapted from `zvadaadam/az-skills` `engineering/devs-roundtable`, recast as generic house-style lenses (no named-person personas). Verdict vocabulary `SOLID / REVISE / RECONSIDER` is shared with `/user:visual-team` (same altitude). Realizes SPEC-016 Part A.

---
description: "Parallel code review with 3 specialist lenses. Dispatches security, architecture, and test-coverage reviewers simultaneously, then merges findings."
---

You are a review coordinator. Your job is to dispatch 3 focused reviewers in parallel, collect their findings, deduplicate, and present a unified report.

## Prerequisites

1. There are code changes to review (git diff is not empty)
2. Optionally, `docs/specs/SPEC-NNN-<slug>.md` exists for spec-compliance checking

If no changes exist, tell the user and stop.

## Process

### Step 1: Gather the diff

Run `git diff main` (or `git diff HEAD~N` if on main). Capture the diff and the list of changed files.

### Step 2: Dispatch 3 reviewers in parallel

Dispatch these 3 subagents via the Task tool. They can run simultaneously since they're all read-only and don't modify anything.

**Reviewer 1: Security lens**
```
Review this code diff through the SECURITY lens only.
Use the reviewer agent with lens: security.

## Diff
[paste diff or list changed files]

## Spec context (if available)
[security-relevant sections from SPEC.md]
```

**Reviewer 2: Architecture lens**
```
Review this code diff through the ARCHITECTURE lens only.
Use the reviewer agent with lens: architecture.

## Diff
[paste diff or list changed files]

## Architecture context (if available)
[docs/research/architecture.md contents, or CLAUDE.md patterns]
```

**Reviewer 3: Test-coverage lens**
```
Review this code diff through the TEST-COVERAGE lens only.
Use the reviewer agent with lens: test-coverage.

## Diff
[paste diff or list changed files]

## Test context
[test commands from CLAUDE.md or package.json]
```

### Step 3: Merge findings

After all 3 complete:

1. Collect all issues from all 3 reviewers
2. Deduplicate (same file + same line + similar issue = one finding, note which lenses caught it)
3. Sort by severity (CRITICAL > HIGH > MEDIUM > LOW)
4. Compute a combined score: average of the 3 lens scores

### Step 4: Present unified report

```markdown
# Parallel Review Report
Date: [date]
Files reviewed: [N]
Reviewers: security, architecture, test-coverage

## Critical issues (must fix)
1. [issue] -- found by: [lens(es)] -- [fix]

## High issues (should fix)
1. [issue] -- found by: [lens(es)] -- [fix]

## Medium issues
1. ...

## Low issues
1. ...

## Scores
- Security: [X]/10
- Architecture: [X]/10
- Test coverage: [X]/10
- Combined: [X]/10

## Verdict: SHIP / FIX THEN SHIP / DO NOT SHIP
```

Write to `REVIEW.md` in the project root. If issues are found, also append to `TODOS.md`.

### Step 5: Decision gate

If verdict is SHIP: suggest `/kit:docs` then `/kit:ship`.
If verdict is FIX THEN SHIP: list the specific fixes needed, ask if the user wants to address them now. If they choose to address now, dispatch the `responding-to-review` agent with the findings as input -- it will verify each item, push back on incorrect feedback, and propose fixes in priority order without performative agreement.
If verdict is DO NOT SHIP: explain what's fundamentally wrong.

## When to use /review-team vs /review

- `/review` (existing): Single-pass review by one agent. Faster, cheaper. Good for small changes, solo work, quick iteration.
- `/review-team` (this command): Parallel 3-lens review. More thorough, 3x the tokens. Good for: PRs before merge, contractor work review, pre-release code, anything touching auth/payments/data.

Source: Addy Osmani's parallel agent review pattern. gstack /review for the paranoid tone. Claude Code Agent Teams documentation for parallel subagent dispatch.

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

**Model tiering (SPEC-078 / ID-078, EveryInc Stage 4 pattern):** dispatch the
security reviewer with an EXPLICIT model override matching the session model ,
the security-auditor agent's frontmatter defaults to sonnet, so omitting the
override would silently down-tier the high-stakes lens, not inherit; dispatch
the architecture and test-coverage reviewers with the mid-tier override
(`model: sonnet`). If the override is unavailable in the dispatch surface, omit
it and note that in the report header. This roughly halves the command's token
cost without dulling the lens that catches exploits.

**Reviewer 1: Security (deep)**
```
Review this code diff through the SECURITY lens only.
Use the security-auditor agent (the dedicated deep-security reviewer; more thorough than the reviewer's security lens).

## Diff
[paste diff or list changed files]

## Spec context (if available)
[security-relevant sections from SPEC.md]
```

**Reviewer 2: Architecture lens**
```
Review this code diff through the ARCHITECTURE lens only.
Use the reviewer agent with lens: architecture.

Express findings in deep-module vocabulary (Ousterhout, via mattpocock
improve-codebase-architecture; SPEC-059): a module is DEEP when a small interface hides a
lot of behavior, SHALLOW when its interface is nearly as complex as its implementation.
Apply the deletion test to suspect modules: delete it mentally; if complexity vanishes it
was a pass-through, if complexity reappears across N callers it earns its keep. Name seams
explicitly (one adapter = hypothetical seam, two adapters = real seam) and justify each
finding in terms of leverage (what callers gain) and locality (where change, bugs, and
knowledge concentrate).

Two hard tripwires (SPEC-080 / ID-080, cursor, MIT): (1) the diff must not push any
file from under 1k lines to over 1k lines without a stated strong reason in the PR ,
flag it as a finding, not a nit; (2) weird if-statements in random places are a DESIGN
problem (spaghetti growth), never a style nit , name the structural cause.

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
4. **Classify each finding's Route (SPEC-078 / ID-076, EveryInc action-class
   rubric):** severity says how URGENT, the Route says what FOLLOW-UP SHAPE:
   - `gated_auto` , a concrete suggested fix exists; applied after judgment at
     the decision gate (never blindly).
   - `manual` , needs design input or a scope decision; not fixable inline.
   - `advisory` , worth recording, no action owed.
   When lenses disagree on a finding's class, route conservatively: manual beats
   gated_auto, advisory never downgrades a class another lens raised.
   (Upstream deprecated `safe_auto`; there is deliberately no auto-apply class.)
5. Compute a combined score: average of the 3 lens scores

### Step 4: Present unified report

```markdown
# Parallel Review Report
Date: [date]
Files reviewed: [N]
Reviewers: security, architecture, test-coverage

## Critical issues (must fix)
1. [issue] -- found by: [lens(es)] -- Route: [gated_auto|manual|advisory] -- [fix]

## High issues (should fix)
1. [issue] -- found by: [lens(es)] -- Route: [gated_auto|manual|advisory] -- [fix]

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

Write the unified report as a `## Review` section IN the active spec (`docs/specs/SPEC-NNN-<slug>.md`, the SPEC-005 rule), **replacing** any prior `## Review` (replace-not-stack). Keep the per-lens findings as subsections (`### Security`, `### Architecture`, `### Test coverage`) and the open items under `### TODOs`. If no active spec exists, output the report inline in chat instead. NEVER write the review (or per-lens files) to fixed-name files in the repo root; that pattern collides across concurrent worktrees and sessions.

Record the verdict for lane telemetry (SPEC-061), one line:
`bash lib/gate-ledger.sh record <rid> review ran "<verdict> findings=<K>"`.

### Step 5: Decision gate

If verdict is SHIP: suggest `/kit:docs` then `/kit:ship`.
If verdict is FIX THEN SHIP: list the specific fixes needed, ask if the user wants to address them now. Route by class (SPEC-078): `gated_auto` findings go to the `responding-to-review` agent as input -- it verifies each item, pushes back on incorrect feedback, and proposes fixes in priority order without performative agreement; each `manual` finding becomes a board row in `_meta/BACKLOG.md` (design input owed, not an inline fix); `advisory` findings are recorded in the spec's `## Review` section and nothing else is owed.
If verdict is DO NOT SHIP: explain what's fundamentally wrong.

## When to use /review-team vs /review

- `/review` (existing): Single-pass review by one agent. Faster, cheaper. Good for small changes, solo work, quick iteration.
- `/review-team` (this command): Parallel 3-lens review. More thorough, ~1.5-2x the tokens with model tiering (3x untiered). Good for: PRs before merge, contractor work review, pre-release code, anything touching auth/payments/data.

Source: Addy Osmani's parallel agent review pattern. EveryInc/compound-engineering-plugin (MIT) for the apply-class rubric + model tiering (SPEC-078, absorption 2026-06-11). gstack /review for the paranoid tone. Claude Code Agent Teams documentation for parallel subagent dispatch. mattpocock/skills improve-codebase-architecture for the architecture lens's deep-module vocabulary (SPEC-059).

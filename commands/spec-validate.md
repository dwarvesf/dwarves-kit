---
description: "Adversarial review of a spec before implementation. 5 reviewer personas attack the spec from different angles."
---

You are running an adversarial spec review. Read the spec from `docs/specs/SPEC-NNN-<slug>.md` (the most recent non-shipped spec if several exist). If no spec exists, tell the user to run `/user:spec` first.

## The 5 reviewers

Run each reviewer sequentially. For each one, present findings and ask the user if they want to address the issues before moving to the next reviewer.

### Reviewer 1: Security Auditor
Look for:
- Auth/authz gaps (who can access what? are there unprotected endpoints?)
- Input validation missing (SQL injection, XSS, path traversal)
- Secrets handling (hardcoded keys, unencrypted storage)
- Data exposure (PII in logs, verbose error messages)
- Dependency risks (known vulnerable packages)

### Reviewer 2: Failure Mode Analyst
Look for:
- What happens when external services are down?
- What happens with concurrent access / race conditions?
- What happens with malformed or unexpected input?
- What happens at 10x expected load?
- What's the recovery path for each failure?
- Are there any single points of failure?
- If the spec has a `## Failure modes` table, check each class is real and has both a detection signal and a mitigation; flag missing or hand-waved entries.

### Reviewer 3: Assumption Destroyer
Look for:
- Unstated assumptions about user behavior
- Assumptions about data quality or format
- Assumptions about infrastructure availability
- Assumptions about third-party API stability
- "Happy path only" designs with no error handling
- Implicit ordering dependencies between tasks

### Reviewer 4: Scope Critic
Look for:
- **Aggressive atomicity check (critical)**: Each task must fit in ~50% of a fresh context window (~100k tokens). Heuristic: if a task touches more than 5 files, or its description needs more than 3 sentences, or its acceptance criteria has more than 5 bullet points, it's too large. Flag it and suggest splitting. Source: GSD's "each plan is maximum 3 tasks, each fits in 50% context" principle.
- Tasks that bundle unrelated changes (e.g., "set up auth AND create user dashboard" is two tasks)
- Features disguised as requirements (nice-to-have dressed up as must-have)
- Gold-plating (things that sound important but aren't needed for v1)
- Missing tasks (gaps between spec and acceptance criteria: does completing all tasks actually satisfy the global acceptance criteria?)
- Unclear acceptance criteria (not testable: "should be fast" is not testable, "response under 200ms at p95" is)
- Missing dependency declarations (Task B clearly depends on Task A's output but doesn't say so)

### Reviewer 5: Solution-Design & Extensibility Critic
Look for:
- Is the chosen approach the simplest design that satisfies the requirements, or is it over- or under-engineered for what the problem needs?
- Are the 2-3 alternatives real and distinct, or strawmen? Are the tradeoffs honest?
- Coupling & boundaries: does each unit have one clear purpose and a defined interface? Can internals change without breaking consumers? A unit that can't be described without reading its internals has a boundary problem.
- Extensibility: does the design state what changes when the load-bearing dimension grows, and is that claim grounded or hand-waved? Flag "it scales" with no mechanism.
- Is there a materially lower-coupling or more extensible design the spec didn't consider?
- If the spec has an `### Interfaces (I/O contract)`, check inputs/outputs/invariants are concrete (named shapes, not "data in / data out").

**Calibration (critical):** only flag issues that would produce a flawed implementation or a design that cannot evolve. Do NOT flag stylistic preferences, "this section could be longer", or theoretical extensibility nobody asked for (YAGNI). Approve unless there is a real design weakness. If a spec predates this template (no `Approaches considered` section), raise the absent structure as ONE advisory recommendation, not a per-point critical flag; do not storm legacy or downstream specs.

Source: forked from superpowers:brainstorming ("design for isolation and clarity") + its spec-document-reviewer calibration. See docs/specs/SPEC-008.

## Output format

After all 5 reviewers complete, produce a summary:

```markdown
# Spec Validation Report
Date: [date]
Spec: [spec name]

## Critical Issues (must fix before implementation)
1. [issue] — [which reviewer found it] — [suggested fix]

## Warnings (address before shipping)
1. [issue] — [which reviewer] — [suggested fix]

## Passed
- [things that look solid]

## Verdict: APPROVED / NEEDS REVISION
```

If NEEDS REVISION, update `docs/specs/SPEC-NNN-<slug>.md` with the fixes and mark the Decision Log with entries for each change made.

If APPROVED, update the Status line in SPEC.md to `VALIDATED`.

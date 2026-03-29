---
description: "Adversarial review of a spec before implementation. 4 reviewer personas attack the spec from different angles."
---

You are running an adversarial spec review. Read the spec from `.planning/SPEC.md` (or the most recent spec file in `.planning/`). If no spec exists, tell the user to run `/user:spec` first.

## The 4 reviewers

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
- Tasks that are too large (won't fit in 50% context window)
- Tasks that bundle unrelated changes
- Features disguised as requirements
- Gold-plating (nice-to-have dressed up as must-have)
- Missing tasks (gaps between spec and acceptance criteria)
- Unclear acceptance criteria (not testable)

## Output format

After all 4 reviewers complete, produce a summary:

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

If NEEDS REVISION, update `.planning/SPEC.md` with the fixes and mark the Decision Log with entries for each change made.

If APPROVED, update the Status line in SPEC.md to `VALIDATED`.

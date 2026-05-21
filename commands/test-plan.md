---
description: "Derive a test-case coverage matrix from a spec's acceptance criteria before /user:execute. Writes TEST-PLAN.md. A coverage target across categories, not an exhaustive test list."
---

You are a test-plan author. Your job is to turn a spec's acceptance criteria into a test-case coverage matrix BEFORE `/user:execute`, so the build has a planned coverage target instead of ad-hoc tests.

This is NOT a roundtable and has NO personas. Test planning derives from FIXED acceptance criteria, so the right shape is systematic coverage, not divergence. (A design critique explores an open space; this enumerates against a fixed contract.)

## Process

### Step 1: Find the active spec

Detect the active `docs/specs/SPEC-NNN-<slug>.md` the way `/user:next` does (branch-aware). If several specs match, ask the user which one. Read its `## Acceptance Criteria` section (or the per-task acceptance checkboxes). If no spec has acceptance criteria to read, say so and point the user to `/user:spec`.

### Step 2: Enumerate the coverage matrix

Enumerate test cases across these categories. Map each case to the acceptance criterion (or criteria) it covers.

1. **Happy-path** -- the expected, in-spec behavior for each acceptance criterion.
2. **Boundary / edge** -- limits, empty inputs, max sizes, off-by-one, first/last.
3. **Failure-injection** -- a dependency errors, times out, or returns garbage.
4. **Security / abuse** -- malformed input, injection, privilege, untrusted-content handling.
5. **Regression** -- behavior the change must not break (existing contracts, prior fixes).

Skip a category only when it genuinely does not apply to this spec, and say why in the coverage notes. Do not pad with cases that do not map to an acceptance criterion.

### Step 3: Write TEST-PLAN.md

Write `TEST-PLAN.md` in the project ROOT (same placement convention as `REVIEW.md` / `TODOS.md`).

```markdown
# Test plan: SPEC-NNN <slug>
Date: [date]
Source: docs/specs/SPEC-NNN-<slug>.md ## Acceptance Criteria

| # | Case | Category | Covers (AC) | Expected |
|---|------|----------|-------------|----------|
| 1 | [case] | happy-path | AC-1 | [expected result] |
| 2 | [case] | boundary/edge | AC-1 | [expected result] |
| 3 | [case] | failure-injection | AC-2 | [expected result] |
| ... | | | | |

## Coverage notes
- Categories skipped: [category -- why, or "none"]
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list. A missing acceptance criterion or an unenumerated category is a gap, surfaced here, not a guarantee.
```

### Step 4: Hand off

Tell the user the plan is written and `/user:execute` should build against it as the coverage target. Do NOT run `/user:execute` yourself; this lane only plans the test cases.

## Source
The kit's own coverage-matrix shape. There is no external roundtable source; this is deliberately NOT a persona roundtable (SPEC-016 DEC-004): it enumerates against fixed acceptance criteria. `TEST-PLAN.md` placement mirrors `REVIEW.md` / `TODOS.md` (project root). Realizes SPEC-016 Part B (the test lane).

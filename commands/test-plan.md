---
description: "Derive a test-case coverage matrix from a spec's acceptance criteria before /kit:execute. Writes a `## Test plan` section into the active spec. A coverage target across categories, not an exhaustive test list."
---

You are a test-plan author. Your job is to turn a spec's acceptance criteria into a test-case coverage matrix BEFORE `/kit:execute`, so the build has a planned coverage target instead of ad-hoc tests.

This is NOT a roundtable and has NO personas. Test planning derives from FIXED acceptance criteria, so the right shape is systematic coverage, not divergence. (A design critique explores an open space; this enumerates against a fixed contract.)

## Process

### Step 1: Find the active spec

Detect the active `docs/specs/SPEC-NNN-<slug>.md` the way `/kit:next` does (branch-aware). If several specs match, ask the user which one. `/kit:execute` resolves the active spec through this SAME detection path, so the plan you write lands in the spec execute will read. Read its `## Acceptance Criteria` section (or the per-task acceptance checkboxes). If no spec has acceptance criteria to read, say so and point the user to `/kit:spec`.

### Step 1b: Pick the dialect from the work's type

```bash
bash lib/task-type-classify.sh classify "<the spec's objective / title>"
```

`spec-feature` uses the BDD-style category matrix below (Step 2). Any other type designs in its
own dialect per `docs/verification/test-design-standard.md` §5b (eval -> metrics + hand-verified
seeds + falsifiability controls; research -> claim-verification matrix; migration/cleanup ->
inventory + rollback rehearsal; data-tool -> recorded live run + negative control; doc ->
doc-verifier match). The section written into the spec is still `## Test plan`; the dialect
changes the matrix's shape, not the heading, the AC-traceability, or the proof-per-case rule.

### Step 2: Enumerate the coverage matrix

Enumerate test cases across these categories. Map each case to the acceptance criterion (or criteria) it covers.

1. **Happy-path** -- the expected, in-spec behavior for each acceptance criterion.
2. **Boundary / edge** -- limits, empty inputs, max sizes, off-by-one, first/last.
3. **Failure-injection** -- a dependency errors, times out, or returns garbage.
4. **Security / abuse** -- malformed input, injection, privilege, untrusted-content handling.
5. **Regression** -- behavior the change must not break (existing contracts, prior fixes).

For each case also name its **proof**: the concrete command or artifact that demonstrates the case passed (e.g. `bash tests/test-meta.sh`, `pytest tests/x::test_y`, a `grep` assertion, a named log line or screenshot). When the proof is not knowable at plan time, write `TBD`; do NOT invent a command. A `TBD` is an honest hole, surfaced like an uncovered category, not a fabrication.

Skip a category only when it genuinely does not apply to this spec, and say why in the coverage notes. Do not pad with cases that do not map to an acceptance criterion.

### Step 3: Write the `## Test plan` section into the active spec

Append a `## Test plan` section to the active `docs/specs/SPEC-NNN-<slug>.md` (the same spec you read in Step 1), exactly how `/kit:devs-team` appends `## Design critique`. One `## Test plan` per spec: if the section already exists, REPLACE it (from the `## Test plan` heading to the next `## ` heading or end of file); do not stack a second copy. Do NOT write a separate root-level plan file; the plan lives in the spec so it travels with the spec and supports multiple specs at once.

```markdown
## Test plan
Date: [date]
Source: this spec's ## Acceptance Criteria

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | [case] | happy-path | AC-1 | [expected result] | [command/artifact, or TBD] |
| 2 | [case] | boundary/edge | AC-1 | [expected result] | [command/artifact, or TBD] |
| 3 | [case] | failure-injection | AC-2 | [expected result] | [command/artifact, or TBD] |
| ... | | | | | |

### Coverage notes
- Categories skipped: [category -- why, or "none"]
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list. A missing acceptance criterion or an unenumerated category is a gap, surfaced here, not a guarantee.
```

### Step 4: Hand off

Tell the user the plan is written into the spec's `## Test plan` and `/kit:execute` will build against it as the coverage target (each case's `proof` becomes that step's verify command where named). Do NOT run `/kit:execute` yourself; this lane only plans the test cases.

## Source
The kit's own coverage-matrix shape. There is no external roundtable source; this is deliberately NOT a persona roundtable (SPEC-016 DEC-004): it enumerates against fixed acceptance criteria. The `## Test plan` section is written into the active spec, mirroring `/kit:devs-team`'s `## Design critique` append (SPEC-016 Part A), so the plan is per-spec and `/kit:execute` can read the spec it is already executing (SPEC-018). The `proof` column adapts harness-experimental's `TEST_MATRIX.md` Evidence column (behavior-to-proof). Realizes SPEC-016 Part B (the test lane) as revised by SPEC-018.

After writing the plan, record it for lane telemetry (SPEC-062), one line:
`bash lib/gate-ledger.sh record <spec-slug> test-plan ran "matrix rows=<N> categories=<list>"`.

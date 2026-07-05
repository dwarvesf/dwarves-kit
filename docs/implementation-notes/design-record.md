# Implementation notes: design record before build (understanding-gate SG-01)

Spec: SPEC-122. Branch: `feat/ug-01-design-record`, worktree `.claude/worktrees/ug-01`, off
master. Built lane-normal via the lib machinery (a cross-repo mega-goal sub-goal; no `/kit:*`
slash commands, since the run's cwd is unstable across worktrees).

## 2026-07-03, decisions the spec + ADR-0031 didn't fully pin down

- **`## Design` is a NEW top-level section, not a rename of `### Architecture (diagram if it
  helps)` in place.** ADR-0031 §1 says "the spec MUST carry a `## Design` block"; it does not
  say whether that reuses the existing sub-heading or adds a new one. Chose new-section
  (DEC-002 in the spec) because the `obvious: <why>` collapse needs to be checkable in
  isolation from `## Solution`'s own (advisory) Reviewer 5 pass. The old `### Architecture`
  line now just points at `## Design` rather than duplicating content.

- **Reviewer 6's finding is the ONE blocking check in `/kit:spec-validate`; Reviewers 1-5 stay
  advisory.** This is the sharpest deviation from the kit's own established pattern (every
  prior spec-validate reviewer, including SPEC-008's Reviewer 5, is advisory-only,
  "Detect, don't dictate"). ADR-0031 §1 is explicit ("refuses VALIDATED"), so this spec treats
  it as a deliberate, scoped exception rather than softening the ADR's language to match the
  kit's usual advisory posture. The blast radius is narrow and reversible: it can only
  withhold a `VALIDATED` flip, never block a build, and only fires on a spec that is BOTH
  above-tiny AND design-bearing.

- **`WORKFLOW.md`'s Lane×phase depth matrix gained a REAL row** ("Design record
  (design-bearing, ADR-0031 §1)"), not a documentation-only note beside the Validate row. This
  had a load-bearing consequence I did not anticipate at spec time: `lib/gate/gate-ledger.sh`
  dynamically PARSES that matrix at runtime to build `plan`/`progress`'s phase checklist and
  `required`'s ship-gate list. Adding a row with `run-lite` (normal) / `measure-twice` (full)
  cells changed the normal-lane plan from 8 steps to 9 (a new step lands between `spec` and
  `test-plan`) and made the phase a REQUIRED ship-gate item for the full lane. This broke 7
  hardcoded step-count/phase-list assertions across `tests/test-hooks.sh` (the `spec-p`
  progress fixture, the `full-noui`/`full-gap` shipped-incomplete detector fixtures) and 3 in
  `tests/test-e2e.sh` (the golden run). Fixed by renumbering the expected `step k/n` values and
  adding a `design-record ran` ledger line to the fixtures that are supposed to represent a
  fully-disposed run, rather than by pulling the row out of the parsed table. Kept it IN the
  table (not a side-note) because that is what makes `Design (opt-in)` (the existing,
  different, opt-in `/kit:design` facilitator row) and the new gate consistent: both are real,
  trackable phases with a real per-lane depth, not narrative.

- **`test-meta.sh`'s reviewer-count assertions bumped 5 -> 6** (the header string and a new
  "Reviewer 6" presence check), plus the existing "no stale N reviewer" count-drift guard
  extended to also catch a stale "5 reviewer" reference, mirroring the guard SPEC-008 already
  added for "4 reviewer" drift. Both are structural-presence checks, same style as the rest of
  the file; no new test dialect introduced.

- **`commands/design.md`'s Step 4/5 wiring is additive, gated on design-bearing.** The
  interactive lane only asks for a diagram + ADR link(s) when the design IS design-bearing; it
  does not add a mandatory extra beat to every `/kit:design` run, matching the proportionality
  rule the rest of this feature holds to.

## Test-harness honesty note (not a deviation, a named limitation)

`/kit:spec-validate` is prompt text, not executable code, so `tests/test-design-record.sh`
cannot drive the live LLM reviewer. Each fixture pre-declares its own design-bearing ground
truth (`Design-bearing (fixture declaration): yes/no`), which stands in for the step the real
Reviewer 6 would do by judgment. The harness then proves the STRUCTURAL contract only:
given that declaration and the `## Design` section's actual content, does the pass/refuse call
match what Reviewer 6 is specified to do? This is the same boundary SPEC-008 already accepted
for Reviewers 1-5 (structural presence, not live judgment quality); named in SPEC-122's Test
plan COVERAGE-DELTA row rather than hidden.

## Verification
`bash tests/test-design-record.sh` (26/26) + `bash tests/test-meta.sh` (663/663) +
`bash tests/test-hooks.sh` (452/452) + `bash tests/test-e2e.sh` (20/20), all green after the
renumbering fix above. `bash tests/test-classify-md-inert.sh` has one pre-existing failure
(`stripped lib should reproduce the stateful bug`, a `/tmp`-relative-sourcing fragility in a
lib/gate/proof-ledger.sh test unrelated to this change) confirmed present on master before this
branch touched anything; left alone as out of scope.

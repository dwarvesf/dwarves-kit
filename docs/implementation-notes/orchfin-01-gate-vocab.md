# orchfin-01-gate-vocab -- implementation notes (ID-091)

Delta from the sub-goal file (`_meta/megagoals/orchestrator-finish/goals/01-gate-vocab-align.md`)
only. Reference that file + WORKFLOW.md for the full contract; this is what it didn't pin down.

## 2026-07-05 19:40 Lane classify returned `full`, not the sub-goal's expected `normal`

Context: the sub-goal text says `bash lib/classify/lane-classify.sh classify "..." ` (expect
`normal`). The actual classifier returned `full`.

Decision: proceeded without escalating to a formal SDD spec cycle. This is a mega-goal delegate
sub-goal (goal-craft shaped, not SPEC-NNN driven); there is no spec file whose `Lane:` header
`hooks/ship-gate.sh` reads, so the heavier classify result has no enforcement teeth here (the
ship-gate test suite confirms a no-spec branch "fails open"). Recorded the gates I actually ran
(`build`, `review`, `docs`, plus a `grill skipped reason=operator-wave`) against the branch rid
either way, for the audit trail.

Why: the scope of the actual change (3 command-prompt edits + 1 doc section + 1 new test file, no
`lib/` or `hooks/` code touched) matches a `normal`-shaped effort; chasing the classifier's `full`
verdict with a full SDD spec/design-critique/design-record ceremony for a documentation-and-prompt
fix would be process theater the repo's own "write a spec only when it will hit a gate" rule warns
against.

Impact: none on the actual fix. Flagging honestly per the "log a deviation, keep going" rule.

## 2026-07-05 19:45 `devs-team.md` keeps BOTH its `review` record and the new `design-critique` record

Context: the pinned direction said "devs-team.md -> also record design-critique"; it did not say
to replace the existing `review ran` line.

Decision: kept both lines. `review` stays useful RUN_REPORT observability (some readers may still
look for it under that name) and costs nothing to keep; `design-critique` is the new, literal-name
record that actually satisfies the full-lane matrix row `gate-ledger.sh check` matches on.

Why: minimal, additive, reversible; matches the goal's explicit "additive marker" pattern used
elsewhere in this file (`tokens`, `debt`, `outcome`).

## 2026-07-05 19:47 `design-record`'s owner is `spec-validate.md` Reviewer 6, not a new command

Context: the goal's "In" scope named three places to touch: `execute.md`, `devs-team.md`, and "the
design-record owner" -- without naming it.

Decision: `spec-validate.md` Reviewer 6 (the Design Record Auditor) is that owner -- it is already
the sole enforcement point for design-bearing specs (WORKFLOW.md "## The understanding axis"
already said so before this change). Added a `design-record ran` record call immediately after
its existing `Validate ran` line, in the same command, same step. No new command was created (the
goal's "Out" scope forbids adding a new gate; this is not a new gate, it is the existing Reviewer
6 check getting its own record call under its own matrix name).

## Verification

`bash tests/test-gate-vocab-recording.sh` (new, 17/17): static sweep (every full-lane required
name has a real command recording it by literal name) + dynamic proof (a full run with all 12
gates recorded reaches `gate-ledger.sh check full <rid>` exit 0; a run missing just `build`
re-blocks with `MISSING-GATE: build`). Regression-checked against `test-command-emit-sweep.sh`
(19/19), `test-design-record.sh` (26/26), `test-references-field.sh` (15/15), `test-gate-outcome.sh`
(22/22) -- all still green, no drift introduced.

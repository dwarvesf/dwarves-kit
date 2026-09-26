# Implementation notes: SPEC-320 spec auto-validate

Delta from `docs/specs/SPEC-320-spec-autovalidate.md`. The spec's own decisions are not repeated here.

## Deviations and decisions

- The operator asked to "require" validation. The design critique showed the hard ship-gate on the normal lane lands estate-wide and reclassifies history, so the spec executes validation automatically at every entry point, blocks the build in `/kit:execute`, and keeps the normal-lane ship-gate cell `run-lite`. The flip to `measure-twice` stays one cell if the operator still wants it.
- The spec took four fresh validation passes (NEEDS REVISION 3 critical, 3 critical, 2 critical, then APPROVED). Each pass found real defects the author missed, including a preflight grep that would have matched a failed validation.

## Build deltas

- `tests/test-wrap.sh` pinned the old step-10 literal `reported: spec-validate BLOCK: <finding>`. T2 does not list it; the pin moved to item 6's literal `reported: spec-validate BLOCK|NEEDS REVISION: <criticals>` so the suite stays green.
- `commands/spec-validate.md` gained two lines item 1 implies: it reads the spec path the caller names (else the most recent non-shipped spec), and a READ-ONLY dispatch skips every edit, Status flip, and record. Without them the skill text contradicts the validator prompt.
- `/kit:spec`'s dispatch is a new `### Step 5: fresh-context validation` after step 4's `Spec ran` record, so the order check in `tests/test-meta.sh` reads line numbers, not prose.
- `commands/wrap.md` step 10's "Wrap never merges" paragraph said an unattended validate pass "checks the spec against itself"; that is no longer true, so the clause now says the validator checks the spec, not the direction.
- `tests/test-gate-ledger-plan-record.sh` cases C2, C3, C6, C7, C9, C10 each gained `--ran validate`, so each still fails for its own reason and not for the new missing disposition (C9 and C10 would otherwise exit 64 before the override guard runs).
- The red runs for `tests/test-e2e.sh` and `tests/test-gate-ledger-plan-record.sh` used `GATE_LEDGER_WORKFLOW` pointed at the pre-change matrix, because the matrix edit landed while the first red run was in flight.
- `docs/FEATURES.md` was regenerated before the first commit (test-meta's freshness check reads the WORKFLOW edit) and again last, after the T4 prose.
- `tests/test-outcome-emit-sweep.sh` requires every `record <rid> <phase> ran` site in `commands/*.md` to carry its own `outcome start`/`end` bracket. The step-10 worker's new `Spec ran` record therefore opens and closes a `Spec` bracket in `commands/wrap.md`, the same pair `/kit:spec` writes.
- `tests/run-all.sh --changed` rewrites the tracked `docs/verification/pitch-command/sample-pitch.md` as a side effect; the file was restored with `git checkout --` and is not part of this change.

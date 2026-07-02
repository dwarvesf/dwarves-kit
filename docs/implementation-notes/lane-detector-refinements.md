# Implementation notes: lane-detector-refinements (SPEC-102)

Delta from the spec. Reference, do not restate.

## 2026-07-02 shipped-incomplete delegates to `check`, not `progress`

**Context:** the spec says "treat lite phases as disposed." The old detector delegated to
`gate-ledger.sh progress` and grepped the literal `complete`; `progress` counts lite phases.
**Decision:** delegate to `gate-ledger.sh check <lane> <rid>` instead (required-gate contract).
**Why:** `check` already ignores run-lite phases (it only inspects measure-twice gates) and is
the SAME contract `hooks/ship-gate.sh` enforces, so "shipped-incomplete" gets the precise
definition "shipped but would not pass its own ship-gate." Changing `progress` to ignore lite
phases would have rippled into the `complete (n/n)` display and the e2e/assign progress pins;
delegating to `check` keeps `progress` untouched.
**Alternatives:** duplicate the required-phase disposition logic in the detector (rejected: the
seam exists to avoid duplicating the matrix parse; `check` already parses it).
**Impact:** retires the A4 "complete" cross-lib seam; the seam pin now asserts the detector
calls `check`. `check` treats a required gate `skipped`-with-reason as unsatisfied (only
ran/override pass) -- stricter than progress's disposition, but correct for this detector (a
required gate that was skipped IS a ship-over-skip).

## 2026-07-02 boardless keeps the rid match, ADDS the ID/PR match

**Context:** the spec says "match by PR/ID, not raw rid."
**Decision:** on-board if the board contains the rid (kept, for the `[run <rid>]` convention the
existing test uses) OR any `ID-NNN`/`PR #N` token from the run's ledger.
**Why:** dropping the rid match would break the existing `[run spec-ghost]` negative control;
adding the ID/PR match fixes the real false-flag (rows key on ID/PR). A `while IFS= read` loop
(not `for`) iterates the tokens because a `PR #N` token carries a space.
**Impact:** real corpus boardless 6 -> 3; shipped-incomplete 15 -> 0. The 3 residual boardless
runs (`kit-clean-01-startwire`, `cc-hyg-04`, `kit-telem-04-dashboard`) carry no board-linked
ID/PR in their ledger -- a data gap, not a detector bug (SPEC-102 Open questions).

## 2026-07-02 pins live in test-hooks.sh, not test-lane-telemetry.sh

**Context:** goal-file 02 said "extend tests/test-lane-telemetry.sh."
**Decision:** the detector pins go in `tests/test-hooks.sh` (lines 218-244), where the boardless
+ shipped-incomplete fixtures + the `BDT` helper already live; `tests/test-lane-telemetry.sh`
covers report/render only.
**Why:** co-locate with the existing detector suite; no new fixture harness needed.

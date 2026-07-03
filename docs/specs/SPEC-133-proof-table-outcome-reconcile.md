# Spec: Reconcile proof-table-gen's OUTCOME reader to the real gate-outcome marker

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (a parser fix over a known, now-merged ledger schema; no new subsystem, no
correctness-critical concurrency).

## Problem

SPEC-132 (`lib/proof-table-gen.py`, sub-goal 05) shipped an OUTCOME parser against an
**assumed** single-line marker shape (documented as "ASSUMED shape for sub-goal 01 ... may
not be merged yet"). SPEC-129 (sub-goal 01, `lib/gate-ledger.sh`'s `outcome()`/`outcome_read()`)
has since merged with a **different, real** shape: TWO lines per gate bracketing start/end,
using `dur_s=` (seconds), not the assumed single-line `dur_ms=`.

Concretely, 01's real marker:
```
<TS> | OUTCOME | <phase> | start | at=<epoch>
<TS> | OUTCOME | <phase> | end   | at=<epoch> caught=<true|false> dur_s=<N>
```
(field 3 = phase, field 4 = event `start|end`; `caught=`/`dur_s=` appear only on the `end`
line.)

05's current parser treats `parts[3:]` as one kv blob and regexes for `caught=` and
`dur_ms=` without modeling the event field. Effect verified against a real-shape fixture:
`caught=` happens to still match (the regex is unanchored, so it finds `caught=true` inside
the `end` line's kv blob regardless of the `start|end` token in front of it), but `dur_ms=`
never matches (01 never emits that key), so the DURATION column is always `n/a`. The
CAUGHT column's accidental match is not a designed pairing (it doesn't distinguish
start-line noise from end-line signal), so it is fragile, not correct. Net effect: the
MEASURABLE-to-HONESTLY-PROVEN link this mega-goal exists to make is broken for duration and
accidental for caught.

## Solution

Rewrite the OUTCOME branch of `parse_ledger()` in `lib/proof-table-gen.py` to model 01's
real two-line shape directly:

- Recognize `parts[3]` as the event (`start`|`end`).
- On a `start` line: record the phase's `at=` epoch (for the duration fallback only); do
  not populate `outcomes[phase]` yet (avoids a start-only phase reading as "has an
  outcome").
- On an `end` line: read `caught=` and `dur_s=` from its kv blob. If `dur_s=` is absent but
  a matching `start` epoch was seen, fall back to `end.at - start.at`. Populate
  `outcomes[phase] = {"caught": ..., "dur_s": ...}` (last end-line-per-phase wins, matching
  `outcome_read()`'s own semantics).
- Rename the rendered column from `Duration (ms)` to `Duration (s)` and print `dur_s`
  directly (no unit conversion; 01 already emits whole seconds).
- Update the stale doc comment (the "ASSUMED shape ... may not be merged yet" note) to the
  real, merged shape, referencing SPEC-129.
- Preserve every additive-tolerance property SPEC-132 already established: an entirely
  absent OUTCOME marker still renders the 5-column table (no Caught/Duration header, no
  crash); a phase with a GATE row but no OUTCOME end-line still renders `n/a` in both
  columns without crashing the row.

**Not changed:** 01's marker format (read-only consumer), 05's output file location/naming,
the acceptance/coverage-delta sections, the CLI surface (`proof-table-gen.sh <rid>
[out-path]`).

### Test fixture correction

`tests/test-proof-table-gen.sh`'s T2/T2B fixtures encode the **assumed** (now known
incorrect) single-line shape from SPEC-132's original write. They are updated in place to
the real 01 two-line shape (start/end pair, `dur_s=`), preserving the exact behavioral
properties they test (round-trip population, per-row degrade-to-n/a, whole-table
degrade-to-absent) -- these fixtures were pinning a hypothesis that has since been falsified
by the real merged marker, not a still-valid contract to protect verbatim.

## Design

`obvious: not design-bearing`. No new component, no schema change, no external
integration, no irreversible choice, and exactly one viable approach (read the marker
format that already exists in merged code). This is a like-for-like parser correction
inside an existing function (`parse_ledger()`'s `OUTCOME` branch) against an existing,
now-fixed wire format (SPEC-129's `outcome()`/`outcome_read()`); the "before/after" is
fully captured by the two marker-shape blocks in `## Problem` and `## Solution` above, so a
diagram would restate them without adding information.

## Acceptance criteria

1. A real-01-format OUTCOME pair (`start` + `end` with `caught=true dur_s=N`) round-trips:
   the generated table's Caught column shows the caught value and the Duration (s) column
   shows `N`.
2. A phase with GATE coverage but no OUTCOME lines at all still renders `n/a`/`n/a` for that
   row (per-row degrade, unchanged from SPEC-132).
3. A ledger with zero OUTCOME lines anywhere still renders the plain 5-column table (no
   Caught/Duration header), unchanged from SPEC-132.
4. `bash tests/test-proof-table-gen.sh` is green after the fixture correction.
5. A negative control (parser reverted to the pre-fix regex) turns the real-01-format
   assertion RED, proving the fix is load-bearing.

## Verification

```
bash tests/test-proof-table-gen.sh
```
All assertions PASS; see `docs/verification/kri-outcome-reader.md` for the full run-table
including the negative control.

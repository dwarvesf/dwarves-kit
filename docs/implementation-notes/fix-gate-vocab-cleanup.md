# fix-gate-vocab-cleanup: delta notes

Delta from the worker brief. One section per item.

## 1. NEEDS-REVISION spelling

- `validate-round close` now writes `GATE | validate | skipped | NEEDS-REVISION: ...`.
- No reader matched the GATE text. The only text reader is the resume guard (`_vr_norm`); it folds the old `NEEDS REVISION:` form so a half-written round from an older kit still resumes.
- Old ledgers keep the space form. Test fixtures that model old ledgers keep it on purpose.
- Docs outside the slice (`docs/MANUAL.md`, `docs/reference/architecture.md`, `docs/reference/workflow-paths.md`, `docs/design/kit-uml.html`) still say `NEEDS REVISION`. Not touched.

## 3. Proof asset status pending

- Removed the manifest `status == "pending"` read in `proof-ledger.sh`. No writer produces it (`bin/proof-asset` queues in `.kit/proof-assets/<slug>/.pending`). The `.pending` queue check stays.
- Dropped the now unused local `n`.

## 4. MUTATION ledger marker: skipped

- The brief says remove it only if no command or skill prose calls it. Prose does: `agents/break-it.md` greps the run ledger for a `| MUTATION |` marker to detect the verify-before-battery inversion, and `commands/verify.md` Step 6b says it records the marker.
- Also pinned by `tests/test-mutation-smoke.sh` T8 and `tests/test-kri-wiring.sh` (ADR names the verb). `lib/gate/mutation-smoke.sh` writes it.
- No code reads the rows, so removal is possible, but it needs `agents/` and ADR edits outside this slice. Left in place.

## 5. Bench unknown gate state

- One map, `GATE_STATE` in `lib/bench/events.py`; `report.py` imports it. An unmapped state is `unknown`, shown as `?` in the matrix and the viewer.
- `run_end` is `fail` when a required gate (per the lane plan) was never recorded or is `unknown`; else `pass`. A required gate that is `skipped` still counts as recorded, as before. Open question: should a skipped required gate fail the run? Conformance already scores it as absent.

## 6. Lane rank, one source

- The brief said make one of the two the source. Both already source `lib/gate/lane-data.sh` (the one reader of lane data), so the table lives there as `lane_rank_of`. Sourcing `lane-classify.sh` into the ledger would load the whole flag engine.
- `gate-ledger.sh` `_lane_rank` still prints empty for an unknown lane. `lane-classify.sh` `lane_rank` still prints `-1`. Each keeps its caller contract.

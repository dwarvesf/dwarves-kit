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

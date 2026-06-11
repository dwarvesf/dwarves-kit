# Proof of done: v-model-descent (SPEC-076)

Behavioral change: tiny x Review matrix cell skip -> run-lite (review obligation on
every lane); gate-ledger `descent` verb (plan-order timeline detector, lite-implicit,
deduped); ship-gate descent advisory; WORKFLOW descent contract + AGENTS one-liner.

## Green run

Failing-first: 8 RED pre-implementation -> green; the review rework (lite-only
implicit checkpoints) was itself caught RED by the existing violation fixtures
before the semantics were narrowed.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 386 / 386`

Command: `bash tests/test-meta.sh` -> 442/442. `bash tests/test-e2e.sh` -> 20/20.

Live dogfood: `bash lib/gate-ledger.sh descent v-model-descent full` ->
`descent clean` on this very run.

## NEGATIVE CONTROL

Run live at build: the `descent)` case arm commented out -> 6 RED (every
dispatch-dependent assertion) -> restored -> green.

## Reproduce

```bash
cd dwarves-kit && bash tests/test-hooks.sh   # 386/386
```

VERDICT: PASS

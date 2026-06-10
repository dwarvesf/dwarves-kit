# Proof of done: golden-run (SPEC-067)

Behavioral change: tests/test-e2e.sh added (the end-to-end loop harness), CI wired.

## Green run

Command: `bash tests/test-e2e.sh`
Exit: 0
Output (tail): `Passed: 20 / 20` / `Golden run green.` , one task walked board-pull ->
classify -> START -> the full phase sequence -> ship, with gate-ledger check green, progress complete
(8/8), telemetry counting the run + ship + surfacing the verdict, trace rendering, and
the board row at shipped.

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `All meta tests passed.` (the first draft of THIS doc broke the SPEC-031
lint and falsely claimed the count; caught in review, fixed, re-verified)

## NEGATIVE CONTROL

In-suite, runs every execution: the drift-control block STARTs a deliberately misrouted
run (chosen=tiny classified=full) and the suite FAILS unless all three read surfaces see
it (report `lane-misrouted: 1`, misfires names the pair, trace prints `<< LANE MISFIRE`).

Live during build: the first fixture phrase ("demo CLI") legitimately failed the type
assertion (19/20 RED) because of a real classifier over-match , the harness caught real
drift on its very first run; finding filed as board ID-057, fixture cleaned, 20/20 GREEN.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-e2e.sh   # 20/20
```

VERDICT: PASS

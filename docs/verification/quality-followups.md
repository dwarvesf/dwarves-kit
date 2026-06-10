# Proof of done: quality-followups (SPEC-069)

Behavioral change: telemetry detectors (boardless, shipped-incomplete), ship-gate advisory,
TTY-gated colors, review-escalation + grill wiring.

## Green run

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 316 / 316` , detector fixtures (boardless named + counted,
shipped-incomplete named, false-positive guard: a complete shipped run is NOT flagged),
seam-agreement pins, bidirectional color tests (PTY emits escape bytes; piped emits zero).

Command: `bash tests/test-meta.sh` -> `All meta tests passed.` (426)
Command: `bash tests/test-e2e.sh` -> `Golden run green.` (20/20)

Live: the detectors' first execution flagged the REAL pre-discipline history (3 boardless,
2 shipped-incomplete runs from before the operator's catch).

## NEGATIVE CONTROL

In-suite, every execution: (a) the boardless fixture's rid is added to the fixture board
and the assertion REQUIRES the boardless flag to vanish; (b) the piped color test REQUIRES
zero escape bytes (breaking the TTY gate in either direction flips one of the pair).

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh   # 316/316
```

VERDICT: PASS

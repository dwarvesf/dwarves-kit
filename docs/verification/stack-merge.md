# Proof of done: stack-merge (SPEC-065)

Behavioral change: lib/stack-merge.sh added (squash-stack merge dance), ship.md wired.

## Green run

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 288 / 288` , includes the 6 SPEC-065 assertions (3 dry-run content
pins via a PATH-shimmed fake gh, the ordering pin retarget < merge < reconcile asserted on
line numbers, usage exits 64, zero-arg chain exits 64).

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 422 / 422`

## NEGATIVE CONTROL

Run live during build: the retarget block was moved AFTER the parent merge in
lib/stack-merge.sh (the exact auto-close gotcha the tool exists to prevent), suite re-run:

- Broken ordering -> `FAIL stack-merge: ordering retarget < merge < reconcile` (RED)
- Restored -> `All tests passed.` (GREEN)

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh   # 288/288
```

VERDICT: PASS

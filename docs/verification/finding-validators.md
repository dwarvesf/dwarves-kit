# Proof of done: finding-validators (SPEC-082)

Behavioral change (prose contract): review-team Step 3b , one adversarial
refuter per unsuppressed CRITICAL/HIGH finding, never batched; refuted demotes
with the refutation, confirmed marks validated, infra failure never drops.

## Green run

Failing-first: 8 meta pins RED pre-edit -> green.

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 473 / 473`

Command: `bash tests/test-hooks.sh` -> 412/412. `bash tests/test-e2e.sh` -> 20/20.

## NEGATIVE CONTROL

Run live at build: the never-batch token text-reverted -> 1 RED -> restored
green.

## Reproduce

```bash
cd dwarves-kit && bash tests/test-meta.sh
```

VERDICT: PASS

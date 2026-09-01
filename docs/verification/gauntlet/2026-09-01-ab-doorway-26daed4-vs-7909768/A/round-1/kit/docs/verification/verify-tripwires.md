# Proof of done: verify-tripwires (SPEC-080)

Behavioral change: /kit:verify claim-restatement + INCONCLUSIVE verdict;
proof-ledger INCONCLUSIVE rejection with last-verdict-wins semantics; README
comparative-evidence pair; review-team Reviewer 2 tripwires.

## Green run

Failing-first: 4 meta pins RED pre-edit -> green. Lens-2 behavioral fixtures:
synthetic INCONCLUSIVE record exits 1; PASS control exits 0; append-retry (old
INCONCLUSIVE + new PASS) exits 0; reverse order (latest INCONCLUSIVE) exits 1.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 412 / 412`

Command: `bash tests/test-meta.sh` -> 454/454. `bash tests/test-e2e.sh` -> 20/20.

## NEGATIVE CONTROL

Run live at build: the INCONCLUSIVE token text-reverted in verify.md -> 1 RED ->
restored green. The gate fixtures are bidirectional by construction (block and
pass sides both pinned).

## Reproduce

```bash
cd dwarves-kit && bash tests/test-hooks.sh && bash tests/test-meta.sh
```

VERDICT: PASS

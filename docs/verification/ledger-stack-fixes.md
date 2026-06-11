# Proof of done: ledger-stack-fixes (SPEC-077)

Behavioral change: gate-ledger `start --amend` (START-AMEND, last-amend-wins read
contract across 4 reader sites); stack-merge `ensure_reconciled` (state-keyed
self-reconcile per link, ff-sync, ancestry assertion, branch restore).

## Green run

Failing-first: 7 RED pre-implementation; the review's AMEND-first fixture was RED
on the unfixed _rows reader before its fix.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 398 / 398`

Command: `bash tests/test-meta.sh` -> 444/444. `bash tests/test-e2e.sh` -> 20/20.

## NEGATIVE CONTROL

Run live at build: the --amend branch commented -> 3 RED; the ensure-reconciled
case arm commented -> 4 RED; both restored -> green.

## Reproduce

```bash
cd dwarves-kit && bash tests/test-hooks.sh   # 398/398
```

VERDICT: PASS

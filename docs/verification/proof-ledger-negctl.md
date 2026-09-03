# Proof of done: proof-ledger negctl

Change under proof: `lib/gate/proof-ledger.sh` gains `negctl <root> <test-cmd> <mutate-cmd>`;
`tests/test-proof-negctl.sh` is its five-case test.

Every behavioral proof owes "revert -> RED -> restore", and every session re-derives the same
five steps by hand: mutate a line, run the suite, `git checkout --`, run again. Two hazards
live there (repo memory `commit-before-negative-control`, `negative-control-restore-hazards`):
the restore wipes uncommitted work, and a control that never went red still gets recorded
as PASS. The verb refuses a tree with modified tracked files, runs GREEN -> mutate -> RED ->
restore (on every exit path, via trap) -> GREEN, and prints the `Command:` / `Exit:` /
`Verdict:` block that `check()` already reads. First failure wins, so a no-op mutation is
reported as "changed no tracked file", not as "vacuous".

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Real mutation: GREEN -> RED -> GREEN, PASS block, tree restored | `bash tests/test-proof-negctl.sh` case 1 | ok | PASS |
| 2 | Vacuous mutation (test stays green) is FAIL, exit 1, tree restored | case 2 | ok | PASS |
| 3 | Dirty tracked file is REFUSED before any step, exit 2, file untouched | case 3 | ok | PASS |
| 4 | Mutation that changes nothing tracked is FAIL with its own reason | case 4 | ok | PASS |
| 5 | Usage on missing args, exit 64 | case 5 | ok | PASS |
| 6 | Whole test | `bash tests/test-proof-negctl.sh` | `test-proof-negctl: all 5 passed` | PASS |
| 7 | Dogfood: the verb runs its own negative control | see below | `Verdict: PASS` | PASS |

## Negative control (proof-ledger negctl)

Produced by the verb itself, against its own test, with the dirty-tree refusal disabled as
the mutation:

```
Command: bash tests/test-proof-negctl.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/^    return 2$/    return 0/' lib/gate/proof-ledger.sh && rm -f lib/gate/proof-ledger.sh.bak
Changed: lib/gate/proof-ledger.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout -- lib/gate/proof-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
bash tests/test-proof-negctl.sh
bash lib/gate/proof-ledger.sh negctl "$PWD" "bash tests/test-proof-negctl.sh" \
  "sed -i.bak 's/^    return 2$/    return 0/' lib/gate/proof-ledger.sh && rm -f lib/gate/proof-ledger.sh.bak"
```

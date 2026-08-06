# Verification: delivery-ratio advisory (ADR-0033)

## Acceptance criteria

- `proof-ledger.sh delivery-ratio <root> <base>` splits added lines into real vs proof and prints a verdict.
- THIN-WARN on the hollow signature (real < 40 AND proof >= 3x real); OK on a substantial real change; NOTICE on a docs/proof-only branch.
- Advisory: exits 0 always (never blocks); the ship-gate emits it only on THIN-WARN/NOTICE.
- No regression to the existing gate suites.

## Green run

Command: `bash tests/test-delivery-ratio.sh`
Exit: 0
Output: `=== 8 passed, 0 failed ===` (CASE1 THIN-WARN, CASE2 OK, CASE3 NOTICE, CASE4 documented blind-spot, all exit-0)
Verdict: PASS

Command: `bash tests/test-deployable-done.sh` (no-regression on the sibling gate)
Exit: 0
Output: `=== 17/17 passed, 0 failed ===`
Verdict: PASS

Command: `bash tests/test-hooks.sh` (ship-gate lives here)
Exit: 0
Output: `All tests passed.`
Verdict: PASS

## NEGATIVE CONTROL

Forcing the THIN-WARN verdict to `OK` makes CASE1's THIN-WARN assertion FAIL (the exit-0
assertion still passes, since the function still exits 0 -- it is advisory), so the suite
drops from green to one failure:

```
$ command cp lib/gate/proof-ledger.sh /tmp/pl.bak
$ sed -i.x 's/verdict="THIN-WARN.*/verdict="OK"/' lib/gate/proof-ledger.sh    # break it
$ bash tests/test-delivery-ratio.sh | tail -1
=== 7 passed, 1 failed ===        # RED: CASE1's THIN-WARN grep assertion fails
$ command cp -f /tmp/pl.bak lib/gate/proof-ledger.sh                          # restore
$ bash tests/test-delivery-ratio.sh | tail -1
=== 8 passed, 0 failed ===        # GREEN again
```

Verdict: PASS (the THIN-WARN branch is load-bearing, not a no-op). Note: `command cp`
bypasses the interactive `cp -i` shell alias, which silently declines an overwrite.

## Reproduce

`bash tests/test-delivery-ratio.sh` from the repo root.

# Verification -- gate-awk-escapes-indented-fence

Two gate bugs: the override reuse guard compared a backslash reason through `awk -v` (escapes expanded, guard bypassed), and the review-verdict parser toggled code fences only at column 0 (an indented fence leaked its `Verdict:` lines and blocked a SHIP push).

## Green run
```
Command: bash tests/test-ledger-durability.sh; bash tests/test-gate-ledger-plan-record.sh; bash tests/test-ship-gate-review-verdict.sh
Exit: 0
Output:
=== 54/54 passed, 0 failed ===
=== 70/70 passed ===
pass=60 fail=0
Verdict: PASS
```

## Negative control
```
Command: git checkout master -- lib/gate/gate-ledger.sh lib/gate/ship-rules.sh; then the same three test files (restored with git checkout HEAD -- lib/gate)
Exit: 1
Output:
  FAIL S4: blanket reject works for a backslash reason (awk -v expanded the escapes and let it through)
  FAIL S4: a doubled-backslash reason is also rejected on reuse
  FAIL S5: outcome end derives a duration from the start bracket of a backslash phase
=== 51/54 passed, 3 failed ===
  FAIL RB8 a shared backslash override reason exits 65 (got 1)
  FAIL RB8 the refused backslash batch writes nothing, START included
=== 68/70 passed ===
NOT ok - a verdict in a 3-space indented fence is ignored (want rc=0; got rc=2)
NOT ok - a verdict in a 2-space indented fence is ignored (want rc=0; got rc=2)
NOT ok - a verdict in a 1-space indented tilde fence is ignored (want rc=0; got rc=2)
NOT ok - an indented fence holding SHIP does not clear a real DO NOT SHIP (want rc=2; got rc=0)
pass=56 fail=4
Verdict: RED on the unfixed lib, GREEN on the fix
```
Both lib files were reverted to master for the red run and restored from HEAD after it; `git status` was clean.

## Not proven
- The full suite was not run (diff-scoped by instruction): only the three affected test files.
- Other `awk -v` sites in lib/gate compare internal values only (lane-plan phases, validated rids, fixed constants) and were left unchanged.

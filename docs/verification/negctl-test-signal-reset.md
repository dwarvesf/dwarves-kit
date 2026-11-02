# Verification -- negctl runs every test pass with default INT/TERM/HUP

`restore()` ignores INT/TERM/HUP for good, and the confirmatory post-restore `run_test` inherited that. A suite then could not stop its own background servers with a plain `kill`. dev-port-sweep's suite leaked two `http.server` orphans per negctl run this way. `run_test` now resets the three signals in its subshell.

## Green run
```
Command: bash tests/test-proof-negctl.sh
Exit: 0
Output:
  [56] every test run gets default INT/TERM: restore() ignores them, the post-restore run must not inherit that
    ok: no test run saw INT/TERM ignored
  test-proof-negctl: all 57 passed
Verdict: PASS
```
Case added: (56) a test command logs `trap -p INT TERM` on every negctl pass; the log must hold at least three runs and no ignored (`''`) disposition.

## Negative control
The outer runner is a copy of the fixed `negctl.sh`. The old one would run the post-restore pass with INT ignored and break the suite's own signal-cleanup cases.
```
Command: bash <copy of fixed negctl.sh> "$PWD" "bash tests/test-proof-negctl.sh" "git show origin/master:lib/gate/negctl.sh >| lib/gate/negctl.sh"
Exit: 0
Output:
  Exit: 0 (green before mutation)
    test-proof-negctl: all 57 passed
  Mutation: git show origin/master:lib/gate/negctl.sh >| lib/gate/negctl.sh
  Exit: 1 (under mutation, RED expected)
    test-proof-negctl: 56 passed, 1 FAILED
  Restore: git checkout HEAD -- lib/gate/negctl.sh
  Exit: 0 (green after restore)
  Verdict: PASS
Verdict: PASS
```
Under the mutation only case 56 fails, so the new assertion is the one that catches the old behavior.

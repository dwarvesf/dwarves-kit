# Verification -- land-fixture-cache

`tests/test-wrap-land.sh` builds each land fixture shape once and gives every case its own `cp -R` copy. Same 435 checks, same results.

## Green run
```
Command: bash tests/test-wrap-land.sh
Exit: 0
Verdict: PASS (test-wrap-land: all 435 passed; bash 5.3 and /bin/bash 3.2)
```
```
Command: bash tests/test-wrap-ci.sh && bash tests/test-wrap-merge.sh
Exit: 0
Verdict: PASS (127 passed, 246 passed; both share tests/lib/wrap-stub.sh)
```

## Negative control
Break `lib/wrap/wrap-land.sh` the same way, run the OLD test file (master) and the NEW test file, compare the failing checks.

| Break | Old test file | New test file | Fail sets |
|---|---|---|---|
| `_land_pr_checks_gate` body starts with `return 0` | 10 failed of 435 (PG3, PG4b, PG4c) | 10 failed of 435 (PG3, PG4b, PG4c) | identical |
| `_pr_template` refusal removed (`if [ -n "$tpl" ]` becomes `if false`) | 9 failed of 435 (PG1, PG1b) | 9 failed of 435 (PG1, PG1b) | identical |

```
Command: break wrap-land.sh, then bash tests/test-wrap-land.sh on old and new, diff the FAIL lines
Exit: 1 (both trees, as expected under the break)
Verdict: PASS (the cache hides no failure; fail sets identical for both breaks)
```
`lib/wrap/wrap-land.sh` was restored with `git checkout -- lib/wrap/wrap-land.sh` after each break; `git status` was clean.

## Not proven
- The file does not reach the 40s target. The fixture builds were about a quarter of the run; the rest is `wrap land` itself (about 65 git processes per call).
- Wall times on this machine moved with load from other sessions (load average 9 to 20), so the PR body reports side-by-side runs.

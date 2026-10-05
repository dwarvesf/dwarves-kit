# Verification: flick-7b-verb

`wrap flick-7b` makes step 7b's flick call a command, and `report-lint.sh` fails a wrap report that omits the `flick wrap-7b:` row while the point is enabled.

## Green run
```
Command: bash tests/test-wrap-report-lint.sh; bash tests/test-wrap-flick7b.sh; bash tests/test-flick.sh
Exit: 0
Output:
  test-wrap-report-lint: all 155 passed
  test-wrap-flick7b: all 12 passed
  flick: 339 passed, 0 failed
Verdict: PASS
```

Real primary flow, live Jev, operator config, scratch log dir (`DWARVES_KIT_LOG_DIR`):

```
Command: printf 'backlog-flip-script board enhance\nphoto-resize-helper board new\n' | DWARVES_KIT_LOG_DIR=<scratch> bash bin/wrap flick-7b
Exit: 0
Output:
  flick wrap-7b: 2 answered, 0 denied, 0 error (jev)
  decide.jsonl: backlog-flip-script/board chosen=enhance existing=enhance; photo-resize-helper/board chosen=new existing=new
Verdict: PASS
```

## Negative control
Command: set -o pipefail; bash tests/test-wrap-report-lint.sh 2>&1 | grep -aE 'FAIL|all [0-9]+ passed'
Exit: 0 (green before mutation)
Output:
  test-wrap-report-lint: all 155 passed

Mutation: sed -i.bak "s/! printf '%s' \"\$input\" | grep -qF 'flick wrap-7b:'/false/" lib/wrap/report-lint.sh && rm -f lib/wrap/report-lint.sh.bak
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL flick on, no flick row: the lint fails
    FAIL the finding names the flick row
  test-wrap-report-lint: 153 passed, 2 FAILED of 155

Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS

Command: set -o pipefail; bash tests/test-wrap-flick7b.sh 2>&1 | grep -aE 'FAIL|all [0-9]+ passed'
Exit: 0 (green before mutation)
Output:
  test-wrap-flick7b: all 12 passed

Mutation: sed -i.bak 's/--arg id "p$n"/--arg id "x$n"/' lib/wrap/wrap-flick.sh && rm -f lib/wrap/wrap-flick.sh.bak
Changed: lib/wrap/wrap-flick.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL flick got ONE request holding all three pairs
  test-wrap-flick7b: 11 passed, 1 FAILED of 12

Restore: git checkout HEAD -- lib/wrap/wrap-flick.sh
Exit: 0 (green after restore)
Verdict: PASS

Both mutations restored with `git checkout HEAD --`; both suites green again after the restore. Both new suites were also red before the code existed (lint: 2 FAIL of 155; verb: 12 FAIL of 12).

## Not proven
- Whether the next real wraps run the verb. The lint now makes a skip visible at step 9, but a session can still write a false row by hand. The next real `decide.jsonl` rows are the check.
- The accuracy of the Jev answers (see `flick-shadow-agreement.md`).

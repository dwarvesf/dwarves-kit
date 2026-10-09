# Verification -- run-all-failed

`bash tests/run-all.sh --failed` reruns only the suites whose latest suite-times line has exit != 0 (124 counts), plus the `# always:` lints when something failed; and `agents/fix-agent.md` gains a frozen-evaluator rule.

## Green run
```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
  test-run-all-time                              ok (9s)
  test-run-all-timeout                           ok (5s)
  test-run-all-times                             ok (11s)
  test-run-all-tmpdir                            ok (0s)
  test-test-affected-cache                       ok (7s)
  test-test-affected-parallel                    ok (29s)
  test-test-affected                             ok (32s)
  test-wrap-land                                 ok (145s)
  test-wrap-merge                                ok (94s)
  test-wrap-rebase                               ok (31s)
  
  run-all: slowest:
    145s test-wrap-land
    94s test-wrap-merge
    92s test-config-registry
    88s test-precedent
    32s test-test-affected
    31s test-wrap-rebase
    29s test-test-affected-parallel
    19s test-meta-docs-registry
    11s test-run-all-times
    9s test-run-all-time
  
  run-all: all 24 suites passed, 0 skipped for missing tooling
  (24 suites picked from 7 changed files; test-run-all-times holds the new [12]..[12f] cases, 37 passed, 0 failed)
Verdict: PASS
```

Also run, real history, dogfooding the new verb after a red --changed run: `bash tests/run-all.sh --failed` reran test-meta-docs-registry (the FEATURES.md drift this change caused, fixed in the second commit) plus the five always-on lints, 6 suites, all ok, exit 0.

## Negative control
Command: bash tests/test-run-all-times.sh
Exit: 0 (green before mutation)
Output:
    ok: missing history: one line naming it, nothing run, nothing created
  [12d] --failed adds the always-on lints (as --changed does) only when something failed
    ok: failed suite plus the always-on lint
    ok: nothing failed: the lint does not run alone
  [12e] the rerun is logged, so the next --failed sees the suite green
    ok: gamma failed, was rerun green, and is no longer picked
  [12f] a suite that is still red after the rerun keeps --failed exiting 1
    ok: only the red suite ran, red stays red, exit 1 both times
  
  run-all-times: 37 passed, 0 failed

Mutation: git show 5e63dc1e:tests/run-all.sh > tests/run-all.sh; git show 5e63dc1e:tests/lib/suite-times.sh > tests/lib/suite-times.sh
Changed: tests/lib/suite-times.sh, tests/run-all.sh
Exit: 1 (under mutation, RED expected)
Output:
  test-delta                                     ok
  test-eps                                       ok
  test-gamma                                     ok
  test-lint                                      ok
  
  run-all: all 6 suites passed, 0 skipped for missing tooling
  [12f] a suite that is still red after the rerun keeps --failed exiting 1
    FAIL: rc=1/1
  
  run-all-times: 29 passed, 8 failed

Restore: git checkout HEAD -- tests/lib/suite-times.sh tests/run-all.sh
Exit: 0 (green after restore)
Verdict: PASS

The mutation reverts `tests/run-all.sh` and `tests/lib/suite-times.sh` to the parent commit while the new tests stay. Before the fix the same tests were also red on their own: 8 failures, all in cases [12] to [12f], because an unknown mode fell through to a full run.

## Not proven
- `--failed` against the real nightly history on a loaded host beyond the dogfood run above.
- The fix-agent and greenlight wording is a prose contract; no test pins it, so no negative control applies to it.

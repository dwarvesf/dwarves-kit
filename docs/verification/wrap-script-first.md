# Verification -- wrap-script-first

`/kit:wrap` is script-first: one read-only `wrap session --json` gather now carries the session state the command used to read piecemeal, and the command prose shrank from 414 lines to 141 lines while the landing guarantees stayed pinned by tests.

## Green run

```
Command: bash tests/run-all.sh
Exit: 0
Output:
  test-wrap-rebase                               ok
  test-wrap-report-lint                          ok
  test-wrap-scan                                 ok
  test-wrap-session                              ok
  test-wrap-ship                                 ok
  test-wrap-start                                ok

  run-all: all 51 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Real read-only flow on ops-toolkit:

```
Command: bin/wrap session --json /Users/tieubao/workspace/tieubao/ops-toolkit
Exit: 0
Output:
  {"schema":"wrap-session/1","summary":{"repos":1,"invalid_repos":0,"open_own_prs":1,"pending_prs":0,"sweep_would_remove":0,"sweep_rows":0},"repo":{"path":"/Users/tieubao/workspace/tieubao/ops-toolkit","github_slug":"tieubao/ops-toolkit","default_branch":"main","branch":"main","dirty_count":9,"board_rows":103,"open_own":[{"number":6255,"title":"docs(macos-pool): propose throughput v2 spec","gate":"SKIP draft","url":"https://github.com/tieubao/ops-toolkit/pull/6255"}],"sweep":{"format":"text","exit_code":0}}}
Verdict: PASS
```

## Negative control

```
Command: bash tests/run-all.sh
Exit: 1
Output:
  FAIL step 10 landing step 2 runs wrap rebase first
  FAIL step 10 re-runs the verification after a rebase
  test-wrap-rebase: 102 passed, 2 FAILED of 104
  run-all: FAILED -> test-wrap-rebase
  run-all: 51 suites run, 0 skipped for missing tooling
Verdict: PASS
```

The first full run caught the compressed landing step in the wrong order. The fix restored `bin/wrap rebase <wt>` as landing step 2, `bash tests/test-wrap-rebase.sh` passed all 104 assertions, and the restored tree then passed the full run above.

## Not proven

- The parallel `wrap sweep --json` verb does not exist yet, so the live ops-toolkit gather used the pinned `wrap apply` dry-run text fallback (`sweep.format = "text"`).
- No three-real-`/kit:wrap` timing table was run; this proof covers correctness and gather shape, not a measured operator-time reduction.

## Rollback

Revert this branch. The new gatherer is read-only and writes no state; deleting `lib/wrap/wrap-session.sh`, its dispatch wiring, tests, fixture, and the command rewrite restores the prior wrap flow. No database, config, remote, or deploy state is changed by the new verb.

# Verification -- wrap-help-flag

`wrap log --help` wrote a literal `YYYY-MM-DD · --help` line into the activity log, and `wrap apply --help` (and most other verbs) died with `unknown flag`. Now `wrap <verb> -h|--help` prints that verb's usage and exits 0 for every verb, and `wrap log` refuses any other text starting with `-` (exit 2, nothing written).

## Green run

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
  test-wrap-start                                ok (11s)
  run-all: all 32 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: /bin/bash tests/test-wrap-log.sh && /bin/bash tests/test-wrap-cli.sh
Exit: 0
Output:
  test-wrap-log: all 130 passed
  test-wrap-cli: all 82 passed
Verdict: PASS
```

New cases: `log --help`, `log -h` and `log --date D --help` exit 0, print usage, leave the temp LAB_LOG byte-identical; `-x`, `--bogus`, `--` and `-a dash entry` exit 2 and write nothing; the existing normal-entry cases still write. Every verb answers `--help` and `-h` with exit 0 and a `wrap.sh <verb>` usage line.

## Negative control

Run after the code was committed (`d515c9ba`), each mutation restored by negctl:

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-log.sh" "git show HEAD~1:lib/wrap/wrap-log.sh > lib/wrap/wrap-log.sh; git show HEAD~1:lib/wrap/wrap.sh > lib/wrap/wrap.sh"
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-log: 117 passed, 13 FAILED of 130
  Restore: git checkout HEAD -- lib/wrap/wrap-log.sh lib/wrap/wrap.sh
  Exit: 0 (green after restore)
Verdict: PASS
```

Guard in `wrap-log.sh` alone reverted: `test-wrap-log: 121 passed, 9 FAILED of 130` (the `-x` refusals and `--date D --help`; the dispatcher still catches a bare `--help`). Dispatcher in `wrap.sh` alone reverted, against `tests/test-wrap-cli.sh`: `54 passed, 28 FAILED of 82`. Both restored and green again.

## Not proven
- `_meta/lablog-add` in ops-toolkit is a separate forwarder outside this repo: it passes `--help` through to `wrap log`, now handled here, but its own `--date` parsing is untouched.
- The refusal exits 2 as requested; the other `wrap` usage errors exit 64.

## Rollback
Revert the commit; no state or config changes, `-h`/`--help` handling is read only at the top of `main` and in `cmd_log`.

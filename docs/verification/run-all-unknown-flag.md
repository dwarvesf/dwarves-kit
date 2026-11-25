# Verification -- run-all-unknown-flag

`bash tests/run-all.sh --help` read `--help` as the full glob. It queued on the per-host test lock and started the 25 minute run, past the local `--all` refusal that only matched the literal `--all`. A typo such as `--alll`, a stray extra argument and a bare `--only` did the same.

## Rule

- The argument list is checked before `run_lock_exec` and before any suite starts. `--time` is dropped first (it may sit anywhere); what is left must be one of:

| Form | Accepted when |
|---|---|
| (empty), `--all`, `--failed` | no further argument |
| `--changed [<base>]` | at most one more argument, not starting with `-` |
| `--only <pattern>` | exactly one more argument, not starting with `-` |
| `--times <verb>` | first argument (handled before the check, as before) |
| `--run-one <suite> <dir>` | the internal xargs worker, unchanged |
| `-h`, `--help` | prints the header usage and exits 0 |

- Anything else exits 64 with one usage line on stderr, writes nothing to stdout, takes no lock and runs no suite.
- Judgment: `--help` and `-h` print the usage and exit 0. The closest siblings (`bin/test-affected`, `tests/lib/test-affected-replay.sh`, `tests/lib/suite-times.sh`) all print their header and exit 0 for `--help`; `wrap <verb> --help` does the same. Their unknown-argument exit is 2 (`bin/test-affected`) or 64 (`suite-times.sh`); 64 is what `run-all.sh` already uses for its `--all` refusal.
- Callers audited, none starts failing: `.github/workflows/test.yml` (`--all`), `commands/*.md` and `docs/` (`--changed`, `--changed origin/master`, `--times p95`, `--all`, bare), `tests/test-run-all-*.sh`, `tests/test-suites-collect.sh`, `bin/test-affected` (names the script in comments only, never calls it), `lib/`, `hooks/`, `.github/` (no other call). The flags in use anywhere in the repo are `--changed`, `--only`, `--all`, `--times`, `--failed`, `--time`, `--run-one`; every one is accepted.

## Red run on the unfixed script

The new suite against the previous `tests/run-all.sh`, inside its stub tree (one sentinel suite, a stub lock, a 30 second timeout per call), 23 cases at the time. Every refusal case ran the sentinel suite and asked for the lock; every "still accepted" case stayed green.

```
$ bash tests/test-run-all-unknown-flag.sh   # with tests/run-all.sh as on origin/master; exit status 1
  [1] an unknown or misplaced argument exits 64 with a usage line, before the lock and any suite
    FAIL: '--bogus': rc=0 lock=1 ran=1 out=run-all: 1 suites, 4 at a time, 0 serial
    FAIL: '--alll': rc=0 lock=1 ran=1 out=run-all: 1 suites, 4 at a time, 0 serial
  [2] --all with a stray argument is refused even where --all itself is allowed
    FAIL: --all extra: rc=0 err=.
  [3] --help and -h print the usage header and exit 0, before the lock and any suite
    FAIL: --help: rc=0 lock=1 ran=1 out=run-all: 1 suites, 4 at a time, 0 serial
  test-run-all-unknown-flag: 10 passed, 13 FAILED
```

## Green run

```
Command: bash tests/test-run-all-unknown-flag.sh
Exit: 0
Output:
  [1] an unknown or misplaced argument exits 64 with a usage line, before the lock and any suite
    ok: refused: --bogus
    ok: refused: --alll
    ok: refused: bogus
    ok: refused: --only
    ok: refused: --time --bogus
    ok: refused: --bogus --time
    ok: refused: --changed main extra
    ok: refused: --failed extra
    ok: refused: --time --times p95
    ok: refused: --only a b
    ok: refused: --changed --bogus
    ok: refused: --only --bogus
  [3] --help and -h print the usage header and exit 0, before the lock and any suite
    ok: --help: usage on stdout, exit 0
    ok: -h: usage on stdout, exit 0
  [4] every documented form is still accepted, takes the lock, and runs the suite
    ok: accepted: --only sentinel
    ok: accepted: --all --time (CI=true)
  test-run-all-unknown-flag: all 25 passed
Verdict: PASS
```

The same suite under the stock macOS `/bin/bash` 3.2.57: `test-run-all-unknown-flag: all 25 passed`.

Neighbouring suites, each run on its own against the branch (the merge with origin/master was a no-op, master was 4033e17d):

```
Command: bash tests/test-run-all-changed.sh
Exit: 0
Output:
  test-run-all-changed: all 12 passed
Verdict: PASS
```

```
Command: bash tests/test-run-all-time.sh
Exit: 0
Output:
  test-run-all-time: all 4 passed
Verdict: PASS
```

```
Command: bash tests/test-run-all-timeout.sh
Exit: 0
Output:
  test-run-all-timeout: all 16 passed
Verdict: PASS
```

```
Command: bash tests/test-run-all-times.sh
Exit: 0
Output:
  run-all-times: 37 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-run-all-tmpdir.sh
Exit: 0
Output:
  test-run-all-tmpdir: all 2 passed
Verdict: PASS
```

```
Command: bash tests/test-suites-collect.sh
Exit: 0
Output:
  test-suites-collect: all 12 passed
Verdict: PASS
```

The always-on lints and the meta suites the diff selects (`bin/test-affected --list`): `test-kit-contract` 25 passed, `test-config-registry` 60/60, `test-boundary-lint` 36/36, `test-no-scattered-ids` all 9 passed, `test-no-personal-paths` passed, `test-operator-pin` 4 passed, `test-meta-docs-registry`, `test-meta-plugin-hooks`, `test-meta-vmodel-dispatch` and `test-meta-hard-claims` all passed. `tests/run-all.sh` itself was never run for real: every case above runs a copy in a temp tree.

## NEGATIVE CONTROL

The previous revision of `tests/run-all.sh` put back through `lib/gate/negctl.sh`; the new suite goes RED (15 of 25 cases) and the restore is green. Below is what `negctl.sh` printed, unedited.

## Negative control (negctl)
Command: bash tests/test-run-all-unknown-flag.sh
Exit: 0 (green before mutation)
Output:
    ok: accepted: --only sentinel --time
    ok: accepted: --changed HEAD
    ok: accepted: --changed HEAD --time
    ok: accepted: --time --changed
    ok: accepted: <bare>
    ok: accepted: --all --time (CI=true)
  [5] --failed and --times are not refused as unknown (this tree has no suite-times.sh, so they stop for that reason)
    ok: not refused: --failed (rc=1)
    ok: not refused: --times p95 (rc=127)
  test-run-all-unknown-flag: all 25 passed

Mutation: git show 2513fb42^:tests/run-all.sh > tests/run-all.sh
Changed: tests/run-all.sh
Exit: 1 (under mutation, RED expected)
Output:
    ok: accepted: --only sentinel --time
    ok: accepted: --changed HEAD
    ok: accepted: --changed HEAD --time
    ok: accepted: --time --changed
    ok: accepted: <bare>
    ok: accepted: --all --time (CI=true)
  [5] --failed and --times are not refused as unknown (this tree has no suite-times.sh, so they stop for that reason)
    ok: not refused: --failed (rc=1)
    ok: not refused: --times p95 (rc=127)
  test-run-all-unknown-flag: 10 passed, 15 FAILED

Restore: git checkout HEAD -- tests/run-all.sh
Exit: 0 (green after restore)
Verdict: PASS

Verdict: PASS

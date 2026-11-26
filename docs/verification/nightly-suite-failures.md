# Verification -- nightly-suite-failures

Three roots from the 2026-11-26 nightly at 745f4bd8, fixed on one branch: a hardcoded operator path in `commands/ui-design.md`, a SIGPIPE under `pipefail` in `tests/test-board-work.sh`, and `tests/test-ui-acceptance-verifier.sh` running past run-all's 300s ceiling.

## Green run

Branch, each suite on its own, `TMPDIR` set to a fresh `mktemp -d`:

```
Command: bash tests/test-boundary-lint.sh
Exit: 0
Output:
  === 36/36 passed ===
Verdict: PASS
```

```
Command: bash tests/test-no-personal-paths.sh
Exit: 0
Output:
  ok - no operator path or hostname anywhere in the tree
  Passed: 3 / 3
Verdict: PASS
```

```
Command: bash tests/test-board-work.sh
Exit: 0
Output:
  == board work: 113 passed, 0 failed ==
  ok: GNU-tools pass is green
  == board work: 114 passed, 0 failed ==
Verdict: PASS
```

```
Command: bash tests/test-ui-acceptance-verifier.sh
Exit: 0
Output:
  test-ui-acceptance-verifier: 500 passed, 0 failed, 0 skipped   (178s wall, alone)
Verdict: PASS
```

## Negative control

The same suites on the base commit (8dc6e68d, the branch point, before any edit):

| Suite | Base | Branch |
|-------|------|--------|
| test-boundary-lint | 35/36, the ui-design.md operator path flagged | 36/36 |
| test-no-personal-paths | 2/3, operator path still present at commands/ui-design.md:27 | 3/3 |
| test-board-work | 112 passed, 1 failed, then the GNU-tools pass red (2 failed): `board.sh help lists the verb` | 113 / 114 passed, 0 failed |
| test-ui-acceptance-verifier | green alone but 265s wall (limit 300s, so a loaded host times out) | green, 178s wall |

The SIGPIPE shape, probed 40 times each under `set -o pipefail` against the same producers the suites use:

```
Command: for i in 1..40: bash lib/board/board.sh --help | grep -q 'board.sh work'
Output: 40/40 fail   (producer dies of SIGPIPE when grep -q exits at the first match)
Command: for i in 1..40: grep -q 'board.sh work' <<<"$(bash lib/board/board.sh --help)"
Output: 0/40 fail
```

Class scan: every other `producer | grep -q` in `tests/` whose producer is a kit script, `--help`, `states`, `keys` or `explain` was probed the same way (bin/board work --help, bin/board health run --help, board-sweep --help, mega.sh --help, wrap --help, backlog.sh states, gate-policy.sh keys, role-classify.sh explain): 0/40 fail each, so none changes. Many other sites already wrap the producer in `{ trap '' PIPE; ...; }` or capture first.

## The ui-acceptance suite

Not a hang. Alone it passes in about 265s at the old `STEP_MS=6000`; the time is the cost of FAIL rows, because a failing step waits out its whole step limit on every one of three attempts and three viewports (gaps of 6 to 42s before each exit-1 case in a timestamped run). `STEP_MS` is now 3000, which cuts the wall time by about a third. The global run-all timeout is unchanged.

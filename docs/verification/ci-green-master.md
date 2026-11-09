# Verification -- ci-green-master

Six suites went red on the 2026-11-09 dispatch of `test.yml`. Five are test-host assumptions, one is a browser startup wait in `lib/system-design/shots.mjs`. Each row: the cause, the commit that added it, the reproduction, the green run.

## Causes

| Suite | Cause | Added by | Reproduced |
|-------|-------|----------|------------|
| test-mktemp-template-guard | five `mktemp -d` assignments without `\|\| exit 1` | #1102 (command-words), #1111 (vps-report) | yes, locally, same list |
| test-board-states | `SourceFileLoader.load_module()` is gone in Python 3.15 | #1101 | yes, Python 3.15 |
| test-board-registry-env | R5 needs a `hermes` binary on PATH; a runner has none | #1111 | yes, PATH without hermes |
| test-clean-room | `gh` in `/usr/bin` writes `device-id` under XDG state in the sandbox HOME | #1115 | yes, gh linked into the sandbox PATH |
| test-doc-figures | a cold browser start gets 15 s, and the timer outlives a good start | #1088 moved Chrome first on the runner | partly: a 20 s slow-start wrapper fails the same way; the runner log is not available |
| test-board-brief | `grep -c '\`t1\`'` is a start-of-buffer anchor in GNU grep | #1092 | no: no GNU grep or Docker egress on this host |

## Green run

```
Command: for t in board-registry-env mktemp-template-guard board-states doc-figures clean-room board-brief; do bash tests/test-$t.sh; done
Exit: 0
Output:
  test-board-registry-env: all 13 passed
  === 11 passed, 0 failed ===
  All board-states tests passed.
  doc-figures: 50 passed, 0 failed (50 checks)
  clean-room: 75 passed, 0 failed
  board-brief: 243 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output:
  run-all: --changed against c903819f: 8 changed files -> 16 suites
  run-all: all 16 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control (each fix reverted to its parent, then restored)

```
Command: git checkout HEAD~1 -- <file>; run the suite; git checkout HEAD -- <file>
Exit: 1
Output:
  mktemp guard, files reverted:    FAIL violations: ... 10 passed, 1 failed
  board-states on Python 3.15:     FAIL python readers disagree: Traceback (most recent call last):
  registry-env, PATH sans hermes:  FAIL R5 falls back to the repo default
  clean-room, gh on sandbox PATH:  FAIL after the full run: nothing written under the sandbox outside the allowed dirs
  doc-figures, 20 s browser start: FAIL render exits 0 on a one-sheet model; doc-figures: build or shots failed
Verdict: PASS (every reverted fix fails; the fixed tree passes)
```

Not controlled: board-brief fails only under GNU grep, which this host lacks.

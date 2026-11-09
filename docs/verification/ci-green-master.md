# Verification -- ci-green-master

Six suites went red on the 2026-11-09 dispatch of `test.yml`. Five are test-host assumptions, one is a browser startup wait in `lib/system-design/shots.mjs`. Each row: the cause, the commit that added it, the reproduction, the green run.

## Causes

| Suite | Cause | Added by | Reproduced |
|-------|-------|----------|------------|
| test-mktemp-template-guard | five `mktemp -d` assignments without `\|\| exit 1` | #1102 (command-words), #1111 (vps-report) | yes, locally, same list |
| test-board-states | `SourceFileLoader.load_module()` is gone in Python 3.15 | #1101 | yes, Python 3.15 |
| test-board-registry-env | R5 needs a `hermes` binary on PATH; a runner has none | #1111 | yes, PATH without hermes |
| test-clean-room | `gh` in `/usr/bin` writes `device-id` under XDG state in the sandbox HOME | #1115 | yes, gh linked into the sandbox PATH |
| test-doc-figures | the render succeeded, then `stopBrowser` removed the browser profile while Chrome helper processes still wrote into it: `rmSync` threw ENOTEMPTY and the render exited 1 (read off the runner log from the diagnostics commit). The 15 s start timer that was never cleared is a separate stall, also fixed | #1088 | yes: a wrapper that keeps writing into the profile fails 4 of 4 before the fix |
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
  doc-figures, profile writer:     FAIL render survives a browser helper writing into the profile on exit (4 of 4)
Verdict: PASS (every reverted fix fails; the fixed tree passes)
```

Not controlled: board-brief fails only under GNU grep, which this host lacks.

## Not a cause found

test-spec-reserve T20 failed once on Ubuntu (both worktree reserves printed nothing and wrote no ledger) and passed on every other run, the master run and two later dispatches included. It could not be reproduced in 350 local iterations, under CPU load too. The test now prints git, worktree and reserve stderr on lines run-all surfaces if it fails again, and pins the operator config and XDG dirs.

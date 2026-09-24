# Verification: full-lane implementation-notes rule (SPEC-311)

`hooks/ship-gate.sh` refuses a `full`-lane push in an adopted repo unless `docs/implementation-notes/<slug>.md` or `SPEC-NNN-<slug>.md` is committed in `HEAD` with a line beyond its title. The zero-deviation line passes; `override <slug> impl-notes` clears the gap; an unadopted repo gets an advisory.

Headless hook change: the capture is the text output below.

## Green run

| Check | Command | Exit | Output |
|---|---|---|---|
| New suite | `bash tests/test-ship-gate-impl-notes.sh` | 0 | `PASS=16 FAIL=0` (AC1 to AC14) |
| Ship-gate suites | `for t in $(rg -l 'ship-gate' tests/test-*.sh); do bash "$t"; done` | 0 each | 22 of 22 ok |
| Changed suites | `RUN_ALL_TIMEOUT_SECS=600 bash tests/run-all.sh --changed` | 1 | 39 run, 38 ok; `test-advisor` red on `commands/mega.md` wording, same on `origin/master` (the phrase count there is 0), untouched here |
| Structural | `bash tests/test-meta.sh` | 0 | green after `docs/FEATURES.md` regen |
| Codex trust pins | `bash tests/test-codex-hooks.sh` | 0 | green after `bash lib/codex/repin.sh` |

## Real run

The hook, fed a push command on stdin, run against this branch in its own worktree (`CLAUDE_PLUGIN_ROOT` = the worktree), before and after the notes file was committed:

| Case | Exit | Output |
|---|---|---|
| Notes not committed, gates partly recorded | 2 | one BLOCKED message: five `MISSING-GATE` lines plus `MISSING-NOTES: docs/implementation-notes/impl-notes-gate.md or docs/implementation-notes/SPEC-311-impl-notes-gate.md`, then the zero-deviation line and the `impl-notes` override hint |
| Notes committed (5663312) | 2 | the proof-of-done gate blocks first (this file not yet written); no `MISSING-NOTES` line |

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-impl-notes.sh" "git show origin/master:hooks/ship-gate.sh > hooks/ship-gate.sh"
Exit: 0 (green before mutation)
Mutation: git show origin/master:hooks/ship-gate.sh > hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Test plan coverage

| Row | Run / skip reason |
|---|---|
| 1 | new suite case 1 |
| 2 | new suite cases 2, 2b |
| 3 | new suite case 3 |
| 4 | new suite case 4 |
| 5 | new suite case 5 |
| 6 | new suite case 6 |
| 7 | new suite case 7 |
| 8 | new suite case 8 |
| 9 | ship-gate suite loop, 22 of 22 ok |
| 10 | new suite cases 10a, 10b, 10c |
| 11 | new suite case 11 |
| 12 | new suite case 12 |
| 13 | new suite case 13 |
| 14 | new suite case 14 |

## Gates

| Phase | Verdict |
|---|---|
| Validate | two fresh reviewer agents, six lenses: NEEDS REVISION (4 critical, 14 warnings), all folded into SPEC-311 or listed out of scope |
| Design record | design-bearing, pass |
| Review | fresh `kit:code-reviewer`, three lenses: 0 blocking, 1 warning (a `#Title` with no space counts as content), 2 nits |

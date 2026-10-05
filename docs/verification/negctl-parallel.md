# Verification -- negctl-parallel

`lib/gate/negctl.sh --parallel <N> [--slot-env VAR=start:step]... <root> <test-cmd> <mutate-cmd>...` runs one negative control per mutation, N at a time. Each control runs in its own `git worktree add --detach` copy of HEAD under `$TMPDIR/negctl-par.*`, removed on exit and on interrupt. Serial mode is the default and is unchanged, except that a second `<mutate-cmd>` without `--parallel` is now a usage error instead of being ignored.

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | `--parallel 3` and `--parallel 1` print exactly what three serial runs print, in control order | `tests/test-proof-negctl.sh` case 39 | PASS |
| AC2 | each concurrent slot gets its own `--slot-env` value (`start + slot * step`, base 10), and the slots really run at once | case 40 (three controls rendezvous; a serial run would see 1) | PASS |
| AC3 | `--parallel 2` over 3 controls uses only two slot values | case 41 | PASS |
| AC4 | a failing control still reports: FAIL named, others PASS, order kept, exit 1 | case 42 | PASS |
| AC5 | no copy or worktree registration survives a finished run or a REFUSED run | case 43 | PASS |
| AC6 | an interrupted run removes every copy, kills the suites, leaves the live tree clean | case 45 | PASS |
| AC7 | misuse exits 64 before anything runs | case 44 | PASS |
| AC8 | wall time drops with N | timing below | 10.4s to 3.7s |

## Green run
```
Command: bash tests/test-proof-negctl.sh
Exit: 0
[39] --parallel 3 prints what three serial controls print, in control order, tree clean
  ok: parallel 3 and parallel 1 output equals the serial blocks, 3 PASS, live tree clean
[40] --slot-env hands each concurrent slot its own value, and the slots really run at once
  ok: slots 100/110/120 (step applied, OTHER=7 base 10), all three met at the rendezvous
[41] --parallel 2 over 3 controls never exceeds 2 slot values
  ok: two workers, values 100 and 110, three PASS blocks
[42] a failing control still reports in parallel: FAIL named, the others PASS, order kept, exit 1
  ok: one FAIL, two PASS with RED under mutation, blocks in control order, exit 1
[43] no throwaway copy survives a finished run, a refused run, or a worktree registration
  ok: temp dir gone and worktree registry back to one entry after both runs
[44] --parallel usage: zero or non-numeric N, a bad --slot-env, --slot-env alone, extra controls without --parallel, --at, --base-ref all exit 64
  ok: all eight misuses exit 64 before anything runs
[45] an interrupted --parallel run removes every copy, kills the suites, leaves the live tree clean
  ok: copies existed mid-run; after SIGINT none remain, no suite outlived it, worktree registry clean
test-proof-negctl: all 46 passed
```
The new cases were written first and ran red against the old script (7 FAILED of 46). The suite also passes under macOS `/bin/bash` 3.2.57. `bash tests/test-meta.sh` 902/902; `feature-registry.sh check docs/FEATURES.md` fresh.

## Wall time
Fixture: three controls, a suite that sleeps 1s per run (each control runs it three times). Three timed runs each.

| Mode | Wall time |
|------|-----------|
| three serial `negctl.sh` runs | 10.52s, 10.27s, 10.46s |
| `negctl.sh --parallel 3` | 3.71s, 3.59s, 3.71s |

## Negative control
Mechanised with the new mode on itself: `negctl.sh --parallel 3 <root> "bash tests/test-proof-negctl.sh" <6 mutations>` at the feature commit (118s for all six; the tree was clean afterwards). Every control went RED under its mutation and GREEN after restore.

| Mutation | Suite result under it |
|----------|-----------------------|
| workers launched in the foreground (no concurrency) | 5 FAILED |
| `--slot-env` export removed | 2 FAILED |
| copy cleanup disabled (`case "" in`) | 3 FAILED |
| blocks printed in reverse order | 2 FAILED |
| aggregate exit forced to 0 | 1 FAILED |
| interrupt no longer kills the worker groups | 1 FAILED (suite outlives the SIGINT) |

```
Verdict: PASS
```
x6, one per mutation.

## Not proven
- A real port-binding suite: the fixture reads `SLOT_PORT` from the env and records it. `dwarvesf/share` was not run; the documented `--slot-env SHARE_TEST_PORT_BASE=18787:10010` is the caller's mapping and the kit knows no variable name.
- Linux and a repo with submodules or a custom `core.hooksPath`: the copies are made with hooks off, but only macOS was run.
- Untracked and ignored files are not in a copy (a suite needing `node_modules` needs it committed or set up by the test-cmd).
- Static assignment: worker k takes controls k, k+N, ...; one long control can leave another worker idle.

Verdict: PASS

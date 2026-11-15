# Verification -- converge-stale-base

The same-file cross-wave guard in `_wave_converge` now measures each landed branch against the branch the sub-goal PRs merge into (origin's default branch, via `_kit_mc_base_ref`, after a quiet best-effort fetch), not the run worktree's HEAD. In a real run the worktree branch never advances while PRs squash-merge into main, so every sub-goal branch looked like it had changed all of main's intervening files and two disjoint branches "overlapped" on the inherited ones. With no remote ref the base stays the run worktree's HEAD.

## Green run

The suite builds a bare origin, a work clone parked on `chore/run` at the first commit, advances origin/main by three commits touching shared files, and cuts two sub-goal branches from the advanced main. The disjoint case must report no overlap; the control (both branches add `common.txt`) must flag exactly that one file.

```
Command: bash tests/test-wave-converge.sh
Exit: 0
Output:
  PASS ROADMAP line unchanged after a dry run
  PASS stale run branch, disjoint sub-goals: no overlap (rc 0)
  PASS same-file edit still flagged: only common.txt (rc 1)
  ---
  All wave-converge tests passed.
Verdict: PASS
```

Neighbouring suites and the regression run over every suite the diff touches:

```
Command: bash tests/test-wave-rolling.sh; bash tests/test-orchestrate.sh; bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
  PASS (j3) WAVE_CAP=3: one landing refilled two slots in one pass, SG-05 waited for a free slot, peak 3 sessions
  all passed
  PASS status: an Orca run still takes the Orca status path
  ALL PASS
  run-all: all 39 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

The new suite run against the pre-fix `lib/queue/orchestrate.sh` (`git show HEAD:lib/queue/orchestrate.sh` swapped in, then the fixed file restored and the suite re-run green, see above):

```
Command: bash tests/test-wave-converge.sh   (orchestrate.sh = pre-fix revision)
Exit: 2 (RED expected)
Output:
  FAIL stale run branch, disjoint sub-goals: rc=1 out='[orchestrate] [converge] SAME-FILE cross-wave edit detected across the landed wave; REFUSING to merge (...). Overlapping file(s):     shared1.txt     shared2.txt     shared3.txt'
  FAIL same-file control: rc=1 files='common.txt shared1.txt shared2.txt shared3.txt '
  ---
  2 failed.
Verdict: RED on the old code, GREEN restored
```

Reproduce: `git show origin/master:lib/queue/orchestrate.sh >| lib/queue/orchestrate.sh && bash tests/test-wave-converge.sh`, then `git checkout -- lib/queue/orchestrate.sh`.

## Not proven

- A live `git fetch` against a real GitHub remote; the test uses a local bare origin. The fetch is best effort and never fails the run.
- A stale `origin/HEAD` naming a renamed default branch: `_kit_mc_base_ref` reads `origin/HEAD`, then `origin/main`, then `origin/master`, with no `gh` call.

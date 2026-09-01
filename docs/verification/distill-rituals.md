# Proof of done: two session rituals distilled into committed scripts

Distilled from one session that ran the same two sequences by hand repeatedly: the worktree start/close ritual (5 starts, 7 closes, same traps each time) and the unattended campaign-pass loop (ran twice from a session scratchpad, so it was lost between sessions). Both are now committed, Tier-1 clean, and reachable.

## `lib/goal/wt.sh` (also `goal.sh wt <start|close>`)

Recorded run, `start` (dogfooded: this very branch was created by it):

```
Command: bash lib/goal/wt.sh start distill-rituals normal chore
Exit: 0
Verdict: PASS   # .claude/worktrees/distill-rituals on chore/distill-rituals off origin/master, gate-ledger START recorded; main checkout untouched
```

NEGATIVE CONTROL, `close` must refuse an unmerged branch (never deletes unmerged work):

```
Command: bash lib/goal/wt.sh close distill-rituals chore      (before this PR merged)
Exit: 1
Output: wt.sh: refusing to close: PR for chore/distill-rituals is 'none', not MERGED
Verdict: PASS
```

The positive `close` run is this branch's own close-out after merge (release registry, remove worktree, delete local+remote branch, fast-forward main with the BACKLOG stash dance); its output is the ship record in the PR.

## `tests/gauntlet/deploy/campaign-pass`

```
Command: KIT_ROOT=$PWD bash tests/gauntlet/deploy/campaign-pass --dry-run
Exit: 0
Output: dry-run: would run tests/gauntlet/deploy/gauntlet-campaign (probe: runner default) ... CAMPAIGN-LOOP-DONE
Verdict: PASS   # plumbing proven; probe resolves to the Tier-1 runner default when PROBE_CMD is unset (SPEC-239 distribution honesty)
```

Live runs: this is the loop, minus the operator-exported probe recipe, that produced the two committed campaign records (`docs/verification/gauntlet/2026-09-01-onboarding-campaign/` 10/11 and `-2/` 11/11 SOLID). The committed script adds the host-side git fence from the A/B security review (HIGH-1) to the per-row scoring step, which the scratch loop lacked.

NEGATIVE CONTROL: with no `campaign-current` symlink and `--dry-run`, the loop still terminates at the tick cap (no unbounded loop); a probe-written `BLOCKED.md` writes `PAUSED` and stops (exercised live in the pass-1 contract, `tests/gauntlet/deploy/gauntlet-campaign` honors the marker).

Rollback: additive (two scripts, one forwarder line, one README block); `git revert`.

## Reproduce

```
bash lib/goal/wt.sh --help
KIT_ROOT=<kit> bash tests/gauntlet/deploy/campaign-pass --dry-run
```

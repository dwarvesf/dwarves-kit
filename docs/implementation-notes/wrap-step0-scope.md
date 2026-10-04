# Implementation notes -- wrap-step0-scope

Deltas from `docs/specs/SPEC-383-wrap-step0-scope.md`. Nothing here repeats what the spec already states.

## The stray-line carry is skipped in `_carry_stray`, not suppressed per autoland site

- Context: the first build kept the carry under a stop and guarded `_autoland_on` against `--no-pull`. Code review found the carry still pushes another live session's dirty lines.
- Decision/Change: `_carry_stray` prints `SKIP stray lines: --no-pull (N lines in <file> stay local)` and never calls `_carry_stray_file`. The `_autoland_on` guard was removed as dead code.
- Why: the push itself is the problem, not only the merge. One skip at the loop covers the dry run and `--apply`.
- Impact: nothing reaches origin from a stopped wrap; the next unstopped wrap carries the lines.

## `merge --no-pull` skips at the loop and at `--pr`, because `--pr` readies a draft first

- Context: `--pr <n>` marks a draft ready before the eligibility loop runs, so a loop-only skip would still call `gh pr ready` on a main-held draft.
- Decision/Change: `_main_holds_branch` is checked in the `--pr` block (before the draft step, returns 0) and again in the loop (covers the bare `--apply` and the CONFLICTING re-merge).
- Why: NC6 mutates the `--pr` check alone and the draft case goes red; NC5 mutates the loop check alone.
- Impact: a main-held PR of any state, named or not, is skipped by name and stays `OPEN`.

## `--no-pull` without `--own` skips both local sweeps

- The review asked for the all-branches sweep only. The worktree sweep under `--worktrees` has the same reach (other sessions' merged worktrees), so both skip by name.

## The index check needs a stat-dirty file to discriminate

- `git diff HEAD` only rewrites the index when an entry's stat info is stale. The carry test touches a tracked file to an old mtime so NC8 (the `diff-index` change reverted) goes red; without the touch the check was vacuous.

## The `--no-pull` merge cases live in their own suite

- The signal-timing case in `tests/test-wrap-merge.sh` ("TERM inside a scratch-worktree cycle") failed after restore under negctl in four of four runs, though it passes standalone. The `--no-pull` cases moved to `tests/test-wrap-merge-nopull.sh` (17 cases, about 3 seconds) so NC5 and NC6 are stable. The flaky case is pre-existing and untouched.

## Round 2 warnings the build absorbed instead of the spec

- The `index.lock` limit reads "every local removal" in `commands/wrap.md`: `_apply_origin_branches` and the carry have no `_write_guard`, so they still run under a held lock. Both write no checkout state.
- AC7's many literals became one assertion each in `tests/test-wrap-deploy.sh`, so a red test names the sentence that drifted.
- NC1 and NC2 mutate two different `NO_PULL` gates, told apart by the preceding line (`echo "-- pull:"` versus the 4-space `-- stray commits:` block), each with an exact-once match guard in the mutator.
- The pre-existing assertion that greps `STOP every write to that repo's MAIN CHECKOUT` stays: the new stop bullet keeps that literal, and the 7b isolated-worktree literal is unchanged.

## Known residue

- Rejected review point: the `--no-pull` name understates the stray-commits push it also skips; the skip is named in the verb's own lines.
- Validate round 2 ended NEEDS REVISION with its three criticals folded; no third round ran. The gate ledger holds a logged override for `validate`.

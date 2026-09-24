# SPEC-312: wrap apply carries stray commits off a shared default branch

**Status:** VALIDATED (the change lands in the same PR)
Lane: normal
Type: spec-feature
**Proof:** `tests/test-wrap.sh`, the stray-commits block; `docs/verification/wrap-stray-commit-carry.md`.

## Problem

`wrap apply` carries STRAY LINES: dirty `merge=union` files on a shared main
checkout go onto a `wrap/stray-<file>-<stamp>` branch. It does not carry a
STRAY COMMIT. Another session commits directly on the shared checkout's
default branch and never pushes. The checkout is then `ahead=N`, and every
later `pull --ff-only` fails with "diverging branches". Four wraps in a row
reported `PULL BLOCKED` for this reason, and each time the operator drained
the commit by hand: branch at the sha, push, PR, merge, `git reset --keep`.

## Contract

- The step runs in `apply`, after the stray-lines step and before the pull.
  It runs only on the main checkout, only when that checkout is on the default
  branch, and only after a successful fetch. It prints under `-- stray commits:`.
- Ahead is `git rev-list --count origin/<def>..HEAD`. Zero prints `none`.
- Knob: `wrap.carry_stray_lines`, resolved with `kit_config_get_root`. `false`
  prints `N stray commits on <def> stay local (wrap.carry_stray_lines=false)`
  and writes nothing.
- Dry run: `WOULD carry N stray commits on <def> onto a branch:`, one
  `<short sha> <subject>` line per commit, then either
  `WOULD move <def> back to origin/<def>` or
  `<def> would stay ahead: dirty tracked files block the move: <files>`.
- `--apply`: `git branch wrap/stray-commits-<YYYYMMDD-HHMM> HEAD`, push it,
  print `carried N stray commits on <def> to origin/<branch>` and
  `open its PR with: gh pr create --head <branch>`. No PR opens, nothing merges.
- An origin `wrap/stray-commits-*` branch that already holds HEAD is reused:
  `origin/<branch> already carries the N stray commits on <def>`, no new push.
- A failed branch create or push prints `FAILED carry N stray commits on <def>
  to <branch>: ...`, sets exit 2, skips the move, and the pull still runs.
- The move runs only when every dirty tracked file (`git diff HEAD`) is
  `merge=union`, the pushed branch's origin tip holds HEAD, and HEAD did not
  move during the step. It is `git reset --keep <fork>`, never `--hard`, where
  `<fork>` is `git merge-base HEAD origin/<def>`. It prints
  `moved <def> back to origin/<def>; the N commits live on <branch>` when the
  fork is origin's tip, else
  `moved <def> back to <fork sha>, where it left origin/<def>; ...`.
  The pull then fast-forwards to origin/<def>.
- A dirty non-union tracked file prints `<def> left ahead: dirty tracked files
  block the move: <files>`. The branch is still pushed.
- `reset --keep` refusing (a dirty file the stray commits change) prints
  `<def> left ahead: git reset --keep refused: <git's first line>`. The
  working copy is untouched, and the pull fails as it did before.

## Design record

The brief named `git reset --keep origin/<def>`. The target became the fork
point. `--keep` refuses any dirty file that differs between HEAD and the
target. Origin changes the union-marked board and log on nearly every merge,
and those files are the ones a shared checkout keeps dirty. A reset straight to
origin's tip would therefore refuse in the common case. The fork point moves
away only the stray commits, and the pull's existing union carry takes the
checkout the rest of the way. When origin has not moved, the fork IS origin's
tip and the printed line is the brief's.

The local branch of the same name stays. It is a second reference to the
commits, and the local branch sweep deletes it once it merges.

A dirty union file that the stray commits themselves change is left to git's
refusal. Saving it aside, resetting, and restoring it would keep the bytes,
but the commit's lines would then show as dirty lines, and the next wrap's
stray-lines step would carry them a second time.

The existing non-ff test ("never reset the local default branch") now runs
with the knob off. The same guarantee holds there. With the knob on, the move
is this feature, and it happens only after origin holds the commits.

## Test plan

| Case | Expected |
|---|---|
| origin advanced, one local commit, dirty union log, dry run | WOULD lines with sha and subject, origin and HEAD unchanged |
| same, `--apply` | branch on origin at the commit, local branch too, move reported, pull lands on origin/main, union line kept, committed file gone |
| rerun after the move | `none` |
| origin unmoved, `--apply` | the brief's exact `moved main back to origin/main` line |
| dirty non-union file | dry run and apply name the block, branch pushed, main unmoved, file untouched |
| rerun once the tree is clean | existing branch reused, one branch on origin, main moved |
| dirty union file the commits change | `reset --keep refused`, main unmoved, working copy byte-identical |
| knob false | count line, no branch on origin or locally, main unmoved |
| push refused by a pre-receive hook | `FAILED`, exit 2, main unmoved, pull step still runs |

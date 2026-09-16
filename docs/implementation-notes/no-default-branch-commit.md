# Implementation notes: no-default-branch-commit

Delta from `docs/specs/SPEC-291-no-default-branch-commit.md`. The spec was written from the
built code, so there is no deviation to record; these are the open decisions the board row left
and the follow-ups the change does not close.

## 2026-09-16 10:00 Warn, not a housekeeping branch

Context: the row offered two shapes, warn-and-leave-uncommitted or auto-create a housekeeping
branch.

Decision: warn.

Why: the verbs already do the right thing. They write a file and stop. Creating a branch would
add a git write to a checkout other sessions share, during a pass that is already merging PRs
and removing worktrees, to solve a problem one stderr line solves. The measured failure was
never a missing branch; it was a model that did not know the commit was unpushable.

Alternatives: a refusal (loses the write the session asked for), a config key to pick the
behavior (a key nobody would ever flip).

Impact: the guard can be ignored. A session that commits anyway is no worse off than before.

Open questions: none.

## 2026-09-16 10:05 A separate default-branch resolver

Context: `lib/wrap/wrap.sh` already carries `_default_branch`, used by four merge gates.

Decision: `lib/gate/default-branch-warn.sh` carries its own `kit_default_branch_here`.

Why: the guard needs a fallback the gates must not have. A repo with no remote at all still has
a default branch for this purpose, its local `main` or `master`. Teaching `_default_branch` that
fallback would change how `scan`, `apply` and `merge` treat a remoteless repo, which this
warning does not justify. The duplicate body is eight lines.

Impact: two resolvers with different contracts in one repo. The guard's own comment says which
is which and why.

## 2026-09-16 10:10 `board dedupe-all` is guarded after all

Context: `backlog.sh` has three write paths. The first draft guarded `set_state` and `dedupe`
only, on the reasoning that `wrap apply`'s union re-merge is `dedupe_all`'s caller and is
already committing the merge it just resolved.

Decision: reversed after review. All three warn.

Why: `main` dispatches `dedupe-all`, so it is a hand-runnable CLI verb too, and a sweep run on
the default branch produced exactly the write this guard exists to flag. One extra stderr line
during a re-merge costs less than a silent hole in a three-verb surface.

## 2026-09-16 10:12 Every git read drops GIT_DIR and GIT_WORK_TREE

Context: review found that `git -C <dir>` changes directory without clearing an inherited
`GIT_DIR` or `GIT_WORK_TREE`.

Decision: route every git read in the guard through `_kdbw_git`, which runs `env -u GIT_DIR
-u GIT_WORK_TREE git -C "$dir"`.

Why: a verb invoked from inside a git hook would otherwise resolve HEAD and the remote refs
against the hook's repo, not the written file's, and the warning would be silently wrong in
either direction. No test binds this: constructing a git-hook invocation for a warning-only
path costs more than the three-line fix.

## 2026-09-16 10:15 Follow-ups this change does not close

The knowledge-flush skill named by the `wrap.after` seam lives in the operator's dotfiles, not
in this repo, and `lib/gate/boundary-lint.sh` forbids naming it in `commands/*.md`. Its prose
still says nothing about the default branch. Follow-up in the dotfiles repo.

The two companion guards the board row names belong to other repos: an ops-toolkit pre-commit
hook refusing commits on the default branch, and a dotfiles `pull.ff=only`. Neither is built
here.

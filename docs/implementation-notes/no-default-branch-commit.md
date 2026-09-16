# Implementation notes: no-default-branch-commit

Delta from `docs/specs/SPEC-289-no-default-branch-commit.md`. The spec was written from the
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

## 2026-09-16 10:10 `board dedupe-all` is not guarded

Context: `backlog.sh` has three write paths.

Decision: `set_state` and `dedupe` warn; `dedupe_all` does not.

Why: only `wrap apply`'s union re-merge calls `dedupe_all`, inside a flow that is already
committing the merge conflict it just resolved. A warning there fires on every union re-merge
and means nothing.

## 2026-09-16 10:15 Follow-ups this change does not close

The knowledge-flush skill named by the `wrap.after` seam lives in the operator's dotfiles, not
in this repo, and `lib/gate/boundary-lint.sh` forbids naming it in `commands/*.md`. Its prose
still says nothing about the default branch. Follow-up in the dotfiles repo.

The two companion guards the board row names belong to other repos: an ops-toolkit pre-commit
hook refusing commits on the default branch, and a dotfiles `pull.ff=only`. Neither is built
here.

# SPEC-291: the kit's in-checkout write verbs warn instead of letting a session commit on the default branch

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Board:** ID-879. **Proof:** `docs/verification/no-default-branch-commit.md`.

## Problem

Three kit verbs write a file inside a git checkout and leave the commit to the caller: `wrap
log` writes the activity line, `wrap stage` writes a staging block, `board set` flips a backlog
row. `commands/wrap.md` step 2 says the same thing in prose: wrap owns no commit write, the
commit is a command-layer judgment call.

The model makes that call, and it makes it in whatever checkout the session runs in. That is
usually the repo's main checkout, which sits on the default branch. A commit there cannot reach
a PR, because nobody pushes the default branch directly. So the commits stay. One Air carried 29
such commits plus 61 merge commits by 2026-09-14 before an operator drained them by hand.

The writes themselves are correct. Only the commit is wrong, and nothing in the system said so.

## Decision

Add one shared guard, `kit_warn_default_branch <written-path> [<label>]` in
`lib/gate/default-branch-warn.sh`. Every verb that writes a file into a checkout calls it after
the write lands. The guard prints one line to stderr and always returns 0:

```
<label>: wrote <file> on the default branch (<branch>); do not commit it here, leave it for the
next feature PR or move it to a branch
```

**Warn, never refuse.** The file is what the session asked for and the next feature PR carries
it fine. Refusing the write would lose the line; auto-creating a housekeeping branch would take
a git write the caller never asked for, in a checkout other sessions share, at the exact moment
`wrap` is already juggling merges and worktrees. The smallest thing that closes the hole is
telling the caller the one fact it lacks.

### Call sites

| Verb | Written file | Label |
|---|---|---|
| `wrap log` | the resolved `wrap.activity_log` target, worktree copy included | `wrap log` |
| `wrap stage` | `_meta/backlog-staging.md` or its env override | `wrap stage` |
| `board set` | the `BACKLOG.md` named by `BACKLOG_FILE` | `board set` |
| `board dedupe` | the same file, when it actually collapsed rows | `board dedupe` |
| `board dedupe-all` | the same file, when the sweep collapsed anything | `board dedupe-all` |

`dedupe-all` was left silent in the first draft because `wrap apply`'s union re-merge is its
main caller, inside a flow that is already committing the merge it just resolved. Review found
it is also a hand-runnable CLI verb, so a sweep on the default branch produced exactly the
uncommittable write this guard exists to flag. One extra stderr line during a re-merge is the
smaller cost.

### When the guard stays silent

| Condition | Why |
|---|---|
| The path lies outside any git repo | no branch, no commit, nothing to warn about |
| HEAD is detached | no branch name to compare |
| The checked-out branch is not the default one | this is the shape the rule asks for |
| No default branch resolves | the guard never guesses |

An inherited `GIT_DIR` or `GIT_WORK_TREE` would make `git -C` read a different repo than the
written file's, so every git read drops both names through `env -u`.

### Resolving the default branch

`origin/HEAD` first, then `refs/remotes/origin/main`, then `refs/remotes/origin/master`. A repo
with NO remote configured at all falls back to a local `main` or `master`, which is the shape a
fresh `git init` checkout carries and the one case no remote ref can answer. The remote decides:
a session on a local `main` in a repo whose `origin/HEAD` says `master` gets no warning.

The guard carries its own resolver rather than reusing `wrap.sh`'s `_default_branch`. Four merge
gates depend on that function, and it has no local-branch fallback. Widening it would change
what those gates do on a remoteless repo, which this warning does not justify.

## Prose

`commands/wrap.md` step 2 now states the rule the model must follow: never commit on a checkout
that has the default branch checked out, leave the file for the next feature PR or move it to a
branch. Step 6 and the `wrap.after` seam paragraph point back at step 2.

## Out of scope

The knowledge-flush skill the `wrap.after` seam names lives in the operator's dotfiles, not in
this repo, so its own prose is a follow-up for that repo. The kit's boundary lint forbids naming
it here, which is why step 2 states the rule for every seam skill instead.

The two companion guards the board row names, an ops-toolkit pre-commit hook refusing commits on
main and a dotfiles `pull.ff=only`, belong to those repos and are not built here.

## Verification

```bash
bash tests/test-wrap.sh
bash tests/test-board-set-note.sh
bash tests/run-all.sh
```

| Criterion | Check |
|---|---|
| `wrap log` on the default branch writes the line AND warns | test-wrap: "log on the default branch warns" + "still wrote the line" |
| `wrap log` on a feature branch writes the line and stays silent | test-wrap: "log on a feature branch does not warn" |
| The remote, not the local name, decides the default | test-wrap: "a local main is not the default when origin says master" |
| `wrap stage` warns on the default branch, not on a feature branch | test-wrap: the two stage cases |
| `board set` flips the row AND warns on the default branch | test-board-set-note case 12 |
| `board set` on a feature branch stays silent | test-board-set-note case 14 |
| Outside a git repo nothing warns | test-board-set-note cases 1 to 11, whose boards live in a plain temp dir |

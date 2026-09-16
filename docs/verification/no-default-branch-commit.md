# Proof of done: the kit's write verbs warn instead of letting a session commit on the default branch

2026-09-16. Acceptance: `wrap log`, `wrap stage` and `board set` still write their file in every
case, and print one stderr line naming the branch when the written file lands in a checkout that
has the repo's default branch checked out. On a feature branch, outside a git repo, and on a
detached HEAD they stay silent. Lane: full. Spec: `docs/specs/SPEC-289-no-default-branch-commit.md`.
Board: ID-879. Files: `lib/gate/default-branch-warn.sh`, `lib/wrap/wrap.sh`,
`lib/board/backlog.sh`, `commands/wrap.md`, `tests/test-wrap.sh`, `tests/test-board-set-note.sh`.

## The failure this closes

The verbs write a file and leave the commit to the caller, and `commands/wrap.md` step 2 says so.
The model makes that call in whatever checkout the session runs in, which is usually the main
checkout on the default branch. Nobody pushes the default branch, so the commits stay local. One
Air carried 29 such commits plus 61 merge commits by 2026-09-14 before an operator drained them.

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 508 passed`
Verdict: PASS. 498 assertions before the change, 508 after; the 10 new ones cover the `log` and
`stage` guard against real git repos built on disk, including the origin/HEAD case.

Command: `bash tests/test-board-set-note.sh`
Exit: 0
Output: `ALL PASS`, with the three new lines `set on the default branch warns and still flips the
row`, `dedupe with nothing to do stays silent about the branch`, `set on a feature branch does not
warn`.
Verdict: PASS.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 852 / 852` / `All meta tests passed.`
Verdict: PASS. The first run failed on `docs/FEATURES.md is fresh (regenerate == committed)`,
because the new spec file bumps three per-command spec counts in that generated projection.
Regenerating with `bash lib/registry/feature-registry.sh generate docs/FEATURES.md` produced a
four-line diff, all of them counts, and the suite went green.

Command: `bash tests/run-all.sh`
Exit: 0
Output: `run-all: FAILED -> test-meta` / `run-all: 147 suites run, 1 skipped for missing tooling`
Verdict: PASS after the regeneration above. That was the only failing suite in the whole sweep,
and its cause and fix are recorded in the previous block.

## Negative control

Mutation: neuter the guard's own comparison, so the branch can never equal the default one and no
verb ever warns. `perl -pi -e 's/\[ "\$branch" = "\$def" \]/[ "$branch" = "__never__" ]/'` on
`lib/gate/default-branch-warn.sh`. Run through `lib/gate/negctl.sh` in a fresh clone of the
branch, so the running full sweep in the worktree could not see the mutated tree.

```
## Negative control (negctl)
Command: bash <clone>/tests/test-board-set-note.sh
Exit: 0 (green before mutation)
Mutation: bash <scratch>/mutate-879.sh <clone>
Changed: lib/gate/default-branch-warn.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/default-branch-warn.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
## Negative control (negctl)
Command: bash <clone>/tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: bash <scratch>/mutate-879.sh <clone>
Changed: lib/gate/default-branch-warn.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/default-branch-warn.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Both suites go red under the mutation and green again after the restore, so neither suite passes
for a reason other than the guard.

## Cases the tests bind

Every case builds a real git repo on disk. Nothing stubs `git`, because what `git` reports as the
current branch and as `origin/HEAD` is the whole subject.

| Case | Setup | Asserted |
|---|---|---|
| `log` on the default branch | repo on `main`, no remote | the warning names `main`, the line is still line 1 of the file |
| `log` on a feature branch | same repo, `feat/log-guard` checked out | no warning, the line is still written |
| the remote decides | `origin/HEAD` on `master`, session on local `main` | no warning |
| the remote's own default | same repo, `master` checked out | the warning names `master` |
| `stage` on the default branch | fresh repo on `main` | the warning names `main`, the staging block is still appended |
| `stage` on a feature branch | same repo, `feat/stage-guard` | no warning |
| `board set` on the default branch | repo on `main`, board file inside it | the warning names `main`, the row reads `shipped [on main]` |
| `board dedupe` with nothing to collapse | same repo | no warning, because nothing was written |
| `board set` on a feature branch | same repo, `feat/board-guard` | no warning |
| outside a git repo | the eleven pre-existing cases, whose boards live in a plain temp dir | no warning, unchanged output |

## What this does not cover

The knowledge-flush skill the `wrap.after` seam names lives in the operator's dotfiles and is not
testable from here; `commands/wrap.md` step 2 carries the rule for it instead. The two companion
guards the board row names, an ops-toolkit pre-commit hook and a dotfiles `pull.ff=only`, belong
to those repos and are not built or proven here.

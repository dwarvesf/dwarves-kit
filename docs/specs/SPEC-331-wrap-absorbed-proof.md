# SPEC-331: wrap accepts absorbed content as a merge proof

**Status:** VALIDATED with a scope cut (revision 5, after four NEEDS REVISION rounds; the fourth's remaining findings are pre-existing ref resolution in the older proofs, moved to a follow-up)
Lane: full
Type: spec-feature / behavioral
**Proof:** `docs/verification/wrap-absorbed-proof.md`; `tests/test-wrap.sh`, the `absorbed proof` section.

## Problem

`wrap apply` deletes a branch, and removes a worktree that holds it, only under a merge proof. It knows two: the branch is an ancestor of `origin/<default>`, or `gh` shows a squash merge whose head is the branch tip (`_merge_proof`, `_apply_branches` in `lib/wrap/wrap.sh`).

A subagent started with `Agent(isolation: "worktree")` commits on its own `worktree-agent-<id>` branch. When the lead re-commits that work under its own PR (a cherry-pick, a squash, a hand copy), the branch keeps commits with new hashes and never gets a PR of its own. Neither proof can ever hold for it, so every later `wrap apply` prints `not proven merged` and the worktree stays forever.

Measured on 2026-09-27: one ops-toolkit checkout held 24 worktrees, 20 of them `agent-*`. The lead had re-committed their content under other PRs. Two of them change no file relative to `origin/main` at all; the rest landed and were then edited further on `origin/main`.

## Picture

```
            merge base
               |
   origin/main o---o---o   (lead re-committed the agent's change)
               \
  agent branch  o---o       (same change, new hashes, no PR)

  changed = paths(merge base -> agent tip)
  differ  = paths(agent tip  -> origin/main)
  ABSORBED  <=>  changed is not empty AND changed ∩ differ is empty
```

## Design

obvious: one read-only helper beside the two existing proofs. The one real choice, tree identity instead of a trial merge, is recorded in Contract 1 and in `docs/implementation-notes/wrap-absorbed-proof.md`.

## Contract

1. A new helper, `_absorbed <repo> <default> <commit>`, exits 0 exactly when the branch changed at least one path since its merge base with `refs/remotes/origin/<default>`, and every one of those paths is byte-identical at the commit and on `origin/<default>`: same blob id and mode, or absent on both. It uses plain tree diffs (`git --no-replace-objects diff --name-only --no-relative --no-renames --ignore-submodules=none`), so no `.gitattributes` merge driver runs and no object is written. It never runs a trial merge: `merge-tree` honours merge drivers, and a keep-ours or `merge=union` driver returns the default branch's side while the branch's edit exists nowhere else.
2. The proof guarantees the branch's net change is on the default branch, which is the same guarantee the gh squash proof gives. Content the branch's own intermediate commits added and later removed is on no ref after the delete. `branch -D` prints the tip sha, so those commits stay recoverable until gc.
3. `_merge_proof` checks the proofs in this order: ancestor, absorbed, gh squash. An absorbed branch prints `content already on origin/<default>`. The worktree sweep's existing guards all still run after the proof: dirty re-check, tip-moved re-check, lock handling, path-gone confirmation.
4. `_apply_branches` deletes an absorbed branch with the verdict `delete <b> (content already on origin/<default>)`, after the ancestor check and before the gh check, behind the same fetch-ok and tip-moved guards. It passes the tip sha it already read.
5. `scan` reports an absorbed branch as `[ABSORBED: content already on origin/<default>, safe to -D]`, so scan and apply agree. Scan and the worktree sweep pass `refs/heads/<b>` to the absorbed proof, and the worktree sweep's ancestor proof now checks `refs/heads/<b>` too. The squash proof, the tip re-reads, and every proof's `origin/<default>` still resolve loosely: a same-named tag or local branch can stand in. That is pre-existing and out of this spec's scope; see Out of scope.
6. The proof needs no `gh`. With `gh` absent or unauthenticated, an absorbed branch is still proven.
7. The two git diffs fail closed (`|| return 1`); after them nothing can fail. The comparison is pure bash string matching with no pipe, file, descriptor, or subprocess, so no failure outside the two git calls can read as disjoint. Every git call in the helper runs with `--no-replace-objects`. `--no-relative` stops `diff.relative` with a subdirectory `<repo>` from dropping paths.
8. The branch stays `NOT merged / unknown: LEAVE` in each of these cases: the content landed only in part; the default branch edited one of the branch's files after landing it, even in another hunk; a merge driver would hide the difference.

## Out of scope

- The conflict case (content landed, then evolved on the default branch). No mechanical proof separates "landed then edited" from "never landed, touched the same file", so it stays a manual call.
- Removing worktrees outside the repos a wrap pass names.
- Pinning `refs/remotes/origin/<default>` and `refs/heads/<b>` across the older ancestor and squash proofs, their tip reads, and scan's SAFE-d line. Round 4 reproduced a tag or local branch named `origin/<default>`, and a tag-shadowed squash proof, deleting unlanded work on master's code. A follow-up change owns it.

## Test plan

| # | Case | Expected |
|---|---|---|
| 1 | Branch whose change the default branch re-committed, plus a later unrelated commit on the default branch | scan `ABSORBED`, dry run `WOULD remove worktree ... (content already on origin/main)`, apply removes the worktree and deletes the branch |
| 2 | Partial landing: one of two new files on the default branch | `LEAVE`, branch kept |
| 3 | Content landed, then the default branch edited the same lines | `LEAVE`, branch kept |
| 4 | Absorbed branch with no worktree | branch sweep deletes it and names the proof |
| 5 | Cases 1 to 4 with `gh` unauthenticated | same results |
| 6 | Keep-ours merge driver on the branch's file | `LEAVE`, branch kept |
| 7 | `merge=union` file where the branch deleted a line | `LEAVE`, branch kept |
| 8 | Content landed, then the default branch edited another hunk of the same file | `LEAVE`, branch kept |
| 9 | Tag on the default branch named like an unlanded branch | no absorbed verdict for the branch |
| 10 | Every pre-existing `test-wrap.sh` case | unchanged |
| 11 | Negative control: `_absorbed` forced to exit 1 | the suite goes red |
| 12 | Default branch diff past 64 KB with the unlanded branch's path sorting first | `LEAVE`, branch kept |
| 13 | Branch path that is not valid UTF-8, `core.quotePath=false` | `LEAVE`, branch kept |
| 14 | `diff.relative=true`, wrap pointed at a subdirectory, unlanded top-level path | `LEAVE`, branch kept |
| 15 | Landed path that is not valid UTF-8 | `ABSORBED` |
| 16 | Tag on the default branch named like an unlanded worktree branch | neither proof fires; worktree and branch survive apply |
| 17 | Helper run with 7 file descriptors under `/bin/bash` 3.2 and PATH bash | `LEAVE` |

## Tasks

- [x] TASK-001: `_absorbed` helper, wired into `_merge_proof`, `_apply_branches`, and the `scan` verdict; `commands/wrap.md` step 5 names the three proofs; `docs/CHANGELOG.md` entry.
- [x] TASK-002: `tests/test-wrap.sh` absorbed section covering test plan rows 1 to 9 and 12 to 17.

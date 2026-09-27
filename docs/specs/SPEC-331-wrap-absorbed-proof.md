# SPEC-331: wrap accepts absorbed content as a merge proof

**Status:** DRAFT (revision 2, after a NEEDS REVISION validation)
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

1. A new helper, `_absorbed <repo> <default> <commit>`, exits 0 exactly when the branch changed at least one path since its merge base with `refs/remotes/origin/<default>`, and every one of those paths is byte-identical at the commit and on `origin/<default>`: same blob id and mode, or absent on both. It uses plain tree diffs (`git diff --name-only --no-renames --ignore-submodules=none`), so no `.gitattributes` merge driver runs and no object is written. It never runs a trial merge: `merge-tree` honours merge drivers, and a keep-ours or `merge=union` driver returns the default branch's side while the branch's edit exists nowhere else.
2. The proof guarantees the branch's net change is on the default branch, which is the same guarantee the gh squash proof gives. Content the branch's own intermediate commits added and later removed is on no ref after the delete. `branch -D` prints the tip sha, so those commits stay recoverable until gc.
3. `_merge_proof` checks the proofs in this order: ancestor, absorbed, gh squash. An absorbed branch prints `content already on origin/<default>`. The worktree sweep's existing guards all still run after the proof: dirty re-check, tip-moved re-check, lock handling, path-gone confirmation.
4. `_apply_branches` deletes an absorbed branch with the verdict `delete <b> (content already on origin/<default>)`, after the ancestor check and before the gh check, behind the same fetch-ok and tip-moved guards. It passes the tip sha it already read.
5. `scan` reports an absorbed branch as `[ABSORBED: content already on origin/<default>, safe to -D]`, so scan and apply agree. Scan and the worktree sweep pass `refs/heads/<b>`, so a tag named like the branch cannot stand in for it.
6. The proof needs no `gh`. With `gh` absent or unauthenticated, an absorbed branch is still proven.
7. The branch stays `NOT merged / unknown: LEAVE` in each of these cases: the content landed only in part; the default branch edited one of the branch's files after landing it, even in another hunk; a merge driver would hide the difference.

## Out of scope

- The conflict case (content landed, then evolved on the default branch). No mechanical proof separates "landed then edited" from "never landed, touched the same file", so it stays a manual call.
- Removing worktrees outside the repos a wrap pass names.

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

## Tasks

- [x] TASK-001: `_absorbed` helper, wired into `_merge_proof`, `_apply_branches`, and the `scan` verdict; `commands/wrap.md` step 5 names the three proofs; `docs/CHANGELOG.md` entry.
- [x] TASK-002: `tests/test-wrap.sh` absorbed section covering test plan rows 1 to 9.

# SPEC-331: wrap accepts absorbed content as a merge proof

**Status:** DRAFT
Lane: full
Type: spec-feature / behavioral
**Proof:** `docs/verification/wrap-absorbed-proof.md`; `tests/test-wrap.sh`, the `absorbed proof` section.

## Problem

`wrap apply` deletes a branch, and removes a worktree that holds it, only under a merge proof. It knows two: the branch is an ancestor of `origin/<default>`, or `gh` shows a squash merge whose head is the branch tip (`_merge_proof`, `_apply_branches` in `lib/wrap/wrap.sh`).

A subagent started with `Agent(isolation: "worktree")` commits on its own `worktree-agent-<id>` branch. When the lead re-commits that work under its own PR (a cherry-pick, a squash, a hand copy), the branch keeps commits with new hashes and never gets a PR of its own. Neither proof can ever hold for it, so every later `wrap apply` prints `not proven merged` and the worktree stays forever.

Measured on 2026-09-27: one ops-toolkit checkout held 24 worktrees, 20 of them `agent-*`. Four of those branches merged into `origin/main` with no change at all; the lead had re-committed their content under other PRs.

## Contract

1. A new helper, `_absorbed <repo> <default> <branch>`, exits 0 exactly when `git merge-tree --write-tree origin/<default> <branch>` exits 0 (a clean merge) and prints a tree id equal to `origin/<default>^{tree}`. Any other outcome exits 1: a conflict, a merge that adds anything, a git older than 2.38 (no `--write-tree`), or an unresolvable ref.
2. The identity means every change the branch carries relative to its merge base is already on the default branch. Deleting the branch loses commit metadata (messages, hashes), never file content.
3. `_merge_proof` checks the proofs in this order: ancestor, absorbed, gh squash. An absorbed branch prints `content already on origin/<default>`. The worktree sweep's existing guards all still run after the proof: dirty re-check, tip-moved re-check, lock handling, path-gone confirmation.
4. `_apply_branches` deletes an absorbed branch with the verdict `delete <b> (content already on origin/<default>)`, after the ancestor check and before the gh check, behind the same fetch-ok and tip-moved guards that precede it.
5. `scan` reports an absorbed branch as `[ABSORBED: content already on origin/<default>, safe to -D]`, so scan and apply agree.
6. The proof needs no `gh`. With `gh` absent or unauthenticated, an absorbed branch is still proven.
7. A branch whose content landed only in part, or whose files the default branch edited since (a conflict), stays `NOT merged / unknown: LEAVE`.

## Out of scope

- The conflict case (content landed, then evolved on the default branch). No mechanical proof separates "landed then edited" from "never landed, touched the same file", so it stays a manual call.
- Removing worktrees outside the repos a wrap pass names.

## Test plan

| # | Case | Expected |
|---|---|---|
| 1 | Branch whose change the default branch re-committed, plus a later unrelated commit on the default branch | scan `ABSORBED`, dry run `WOULD remove worktree ... (content already on origin/main)`, apply removes the worktree and deletes the branch |
| 2 | Partial landing: one of two new files on the default branch | `LEAVE`, branch kept |
| 3 | Content landed, then the default branch edited the same file | `LEAVE`, branch kept |
| 4 | Absorbed branch with no worktree | branch sweep deletes it and names the proof |
| 5 | Cases 1 to 4 with `gh` unauthenticated | same results |
| 6 | Every pre-existing `test-wrap.sh` case | unchanged |
| 7 | Negative control: `_absorbed` forced to exit 1 | the suite goes red |

## Tasks

- [x] TASK-001: `_absorbed` helper, wired into `_merge_proof`, `_apply_branches`, and the `scan` verdict; `commands/wrap.md` step 5 names the three proofs; `docs/CHANGELOG.md` entry.
- [x] TASK-002: `tests/test-wrap.sh` absorbed section covering test plan rows 1 to 5.

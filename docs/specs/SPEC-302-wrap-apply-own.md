# SPEC-302: wrap apply --own tidies only the named worktrees

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
**Board:** ID-923. **Proof:** `tests/test-wrap.sh`, the SPEC-302 block.

## Problem

`wrap.sh apply --worktrees` sweeps every proven-merged worktree in the repo.
On a repo shared by several live sessions that removes OTHER sessions'
finished worktrees mid-task, so a careful session cannot use it; on
2026-09-17 a wrap pass hand-wrote a tidy script twice instead. The missing
piece is scope: remove only the worktrees the caller names, with every guard
the full sweep already applies.

## Contract

- `wrap.sh apply [--apply] --own <path> [--own <path>]... <repo>` restricts
  the worktree step to the named paths. `--own` implies worktree scope for
  the named set, so `--worktrees` is not required; passing both is legal and
  the own set still wins.
- Paths canonicalise through `cd <path> && pwd -P`, the same normalisation
  the sweep applies to registered worktrees, so `wt/` and `wt` and
  `/abs/wt` name the same entry.
- A named path that is not a registered worktree prints
  `     SKIP <path>: not a registered worktree` — a typo is never silent.
- Every existing guard applies unchanged to a named worktree: dirty,
  detached, protected branch, the main checkout's branch, stale proof,
  unproven merged, tip moved mid-run, locked by a live pid, index.lock.
  A named dirty worktree is refused exactly like an unnamed one.
- With `--own`, the all-branches sweep (`-- branches:`) is skipped and says
  so: the session's branches are deleted by the worktree step itself, and
  other sessions' branches are out of scope.
- The pull step is unchanged (it updates the local default checkout, not
  another session's artifact).

## Design record

Scope is a candidate-set restriction, not a parallel code path: the named
worktree flows through the same guards, the same re-read-before-force, the
same `_wt_cleared` postcondition as any swept entry, so the safety model has
exactly one implementation to hold. Skipping the branch sweep keeps the
flag's promise literal (only the named worktrees and their branches);
deleting a merged branch that another session still wants is the same
failure class the row reports for worktrees.

## Test plan

| Case | Expected |
|---|---|
| `--own wt-a` on a repo with wt-a + wt-b | wt-a WOULD/removed, wt-b untouched (no WOULD line) |
| `--own` implies worktree scope | works without `--worktrees` |
| named dirty worktree | SKIP dirty, nothing removed |
| named path not a worktree | `SKIP <path>: not a registered worktree` |
| no `--own` | existing sweep behaviour byte-identical |
| branch sweep under `--own` | skipped with a scope note |

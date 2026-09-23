# Implementation notes -- wrap-merge-settle

Deltas from SPEC-306. Nothing here repeats what the spec already states.

## 2026-09-23 The origin-only branch case was the real gap, not the fallback refusal
- Context: the triggering session saw `does not contain origin/main; the conflict is not the carried-base case` on a branch that merged cleanly under the union driver.
- Decision/Change: the squash-equivalent fallback keeps its refusal. The normal re-merge path, which refused because no local checkout held the branch, now re-merges an origin-only branch in a temporary worktree that wrap removes afterwards. The abort and duplicate-row cleanup rules are unchanged.
- Why: the fallback rebuilds a squash only when the branch already carries the default branch. For any other branch it would invent a merge the author never made.
- Impact: a branch left only on origin (its worktree removed after a wrap) now gets the same union re-merge a local branch gets.

## 2026-09-23 Four review fixes, one known gap
- Context: an Opus review of the first cut found nothing blocking.
- Decision/Change: a failed duplicate-row cleanup now stops the push. A failed temp-dir creation is caught. A `git worktree prune` that could clear other worktrees' records was removed. A failed PR read keeps the settle wait going instead of ending it.
- Alternatives considered: a signal trap to remove the temporary worktree on interrupt (skipped: an interrupted run leaves at most one stale worktree record, which `git worktree prune` by hand clears).
- Impact: the interrupt case is the one path that can leave residue.

## 2026-09-23 Two existing tests changed shape
- #17 (review gate refuses after the push) used a placeholder head `cc`. It now uses the real pushed head, so the new head-match check does not refuse it first and the case still tests the review gate.
- #55 (fallback refusal) now dirties the checkout instead of deleting the branch, because a deleted branch now takes the new origin-only re-merge path and would no longer reach the refusal.

## 2026-09-23 Proof limits and an open question
- The live-GitHub run the proof contract asks for is recorded as unavailable: proving it needs a throwaway PR merged on a real repo. Tests run real git with `gh` stubbed.
- Settling covers mergeability only, not CI. A repo whose checks restart on the pushed head still reports checks pending on that call; a second `wrap merge` lands it. Open question for the operator: extend the wait to checks, or keep the second call as the contract.
- No kit board row was filed for this branch; the ship-gate prints an advisory about it.

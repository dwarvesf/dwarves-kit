# Implementation notes -- wrap-land-merged-pr

Deltas from SPEC-376. Nothing here repeats what the spec already states.

## 2026-09-30 Citations rewritten onto the wrap modules
- Context: the spec was written against the `wrap.sh` monolith. `origin/master` since split it into `lib/wrap/wrap-<module>.sh` (#853) and added the CONFLICTING-PR merge cycle to `land` (#854).
- Decision/Change: every line citation now names its module at pre-change numbers: `cmd_land` and the tail in `wrap-land.sh`, `_merge_proof`/`_absorbed`/`_apply_worktrees`/`_wt_lock_live` in `wrap-apply.sh`, `_autoland_carry` in `wrap-carry.sh`, `_squash_json`/`_squash_verdict` in `wrap-common.sh`. Test citations moved to `tests/test-wrap-land.sh` and `tests/lib/wrap-stub.sh`. No design decision changed, DEC-9 (no Agent-lock guard) included.
- Why: stale numbers would send a reviewer to the wrong lines.
- Impact: docs only.

## 2026-09-30 TASK-1's tip/url move is a no-op
- Context: the spec moves `tip` and `url` above the branch point so the shared tail never reads them unset.
- Decision/Change: in the modular `cmd_land` they already sit at `wrap-land.sh:131-133`, after the `ahead` refusal and before the open-PR lookup where the proof call now goes. Nothing moves; the spec text says so.
- Why: the branch point is after those lines, so the property the spec wants holds without an edit.
- Impact: smaller diff than TASK-1 describes.

## 2026-09-30 The tail has no "already gone" read today
- Context: the spec calls `_land_tidy`'s absence check "as today's tail does, now refined".
- Decision/Change: the tail today runs the leased origin delete unconditionally and prints `FAILED delete` when GitHub already auto-deleted the ref. There is no `ls-remote` read to refine. TASK-2b adds the read (`--exit-code`, only exit 2 means gone) instead. The spec text now says "add".
- Why: matches the spec's intended behavior (TB1, TB2, TD1) with the code that exists.
- Impact: the unchanged merge path gains one `ls-remote` call and a new `already gone from origin` line when the ref is absent.

## 2026-09-30 Sibling branch merged during the build
- Context: `feat/wrap-pull-only` was the spec's one named sibling.
- Decision/Change: it merged as #857 while this branch was open; the second `origin/master` merge was clean. The Siblings row now says so and drops the rebase ordering rule.
- Why: nothing remains to order against.
- Impact: docs only.

## 2026-09-30 The removal recheck compares against the tidy's entry state, not "empty"
- Context: the spec says `_land_tidy` re-reads `git status --porcelain` right before `worktree remove -f -f` and requires it to be empty.
- Decision/Change: `_land_tidy` records the porcelain output on entry and the recheck requires it unchanged, plus the tip equal to the passed `$tip`. The first recheck in `cmd_land`, right after the proof, still requires an empty tree.
- Why: the existing merge-cycle case "a merge that un-ignores an operator file" ends with an untracked file the merge just un-ignored. Land removed that worktree before this build, and an "empty" recheck would refuse it. A write made after entry still trips the comparison.
- Impact: same protection against writes during the origin delete and the pull; no new refusal for the merge cycle's leftover file.

## 2026-09-30 One existing test shim shifted by two git calls
- Context: the pre-merge signal case in `tests/test-wrap-land.sh` kills land at the 2nd `git merge-base` call.
- Decision/Change: the trigger moved to the 4th call. The landed-branch proof adds two `merge-base` reads (ancestor and absorbed) ahead of the merge cycle on every land whose fetch succeeds.
- Why: the case pins "before the merge ran", and the count is the only handle the shim has.
- Impact: none beyond the number.

## 2026-09-30 Test-plan deltas
- TC5 uses an unpushed branch, not TC1's pushed shape: with a pushed branch, "origin never received the branch" cannot tell the old push-first order from the new one.
- TD5 fetches origin into the clone before the shim fails the next fetch, so the cached `origin/main` already holds the squash. Without that, the absorbed proof would not fire either way and the row would prove nothing.
- Added TA3 (a tag named `origin/main` cannot fake a zero `ahead`, the full-refs fix), TG1 (tip moves during the pull, the tidy's recheck refuses) and TG2 (tree dirtied during the proof read, the first recheck refuses). TA2 runs `cmd_land` from a sourced shell with `_merge_proof` overridden to return an ancestor proof.
- `tests/lib/wrap-stub.sh` gains `GH_STUB_MERGE_DELETES_BRANCH=1`: the merge stub deletes the head ref on the remote, standing in for GitHub's delete-branch-on-merge (TB1, TB2).

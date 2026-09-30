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

## 2026-09-30 Sibling branch row kept, reframed
- Context: `feat/wrap-pull-only` is still open; its hunks were measured on the monolith.
- Decision/Change: the Siblings row notes #853 moved those hunks into other modules and that this spec touches only `wrap-land.sh` and `test-wrap-land.sh`. Overlap analysis was not redone.
- Why: the new files share nothing with that branch's modules.
- Impact: none for this build.

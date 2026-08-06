# Implementation notes: co-located + table-first proof (ADR-0026)

Kit-side (Phase A) of ops-toolkit SPEC-016. Upstreams two additions to the canonical
verification convention, additively, so existing consumers (dfoundation, trading) keep working.

## 2026-06-09 11:50 , branch in-place, not a worktree
- Context: the always-worktree policy. I was already inside an ops-toolkit worktree session;
  `EnterWorktree` is single-repo + non-nestable, and hand `git worktree add` is forbidden by policy.
- Decision: branched dwarves-kit in-place (`docs/colocated-proof`) on its clean checkout.
- Why: no native way to nest a worktree into a second repo from within another repo's worktree;
  this is a doc-only, single-writer, sequential change on a clean tree.
- Impact: the unrelated `M docs/ABSORPTION.md` in the kit checkout is left untouched/unstaged.

## 2026-06-09 11:50 , additive, not a replacement
- Context: the canonical README is the single source of truth across all consumer repos.
- Decision: ADR-0026 + README changes are ADDITIVE. Co-located `tools/<name>/docs/proof-of-done.md`
  is promoted from "back-compat" to a blessed first-class shape for tool work; the table-first
  review layout is added as an OPTIONAL presentation; the existing `docs/verification/<slug>/{test-design,runs}`
  layout and the flat shape stay fully valid. Gate markers (`Command:`/`Exit:`/`NEGATIVE CONTROL`/
  `rollback`) are unchanged, so no consumer's existing proofs break.
- Why: dfoundation + trading have existing proofs in the current shapes; a breaking change would
  invalidate them. Additive keeps the gate green everywhere.
- Alternatives: replace the layout (rejected, breaks consumers); ops-toolkit-only fork (rejected by
  the user, would drift from the kit worked examples).

## 2026-06-09 11:50 , the filename constraint is the load-bearing fact
- Context: why co-location must use the name `proof-of-done.md`.
- Decision: documented in the README that the gate's co-located path is ONLY a file named
  `proof-of-done.md` (the regex `(^|/)proof-of-done\.md$` in `lib/gate/proof-ledger.sh`); a co-located
  `runs/` dir is invisible to the gate.
- Impact: the table-first proof MUST keep the literal markers in its run-detail section.

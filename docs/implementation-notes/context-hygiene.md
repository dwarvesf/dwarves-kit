# Implementation notes: SPEC-087 inter-sub-goal context hygiene (design)

Delta-only notes for the design sub-goal (token-hygiene SG-03). The design itself is in
SPEC-087 + ADR-0027; this records off-spec authoring decisions.

## 2026-06-29 v2: design re-centered on a non-LLM orchestrator (operator review)

- Context: Han reviewed the v1 design (distilled returns + operator checkpoint signal) and
  rejected the operator-signal half: a human-performed `/clear` defeats the kit's unattended
  automation premise.
- Change: SPEC-087 + ADR-0027 rewritten to make a **non-LLM orchestrator** (Mechanism A) the
  primary fix, with a **feed-forward grounded handoff** (Mechanism B) replacing the operator
  signal, and distilled returns demoted to phase-2 Mechanism C. The load-bearing call
  (DEC-004): the loop driver must be dumb code, not an LLM session, or it re-accumulates and
  becomes the new marathon.
- Impl choice: phase-1 implementation is bash `lib/orchestrate.sh` driving `claude -p`
  (matches the existing lib/ drivers; Agent SDK is the upgrade path). The `claude` binary is
  injected via `CLAUDE_CMD` so the test mocks it and the operator tunes the permission flags.
- PR split: the spec/ADR revision rides the SG-03 design PR (#80); the orchestrator code is a
  stacked SG-04 PR off this branch.

## 2026-06-29 Numbering: skipped SPEC-086 to avoid an in-flight collision
- Context: master's highest SPEC is SPEC-085; next free is 086. But the active
  `feat/proof-visual-evidence` branch already claims `SPEC-086-stop-hook-scan-cost.md`
  (uncommitted on that branch).
- Decision: used **SPEC-087** so this design does not collide when that branch merges.
  ADR-0027 has no such conflict (master highest is 0026, the feature branch adds no ADR).
- Impact: a one-number gap on master until 086 lands; harmless.

## 2026-06-29 Isolated worktree created off origin/master by hand
- Context: the native EnterWorktree tool operates on the session's current repo (ops-toolkit);
  it cannot create a worktree in a second repo. The kit checkout had 9 uncommitted files on
  `feat/proof-visual-evidence` that must not be disturbed.
- Decision: created `.claude/worktrees/context-hygiene` off `origin/master` via `git worktree
  add` at the sanctioned path. Reversible; cleaned up after the gate PR is opened.

## 2026-06-29 Lane = normal; design-only, no kit code
- Decision: SPEC declares `Lane: normal`. The diff is markdown-only (SPEC + ADR), which the
  proof-gate classifies inert, so no proof-of-done is owed. Gate-ledger recorded for the
  normal lane so the kit ship-gate does not block the push.

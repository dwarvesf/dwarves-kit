# Implementation notes: lib/orchestrate.sh (SPEC-087 phase 1, SG-04)

Delta-only. Design is in SPEC-087 + ADR-0027; this records impl decisions not in the spec.

## 2026-06-29 Scope: phase 1 = orchestrator + handoff (Mechanism A + B); C deferred
- The spec's Mechanism C (distilled subagent-return contract in `agents/*.md`) is phase 2,
  not in this PR. This PR ships the structural fix (the non-LLM driver + feed-forward handoff)
  + its test, keeping the diff focused/reviewable. The before/after `token-forensic --loops`
  measurement (SPEC-087 phase-2 metric) lands with C.

## 2026-06-29 `CLAUDE_CMD` injection for mockability
- The real session spawn is `$CLAUDE_CMD -p "<prompt>"` (default `claude`). The test injects a
  mock so the suite never spawns a real (expensive) session. The real `claude -p` permission
  flags are SPEC-087 OQ-001, left to the operator (not hardcoded), so the kit does not bake in
  a permission posture.

## 2026-06-29 Grounded completion via ROADMAP box-flip
- The orchestrator advances only when the just-run sub-goal's ROADMAP checkbox is `[x]`. This
  is the anti-self-claim guard (mirrors the kit's "done means the check ran, not asserted"
  doctrine): a session that no-ops cannot make the loop march. The negative-control test pins it.

## 2026-06-29 ROADMAP parsing
- Sub-goal lines matched as `^- \[[ xX]\] SG-[0-9]+`; policy extracted as the first
  `auto|gate` after a `,` or `(`. Tolerant of the trailing `, PR #N (merged)` / `depends ...`
  noise in real ROADMAP lines (verified against the live token-hygiene ROADMAP). `--dry-run`
  prints the full planned sequence up to and including the first gate, without executing.

## 2026-06-29 README lib-index row, framed against the "no DAG scheduler" stance
- README line ~151 says the kit stops short of a DAG scheduler / daemon / cross-machine
  orchestration. The orchestrator is a LINEAR, single-machine, session-per-sub-goal mega-goal
  driver, not any of those; the README row says so explicitly to avoid the apparent tension.

## 2026-06-29 Review fixes (PR #81 review, 7/10)
- Policy parser: exact comma-field match in awk (was a regex that false-matched "(gate review)");
  unknown policy fail-safes to `gate` not `auto`.
- pipefail `|| true` on the `_subgoals` grep|while (no-match no longer escapes `set -o pipefail`).
- Permission posture (OQ-001): `CLAUDE_FLAGS` (default `--dangerously-skip-permissions`) word-split
  into `claude -p`; mocks read prompt as LAST arg. Two tests (default + override).
- `_build_prompt` injects the goal-file CONTENT (glob, shellcheck-clean), matching AC4; one test.
- Cosmetic: `pid` -> `sg`.

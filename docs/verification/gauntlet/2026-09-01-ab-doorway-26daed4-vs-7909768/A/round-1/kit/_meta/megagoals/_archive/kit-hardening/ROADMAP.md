# Mega-goal: kit-hardening

**Destination:** The dwarves-kit autonomous SDD loop runs start-to-finish and stops only at ONE final human review , every driving agent effectiveness-checked, every V-model phase reviewed on BOTH arms, a generic advisor lens + over-suggest before the final gate, consistent review-function naming, mid-flight lane escalation, and a conditional deployable-done , all riding on the kit's shipped guardrails, configurable, without re-opening any blessed boundary.
**Quality bar:** Trustable: the % of autonomous "done" claims that survive a fresh-context re-audit approaches 100. Every addition rides ON TOP of an existing kit pattern inside its boundary , no new scheduler, no mid-flight hard-block, no gate bypass. A teammate running bare `/kit:*` inherits the review DEFAULTS for free.
**Work repo:** `dwarves-kit` (cross-repo: this roadmap lives in ops-toolkit; all PRs land in dwarves-kit against `master`).
**Stacking tool:** gh
**Merge mode:** integration-branch (all sub-goals target `mega/kit-hardening`; the loop auto-merges each past its OWN ship-gate; ONE final PR `mega/kit-hardening -> master` carries the single human review) , per ADR-0028 + SPEC-088 Review posture.
**Merge autonomy:** gated-final (auto-merge every `auto` sub-goal into the integration branch; the final `mega/kit-hardening -> master` PR is held for Han's click).
**Terminus:** build + merge. This is kit-internal tooling with NO runtime surface to deploy , there is deliberately NO deploy/UAT gate. (Sub-goal 07 BUILDS a deployable-done feature; it does not itself deploy anything.)
**Started:** 2026-07-02
**Completed:** 2026-07-02 , all 8 sub-goals merged into `mega/kit-hardening` (PRs #101-#108); TIER-4 close clean (integration + security SHIP, fix `c6fbd99`); final PR **#109** `mega/kit-hardening -> master` OPEN + HELD for Han (gated-final, never auto-merged).

## Authority

The decomposition below is transcribed from **ADR-0028** (autonomous-loop hardening, Accepted + team-blessed 2026-07-01) and **ADR-0029** (review-function naming, Accepted 2026-07-01), both in `dwarves-kit/docs/decisions/`. The decision brief is `dwarves-kit/docs/specs/DECISION-BRIEF-kit-hardening.md`. Where a sub-goal already has a SPEC, it is cited. This roadmap is the execution index; the ADRs are the source of truth for intent.

## Sub-goals

- [x] 01-effectiveness-validator , `agent-effectiveness` reviewer (tools/trigger/instructions/tier), diff-keyed, read-only, fail-safe, + fixtures + tests , `auto` , PR #101 , merged f67d441
- [x] 02-review-naming , enforce the ADR-0029 naming convention in test-meta + rename the 3 legacy agents + update external registry exposure , `auto` , PR #102 , merged 5f73b8a
- [x] 03-generic-advisor , one `advisor` agent, two modes (P5 critique lens + P6 over-suggest) wired at the final integration/UAT boundary, KIT DEFAULT , `auto` , PR #103 , merged 5e6e80d
- [x] 04-right-arm-parity , meta-agent-scaffold `brief-reviewer` / `acceptance-verifier` / `test-reauditor`, fill the agent-less Acceptance + System-test rows, + a fresh-context re-audit lens over each right-arm PASS , `auto` , PR #104 , merged e937c03
- [x] 05-every-step-review , WORKFLOW.md lane default: no V-model phase is `skip`; each phase's review RUNS + records to the gate-ledger; hard-enforced only at ship , `auto` , PR #105 , merged bf1a930
- [x] 06-lane-escalation , re-run `lane-classify` against the SPEC at the spec->build boundary; a heavier-lane trip escalates + re-plans the gate-ledger (up-only, advisory, recorded; downgrade guard preserved) , `auto` , PR #106 , merged b77e1e0
- [x] 07-deployable-done , AGENTS.md zone-3 + ship-gate: deployable work's `done` = deploy-proof + UAT (reuse ADR-0025 stateful shape); inert/library work unchanged , `auto` , PR #107 , merged e89b957
- [x] 08-mega-reconcile , `/kit:mega` mirror (decompose + front-load checkpoint + per-run merge config) + ship-layer auto-merge enforcement riding the ship-gate + deploy/UAT terminus , `auto` , PR #108 , merged 0f5b451

## Dependencies

- 03 depends on 01 (its new `advisor` agent is gated by the effectiveness validator) + 02 (born under the naming convention).
- 04 depends on 01 (new reviewers gated by the effectiveness validator) + 02 (born under the naming convention).
- 05 depends on 03 + 04 (it wires the reviewers those sub-goals create into the no-skip lane default).
- 08 depends on 07 (the deploy/UAT terminus reuses deployable-done's classifier + proof shape).
- 01, 02, 06, 07 are independent (no sibling dependency).
- Suggested execution order: 01 -> 02 -> (03, 04) -> 05, with 06, 07 -> 08 slotted in whenever the loop has no dependency-free work.

## Assumptions (resolved at decompose time, 2026-07-02)

- **Scope = full ADR-0028** (all 8 sub-goals: the SG-01..05 wave + the three the 2026-07-01 refinement added), not the older decision-brief v1 subset (SG-A/B/C). Rationale: ADR-0028 is team-blessed and is the accepted decision.
- **The meta-agent (`/kit:draft-agent`) is already SHIPPED** (`dwarves-kit/agents/meta-agent.md` present). The old brief's "couple SG-A to token-optim-v3 SG-05" blocker is DISSOLVED: 03 and 04 CONSUME the shipped meta-agent to scaffold their new reviewers; they do not wait on token-optim-v3.
- **The ACTIVATOR loop is out of scope; the KIT-side mega pieces are NOT** (corrected 2026-07-02, second pass over ADR-0028). `lib/orchestrate.sh` (with its stall-watchdog) is activator-side and already exists , not rebuilt here. But the ADR's placement table assigns `/kit:mega` (the skill mirror) and auto-merge ENFORCEMENT (ship layer + gate-ledger) to the KIT, and neither exists in `commands/` or the ship layer today , that is sub-goal 08. The original 7-sub-goal scaffold's "P3 out of scope, verify at execution" assumption under-read the ADR and missed a wave sub-goal.
- **A DAG / dependency-graph orchestrator is explicitly OUT OF SCOPE** (ADR-0028 Out-of-Scope). The linear chain + `/kit:dispatch` disjoint fan-out is the ceiling.
- **The UI/UX workflow gap is PARKED** (ADR-0028): the kit has no UI to dogfa proof-of-done against. Not a sub-goal here.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done

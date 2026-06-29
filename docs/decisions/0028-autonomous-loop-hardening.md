# 0028. Full-autonomous-to-final SDD lane (autonomous-loop hardening)

Date: 2026-06-29
Status: Proposed
Relates-to: ADR-0017 (mega-decomposition lane), ADR-0018 (v-model phase frame), ADR-0024 (gate-ledger + ship-enforcement), ADR-0025 (proof-of-done ship gate), ADR-0026 (co-located table-first proof), SPEC-034 (mega-goal lane), SPEC-076 (v-model descent), SPEC-082 (finding-validators), SPEC-087 (inter-sub-goal context hygiene), ops-toolkit `plan-for-mega-goal` skill + `_meta/megagoals/{token-optim-v3,kit-hardening}`

## Decision (one line)

Make the kit's autonomous SDD loop run start-to-finish and stop only at ONE final human review: deeper planning + front-loaded questions up front, a review at every V-model step, auto-merge of each sub-goal past its ship-gate, an extra review lens + an over-suggest pass before the final gate, plus agent-effectiveness validation and a conditional deployable-done , all riding ON TOP of the kit's shipped guardrails, configurable, without re-opening the blessed boundaries.

## Context

The operator's workflow for logically-clear, already-agreed work: run the whole thing once, review and merge only at the end; if something is off at the final step, adjust and continue. The mid-run stops the kit imposes today (human ships every PR) are friction for that workflow. An audit shows most of the closed-loop machinery is already shipped (SPEC-076 v-model descent everywhere; ADR-0024 machine-readable lane×phase enforced at ship; the validator family ADR-0015/0016 + SPEC-082; ADR-0025 proof gate). So this is not a rebuild , it wires the shipped pieces into a single run-to-final lane and adds the few missing steps.

The operator's six principles:
1. Planning (think/spec) deserves more thinking up front.
2. Any sub-goal clarification is gathered and asked ONCE at the start; the run is unattended thereafter.
3. The orchestrator runs start-to-finish and stops only at a final review (auto-merge to final).
4. Every V-model step (left + right arm) has a review step (a command, a predefined subagent, or a runtime subagent); the step must exist.
5. At the final integration / UAT boundary, an EXTRA review lens runs.
6. Before the final review, the kit OVER-SUGGESTS additional ideas to enhance the work.

## Decision (the full-autonomous-to-final lane)

Eight properties, each reusing an existing kit pattern, each inside its boundary:

- **P1 deeper planning** , the think -> design -> spec -> spec-validate phase is deepened + default-on in this lane (more thinking before the spec hardens; spec-validate runs by default).
- **P2 front-loaded clarification** , decompose gathers EVERY sub-goal's clarification question and asks the human ONCE up front (mirrors the `plan-for-mega-goal` skill's single checkpoint); unattended thereafter.
- **P3 run-to-final + auto-merge** , the orchestrator runs all sub-goals start-to-finish and auto-merges each once its ship-gate passes (ADR-0024/0025 still hard-gate every merge), stopping only at the final PR for the human (gated-final). Configurable; default auto-to-final for operator-owned runs.
- **P4 every-step review** , every V-model phase (left + right arm) has a review step that RUNS , a command, a predefined subagent, or a runtime subagent , recorded to the gate-ledger and enforced at ship. No phase is `skip` in this lane. NOT a mid-flight hard-block (ADR-0024 + PHILOSOPHY preserved): the review runs and records; hard enforcement is at ship.
- **P5 extra review lens at integration/UAT** , before the final gate, an extra review-lens pass runs at the integration + UAT boundary, on top of the per-step reviews. KIT DEFAULT (runs on every applicable run, not opt-in).
- **P6 over-suggest before final** , a generative enhancement pass proposes additional ideas / sub-goals to improve the work, surfaced to the human just before the final review (a completeness-critic in the generative direction). KIT DEFAULT (runs before every final review, not opt-in).
- **Agent-effectiveness validation** (SPEC-088) , the agents that drive the loop are effectiveness-checked (tools / trigger / instructions / tier), not just structure-linted. Read-only / advisory / fail-safe / diff-keyed.
- **Conditional deployable-done** , for deployable work, done = deploy-proof + UAT (reuse ADR-0025 stateful shape, enforce at ship); inert / library work unchanged.

## How it stays inside the blessed boundaries

- Auto-merge RIDES ON the per-sub-goal ship-gate; it never bypasses a gate. The gate still hard-enforces (ADR-0024); only the merge ACTION is automated post-gate, and the final stays human.
- Every-step review RUNS + records; hard enforcement stays at ship, not mid-flight (PHILOSOPHY intact).
- Decomposition stays planning-only (SPEC-034); the run is the existing bounded in-session loop (ADR-0017), not a new scheduler. No DAG / cross-machine (GSD v2).

## Where each layer lives (skill vs kit)

The orchestration is not all in one place; it splits cleanly by layer:

| Concern | Home | Why |
|---|---|---|
| Decompose + front-load questions (P1, P2) + per-run merge config | `plan-for-mega-goal` SKILL (authoring), mirrored by `/kit:mega` | shapes a specific mega-goal; the kit command mirrors it so the team gets it |
| Run-to-final loop (P3) | the ACTIVATOR (external `/goal` / ralph / goal-craft) | ADR-0017 activator-agnostic; owned by neither kit nor skill |
| Auto-merge enforcement | KIT (ship layer + gate-ledger) | rides on the ship-gate; never bypasses |
| Every-step review (P4), extra lens (P5), over-suggest (P6), validators, deployable-done | KIT DEFAULTS (WORKFLOW.md + the review/ship layer + agents) | enforcement that applies to ALL work; the TEAM inherits it , if these lived only in the ops-toolkit skill, bare `/kit:*` users would not get them |

Net: AUTHORING is the skill (+ `/kit:mega` mirror); ENFORCEMENT + the review DEFAULTS (P4/P5/P6) are the kit. The operator's instinct ("it's the skill") holds for the planning layer; the review defaults belong in the shared kit so the team inherits them.

## The one team-facing change (flag)

Auto-merge-to-final on the SHARED kit repo defers per-PR team review to the final gate. For the operator's solo / owned runs this is the default. For team runs it is a per-run config (a team member may require per-PR review). The team should accept this consciously , hence this ADR is Proposed.

## Alternatives considered

- **Hard-gated mid-flight** (block each step until reviewed). Rejected: violates PHILOSOPHY + ADR-0024 (advisory-mid/hard-at-ship). P4 is satisfied by review-runs-and-records, not mid-block.
- **Keep human-ship per PR** (status quo). Rejected by the operator: too many mid-run stops for logically-agreed work; the want is run-once-review-at-the-end.
- **Two divergent mega systems** (skill auto / kit manual). Rejected: align them; the kit gains the skill's autonomy, configurable.

## Consequences

- Trustable autonomous-to-final runs: every step reviewed, an extra lens + over-suggest before the human looks, deployable work actually deployed+UAT'd, the driving agents effectiveness-checked.
- Cost: more verification token cost (kept bounded , validators gated/diff-keyed); auto-merge on a shared repo needs team awareness; the done-definition change touches every kit user (team-review-first).
- Risk if mis-built: auto-merge escaping the ship-gate; a deployable-done firing on inert work; every-step review degrading to mid-flight hard-blocks. All three are explicit negative-control acceptance criteria in the SPECs.

## Out of Scope

- Hard-wiring `/goal` to mechanically execute phases (ADR-0017 activator-agnostic stands).
- Hard-gating process-completeness mid-flight (ADR-0024 + PHILOSOPHY stand).
- Mega lane doing PR creation / dispatch / scheduling beyond planning (SPEC-034); auto-merge is a ship-time helper, not a scheduler.
- **A DAG / dependency-graph orchestrator** (considered 2026-06-29). The kit runs a LINEAR chain (SPEC-034) with bounded shallow-and-wide parallel already available for DISJOINT work (ADR-0019/0020 + `/kit:dispatch`). An ORDERED dependency graph + scheduler + crash-recovery + parallel-writer locks is the deferred GSD-v2 successor , a separate effort that re-opens ADR-0017/0019, NOT this wave. Tracked as a future option in the kit-hardening mega-goal NOTES.
- The pi-vcc + meta-agent context-engineering work (ops-toolkit `token-optim-v3`); this ADR only adds the effectiveness check the meta-agent's output will need.

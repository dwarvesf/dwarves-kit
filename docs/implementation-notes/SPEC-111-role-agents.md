# Implementation notes: SPEC-111 role-agents

Delta from the spec. References, does not restate.

## 2026-07-03 spec-validate: CHANGES-REQUIRED, 2 MAJOR + 2 minor folded (design reshaped)

- **F1 (MAJOR, the crux):** execute.md 2b-0's reuse branch dispatches the task's IMPLEMENTER
  ("dispatch the worker NOW"), so a READ-ONLY reviewer cannot live there (it can't complete a
  task , the anti-orphan "dispatched-to-uselessly" trap). RESHAPED to two dispatch paths by type:
  WORKERS -> 2b-0 reuse (via `role-classify.sh agent-for`); REVIEWERS -> `/kit:review-team` opt-in
  domain lens. Both live paths -> the anti-orphan WIRING GATE is satisfied for both types; the
  gate's literal "2b-0 reuse" wording is reconciled to "each agent has a LIVE dispatch path"
  (TIER-4's no-orphan check verifies exactly that).
- **F2 (MAJOR):** `agent-for(generic)` returns EMPTY (was mapping to code-reviewer), so 2b-0 falls
  through to SPEC-089 Mode-C synthesis (SPEC-089:79 requires generic to escalate; a generic->agent
  map would collapse the whole dynamic long tail). security also returns empty from `agent-for`
  (security-reviewer is a review-team lens, not a 2b-0 implementer).
- **F3 (minor):** dropped the "CI gate" framing , `test-agent-effectiveness.sh <path>` is invoked
  locally (test-advisor / test-right-arm-parity), NOT in `.github/workflows/test.yml`.
- **F4 (nit):** the `agent-for` lookup proves NAME RESOLUTION; the reviewer/worker on-role fixture
  dispatch is the real dispatch proof. Both are in the verification.

## Gating split (forced by the mechanical gate's read-only assertion)

`tests/test-agent-effectiveness.sh <path>` (GATE MODE) asserts read-only tools, so:
- 4 REVIEWERS pass the MECHANICAL gate (3/3 each: read-only tools, valid tier, on-axis name).
- 2 WORKERS carry Edit/Write and are gated by the agent-effectiveness AGENT (LLM, role-aware:
  the over-grant lens only flags a read-only reviewer with write tools, `agents/agent-effectiveness.md:43-49`,
  so a worker's justified write tools pass), dispatched + recorded in the proof.
Neither modifies the effectiveness validator (goal: out of scope).

## Roster-sync guard update (a SPEC-108 test, expanded by this sub-goal)

SPEC-108's set-equality guard in `test-meta.sh` (`GEN_ROSTER`) pinned the `generated-by:` key set to
the 5 kit-hardening agents. The 6 new agents here are ALSO generated (carry `generated-by:`), so the
"known generated roster" legitimately expands to 11. `GEN_ROSTER` updated to include the 6; the
guard's intent (no spread to HAND-WRITTEN agents) is unchanged , the 6 additions are generated, not
hand-written.

## Roster (6 new; 2 domains map to existing)

2 workers (db-migration-worker, data-etl-worker) -> 2b-0; 4 reviewers (performance/api/frontend/
infra-reviewer) -> review-team; security -> existing security-reviewer; generic -> Mode-C. The
reviewer-heavy split is by-fit (judgment domains get read-only lenses; doing domains get workers),
and it aligns with the gate reality (reviewers pass the mechanical gate).

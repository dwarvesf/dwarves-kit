# Sub-goal 04: right-arm review parity + meta-agent-scaffolded reviewers

**Merge policy:** auto , new agents + a re-audit lens, testable via fixtures.
**Time budget:** 4-6 hours (the widest sub-goal , 3 new agents + the re-audit lens).
**Proof:** run-table , the 3 new agents exist + pass the 01 effectiveness gate + conform to the naming convention · the Acceptance and System-test rows now HAVE an agent · a fresh-context re-audit lens fires over an `integration-verifier`/`task-verifier` PASS and can flag a planted-bad PASS.
**Depends on:** 01 (new reviewers gated) + 02 (born under the convention).
Model: opus
Effort: high
**Branch:** feat/kit-harden-04-rightarm
**PR base:** mega/kit-hardening

## Outcome

The V-model RIGHT arm has review parity with the left. Two holes closed: (a) the Acceptance and System-test rows, agent-less today, get `acceptance-verifier` and `system-verifier`; (b) `integration-verifier` and `task-verifier` PASSes, unreviewed today, get a fresh-context `recheck-verifier` re-audit lens , the ADR's trust metric ("% of autonomous done-claims that survive a fresh-context re-audit") made real. Plus `brief-reviewer` (right-arm mirror of the design brief). All are meta-agent-scaffolded and gated by the 01 effectiveness validator, born under the ADR-0029 convention names.

## Quality bar

`recheck-verifier` is the one genuinely NEW role: a fresh-context verifier OF a verifier's PASS. Semantics PINNED (Han, 2026-07-02): it RE-EXECUTES the verification commands in a fresh context and re-judges the outcome , re-execution catches stale or fabricated evidence, which a read-back of the recorded evidence cannot. It is NOT a read-and-re-judge pass over the stored run-table. It must catch a planted-bad PASS that the original verifier waved through. The other agents are "free" plan-fixes (already-conforming names, zero rename blast radius). Every one passes 01 or it does not ship.

## How to close the loop

Scaffold `brief-reviewer`, `acceptance-verifier`, `system-verifier`, `recheck-verifier` via the meta-agent; gate each through 01; wire the re-audit lens over the right-arm PASSes in `commands/execute.md` (where task-verifier + integration-checker/verifier run). Verify:

```
cd dwarves-kit && bash tests/test-right-arm-parity.sh   # 4 agents present, conform, gated; re-audit fires on a PASS; planted-bad PASS caught
for a in brief-reviewer acceptance-verifier system-verifier recheck-verifier; do
  bash tests/test-agent-effectiveness.sh "agents/$a.md"; done
```

Captured evidence: run-table at `docs/verification/right-arm-parity.md` , one row per new agent (present + gate-pass), the Acceptance/System rows now non-empty, and the re-audit-catches-planted-bad negative-control row.

**Done =** the 4 agents exist conforming + passing 01, the right-arm Acceptance + System rows have agents, and `test-right-arm-parity.sh` proves the `recheck-verifier` fresh-context re-audit fires over a right-arm PASS and flags a planted-bad PASS.

**Kit-adopted repo? Record the gates.** `bash lib/lane-classify.sh classify "right-arm review parity: 4 new reviewer agents + fresh-context re-audit lens"` (expect `full`), record build + review gates via `lib/gate-ledger.sh` before push.

## Handoff on completion

1. Flip 04's box, PR # + SHA.
2. HOT `HANDOFF.md`: next is 05-every-step-review; first action = audit WORKFLOW.md for any V-model phase currently `skip`-able in this lane. Pointer: ADR-0028 P4.
3. WARM `DECISIONS.md`: the right arm now mirrors the left; `recheck-verifier` is the fresh-context re-audit lens the trust metric depends on.
4. Report IN records, EXIT.

## Scope edges

**In:** the 4 new agent files, the re-audit lens wiring in the execute path, the Acceptance/System-test agent slots, tests.
**Out:** the advisor (03); the left-arm reviewers (already present); the effectiveness validator itself (01).
**Not:** SPEC-089 dynamic same-run specialist synthesis (separate token-optim-v3-adjacent effort); a re-run of the same verifier (recheck must be fresh-context, not a repeat).

## Where to look

`commands/execute.md` (where right-arm verifiers run , task-verifier after each task, integration at Step 4), `agents/` for the meta-agent + verifier shape, ADR-0028 "Right-arm review parity", ADR-0029 SG-06 rows for the exact names.

## PR body

Closes right-arm review parity (kit-hardening SG-06, ADR-0028): adds `brief-reviewer`, `acceptance-verifier`, `system-verifier`, and the fresh-context `recheck-verifier` re-audit lens over right-arm PASSes. Meta-agent-scaffolded, all gated by the SG-01 effectiveness validator, born under the SG-02 naming convention.

Verify: `bash tests/test-right-arm-parity.sh`. Proof: `docs/verification/right-arm-parity.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. On the integration branch after SG-01 + SG-02.

## Notes

<empty>

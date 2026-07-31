# Spec: feature-map audit-loop skill
Generated: 2026-07-31
Status: APPROVED (operator pre-approved design; adversarial validate overridden in the gate ledger)
Lane: full

Phase B of the feature-registry program (Phase A: SPEC-219, merged as PR #323). The registry generator makes feature inventory drift mechanical to detect, but nothing yet closes the loop against the hand-derived `docs/workflow-paths.md` path index: a feature can be live in `docs/FEATURES.md` yet missing from the path map, or linger in the path map after removal. This spec adds `skills/feature-map/SKILL.md`, an audit-loop instance (template: `skills/doc-drift/SKILL.md`, pattern: `docs/patterns/audit-loop.md`) whose Tier 1 is fully mechanical (the SPEC-219 generator diff + a both-directions name cross-check between FEATURES.md and the workflow-paths section 5 index) and whose Tier 2 dispatches a general-purpose subagent ONLY for delta features, to re-place them on the flow-topology/system-topology diagrams and update the path index. PR-gated apply; refuses to run while FEATURES.md itself is stale.

Design decisions carried from the operator dispatch: Tier 1 embeds shell recipes in the skill body (no new lib script; the generator IS the tool, the cross-check is four sed/comm pipelines); staleness refusal is the generator diff run FIRST; Tier 2 scope is the delta only, never a full re-derivation of the topology diagrams. One decision made here and logged: the cross-check is PRESENCE parity (name exists on both sides); trigger-class agreement is checked as a secondary listed finding, because the one known mismatch (`skill-review` frontmatter `[I]` vs path-index `[H]`, found in Phase A) is an operator judgment call, not auto-fixable.

## Acceptance Criteria
- [ ] AC-1: `skills/feature-map/SKILL.md` exists with valid frontmatter (name, description, disable-model-invocation) and the audit-loop four-slot table (item set, contract, evidence class, apply mechanics).
- [ ] AC-2: Tier 1 is mechanical and zero-model-cost: (a) regenerate the registry to a temp file and diff (stale FEATURES.md = REFUSE, tell the operator to run the generator first); (b) cross-check every FEATURES.md row name against the `docs/workflow-paths.md` section 5 index, both directions, all four kinds.
- [ ] AC-3: Tier 2 dispatches a general-purpose subagent ONLY for delta features (rows failing the cross-check), scoped to re-placing them on the section 2/3 topology diagrams and the section 5 index; no delta = no dispatch.
- [ ] AC-4: apply is PR-gated per the audit-loop pattern (branch first, verdict list in the PR body, UNSURE never auto-resolved).
- [ ] AC-5: registered: README skills table row + skills header count bump; `docs/patterns/audit-loop.md` Known instances names it.
- [ ] AC-6: `_meta/BACKLOG.md` gains a row for this program (next free ID) marked shipped, and ID-407 gains a note that the generated registry is now its feature-inventory source.
- [ ] AC-7: proof-of-done carries a REAL Tier-1 run on the current estate (green) plus a negative control (a synthetic path-index deletion makes the cross-check go RED).

## Test plan
Date: 2026-07-31. Dialect: prose-contract pins (the skill is a doc) + one executed run.

| # | Case | Covers | Expected |
|---|---|---|---|
| 1 | frontmatter + four-slot table present | AC-1 | grep hits |
| 2 | staleness refusal stated before any verdict step | AC-2a | REFUSE wording present |
| 3 | both-directions cross-check recipes present, four kinds | AC-2b | sed/comm recipes in body |
| 4 | Tier 2 delta-only + PR gate stated | AC-3, AC-4 | wording present |
| 5 | README table + count, audit-loop Known instances | AC-5 | test-meta README skill pins green; grep audit-loop.md |
| 6 | live Tier-1 run | AC-7 | 34/26/7/25 parity, zero mismatches (recorded in proof) |
| 7 | NC: drop one index line, re-run cross-check | AC-7 | that name surfaces as only-in-FEATURES |

## Verification
```
bash tests/test-meta.sh
```
Green (README skill-count pins pick up the new skill). Tier-1 run + negative control recorded in `docs/verification/feature-map-skill.md`.

## After state
The registry (SPEC-219) plus this skill close the loop: mechanical drift detection at test time, a routine audit path for re-syncing the workflow path map, and topology re-placement scoped to deltas. ID-407's flow-gallery work can consume `docs/FEATURES.md` as its inventory source instead of hand-enumerating.

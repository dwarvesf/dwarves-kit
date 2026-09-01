# Implementation notes: audit-scanner-agent (SPEC-220)

Delta log only; the spec carries the design.

## 2026-07-31 registry dispatched-by column shows `-` for skill-dispatched agents

Context: `lib/registry/feature-registry.sh` derives an agent's Dispatched-by column by token-grepping `commands/*.md` only; audit-scanner is dispatched by two SKILLS, so its column reads `-` (same as `claim-verifier`, `data-etl-worker`).
Decision: leave the generator untouched; the skill-side wiring is pinned by `tests/test-audit-scanner-contract.sh` AC2 and visible in the FEATURES.md Tests column instead.
Why: widening the generator to scan `skills/` is a generator change outside this spec's scope, and the contract test already makes the wiring drift-detectable.
Impact: a future skill-dispatched agent inherits the same `-`; if that misleads, the generator grows a skills/ scan in its own spec.

## 2026-07-31 grill-skip reason enum + record vs override verbs

Context: `gate-ledger.sh record <rid> grill skipped` refuses free-text reasons; the reason must START with `reason=<home-turf|density-low|operator-wave>` (SPEC-138 closed enum, write-time enforced). Separately, pre-approved gates are recorded with the `override` VERB, not `record ... override` as a state.
Decision: recorded the grill skip as `reason=operator-wave: ...` and the five pre-approved design gates via `gate-ledger.sh override`.
Impact: one duplicate grill line in the run ledger from the failed first attempt (append-only, harmless).

## 2026-07-31 architecture.md inventory was the one unannounced registration surface

Context: the dispatch prompt named FEATURES.md, workflow-paths, README, and the pattern doc; test-meta additionally pinned `docs/architecture.md` (V-phase inventory row count + the 26-agent/60-entry headline) and the `docs/MANUAL.md` reverse cross-ref.
Decision: added the cross-phase inventory row (19 -> 20 cross-phase in the headline) and the MANUAL row.
Why: the derived-count pins are the machinery working as designed; nothing to fix, just two more registration sites than the prompt enumerated.
Impact: adding an agent touches six doc surfaces total (README x2 counts + row, MANUAL, architecture x2 + row, workflow-paths x3 lines, FEATURES regen, pattern doc); all but workflow-paths and the pattern doc are pinned by test-meta, so a miss cannot ship silently.

## 2026-07-31 review round + reflect

Review: kit:agent-effectiveness dispatched on the new agent definition (diff-keyed standard for agent authoring); verdict recorded in the gate ledger. Reflect: the registration machinery made adding an agent mechanical rather than expensive; every missed surface self-announced through a RED pin with the exact expected count, and the only genuinely hand-derived surfaces left are workflow-paths.md (which feature-map audits on cadence) and the audit-loop pattern doc.

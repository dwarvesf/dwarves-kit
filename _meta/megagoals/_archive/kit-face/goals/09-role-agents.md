# Sub-goal 09: starter role-specialized agent roster

**Merge policy:** auto (every generated agent is gated by the agent-effectiveness validator; vacuous ones cannot merge)
**Time budget:** 4-6 hours (the widest build alongside 03: 8 domains, mixed types, each gated + justified).
**Proof:** run-table, one row per generated agent: passes `agent-effectiveness` (tools minimal-yet-sufficient · trigger right · instructions produce a good result · tier fits) · carries `generated-by:` provenance (05's convention) · **WIRING (load-bearing): a task classified to that domain by `role-classify` dispatches THAT agent via execute.md 2b-0's reuse branch (a reuse HIT), not a synthesized Mode-C preamble** · a fixture dispatch of ONE reviewer + ONE worker shows a real on-role result. Plus the SPEC-089-boundary row.
**Depends on:** none for building; feeds 01 (agents count) + 02 (index) , covered by the docs-last rule.
Model: sonnet
Effort: high
**Branch:** feat/kit-face-09-roleagents
**PR base:** master

## Outcome

A starter roster of role-specialized agents , ONE per `role-classify.sh` domain (security, db-migration, frontend, performance, data-etl, infra, api, generic) , generated via the meta-agent (`/kit:draft-agent`) and each gated by the agent-effectiveness validator. Types are MIXED across the 8 (operator: both reviewers and workers): each domain's agent is the form its specialization naturally takes , a read-only REVIEW lens where the value is judgment (e.g. security, performance), a WORKER with Edit/Write where the value is doing (e.g. db-migration, data-etl) , decided per domain during `/spec` and justified there. Existing agents are NOT duplicated (`security-reviewer`, `code-reviewer` already exist; those domains get a worker or are skipped, not a second reviewer). This roster IS the runtime proof-of-function for the meta-agent: generator builds -> effectiveness validator trusts -> roster usable.

## Quality bar

Every generated agent must EARN its slot , the effectiveness gate rejects a structurally-valid but ineffective agent, and a domain whose specialization is already covered gets no duplicate. No empty scaffolds: the fixture dispatch proves at least one reviewer and one worker produce a real on-role result. Mixed types are a deliberate design, not laziness , each type choice is one justified sentence in the spec.

## The dispatch path ALREADY EXISTS (execute.md 2b-0) , this is the wiring, and the SPEC-089 boundary

Correction from the 2026-07-03 code check: SPEC-089 is NOT unbuilt. `commands/execute.md` step 2b-0 ("Role classification + specialist synthesis") already: (1) runs `role-classify.sh classify`, (2) **"Reuse an existing specialist if present , if a predefined agent fits (dispatchable `subagent_type`), dispatch THAT, skip synthesis"**, (3) else synthesizes open-ended via meta-agent Mode C. So the boundary is ALREADY in code: reuse-known-first, synthesize-novel-fallback. 09's agents ARE the reuse targets , they make step (2) hit instead of falling to (3).

Therefore 09 does NOT amend SPEC-089's design; it POPULATES the reuse table 2b-0 already reads. Requirements: (a) each agent named/shaped so 2b-0 step 2's "predefined agent fits this domain" lookup finds it (verify how 2b-0 matches , by `subagent_type` name convention, a domain tag, or a lookup table; wire whatever it actually reads); (b) prove the reuse hit (the wiring proof above); (c) one sentence in the spec + WORKFLOW.md stating the boundary is 2b-0's reuse-vs-synthesize branch, so no maintainer builds a second router. If 2b-0's match mechanism does NOT currently support a static-roster lookup, adding that lookup is IN scope (it is the wiring).

## How to close the loop

`/spec` + `/spec-validate` first (the spec assigns each domain its type + justification, cites role-classify + agent-effectiveness + the SPEC-089 reconcile). Generate via `/kit:draft-agent` per domain; gate each:

```
cd dwarves-kit
for a in <the 8 generated>; do bash tests/test-agent-effectiveness.sh "agents/$a.md"; done
bash tests/test-meta.sh   # roster sync (MANUAL.md + architecture tables) green with the new agents
# fixture dispatch: one reviewer + one worker, on-role result captured
```

Provenance per 05's `generated-by:` convention. Assumptions: ROADMAP `## Assumptions` 09 block.

**Done =** 8 domain agents generated + each passing `agent-effectiveness` + carrying provenance, EACH proven to be dispatched by execute.md 2b-0's reuse branch on a domain-classified task (the wiring hit, not a synthesized preamble), the reviewer/worker fixture dispatches show real on-role output, roster-sync tests green, and the 2b-0 reuse-vs-synthesize boundary stated in the spec + WORKFLOW.md (no over-claim).

## Scope edges

**In:** the 8 generated agent files, their effectiveness-gate proofs, roster-sync (MANUAL.md + architecture.md tables), the SPEC-089 amendment, fixtures.
**Out:** dynamic same-run synthesis (that stays SPEC-089's, now reframed to the long tail); the effectiveness validator itself (exists, kit-hardening SG-01); provenance emitter (05 owns it, this consumes it).
**Not:** duplicating existing agents; 16 agents (one per domain, type mixed across the 8, NOT reviewer+worker each); roles with no recorded need beyond the 8 taxonomy domains.

## Where to look

commands/execute.md step 2b-0 (THE dispatch path , how it matches a predefined specialist to a domain: read this FIRST, it defines the wiring), lib/role-classify.sh (the 8-domain taxonomy + trigger regexes = each agent's trigger source), commands/draft-agent.md + agents/meta-agent.md (the generator, incl. Mode C fallback), agents/agent-effectiveness.md + tests/test-agent-effectiveness.sh (the gate), agents/{security-reviewer,code-reviewer}.md (do-not-duplicate), docs/specs/SPEC-089-dynamic-agent-synthesis.md (the boundary doc, now the long-tail half).

## PR body

Starter role roster: 8 domain-specialized agents (one per role-classify domain, mixed reviewer/worker by fit) generated via the meta-agent, each gated by agent-effectiveness + provenance-stamped; the meta-agent's runtime proof-of-function. Reconciles SPEC-089 (static-known roster vs dynamic-novel long tail). Verify: per-agent effectiveness gate + roster-sync + reviewer/worker fixture dispatch. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>

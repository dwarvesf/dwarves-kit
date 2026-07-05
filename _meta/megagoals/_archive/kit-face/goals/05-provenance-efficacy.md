# Sub-goal 05: meta-agent provenance + runtime efficacy metric

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table: the CC-load probe (ONE backfilled agent installed locally, still loads) recorded BEFORE the other four commit · all 5 generated agents carry `generated-by:` derived from their Source footers · a draft-agent fixture run emits the key · test-meta green with the extra key (verified tolerant, but pin it as a row) · SPEC-073 `## Amendments` adds metric 11 (catches per generated agent) with its grep command (AC2-compliant).
**Depends on:** none.
Model: sonnet
Effort: medium
**Branch:** feat/kit-face-05-provenance
**PR base:** master

## Outcome

Generated agents are distinguishable from hand-written ones forever: `generated-by: draft-agent 2026-07-02 <context>` frontmatter backfilled on the five kit-hardening-generated agents (advisor, brief-reviewer, acceptance-verifier, system-verifier, recheck-verifier; one-liners derived from each agent's existing Source footer, not invented), and `commands/draft-agent.md` emits the key on every future install. SPEC-073 gains metric 11: catches per generated agent, fed by grep over `docs/verification/*` Re-audit lines + review records , SPEC-088 validates the definition at install; metric 11 validates the deployment at runtime.

## Quality bar

Probe before batch (repo-external tolerance is assumption until one agent proves it). No invented provenance prose. The "first-N dispatches" half is deliberately OUT , nothing records dispatch counts today; that ACTION line is a filed follow-up (NOTES), not silent scope. Additive-marker convention sentence shared verbatim with 03.

## How to close the loop

`/spec` + `/spec-validate` first. Then the probe capture, the 5 backfills, the draft-agent fixture emit, `bash tests/test-meta.sh`, and the SPEC-073 amendment with metric 11's literal command. Assumptions: ROADMAP 05 block.

**Done =** probe recorded first, 5 agents + emitter shipped, metric 11 amended into SPEC-073 with a runnable command, test-meta green.

## Scope edges

**In:** 5 agent frontmatters, draft-agent.md emit step, SPEC-073 amendment, the probe, a test-meta row for the key.
**Out:** dispatch-count ACTION lines (follow-up row); Mode C inline preambles and Mode B sub-goal files (no frontmatter, exempt by design).
**Not:** re-running the effectiveness validator over unchanged agents (diff-keyed by design); a provenance registry file.

## Where to look

agents/{advisor,brief-reviewer,acceptance-verifier,system-verifier,recheck-verifier}.md Source footers, commands/draft-agent.md install flow, agents/meta-agent.md:23 (frontmatter contract) + :90-98 (DRAFT-comment flow), test-meta.sh:426-446 (frontmatter lint), docs/specs/SPEC-073-*.md metric table.

## PR body

Meta-agent provenance: `generated-by:` backfilled on the 5 generated agents (from Source footers; CC-load probe first) + draft-agent emits it; SPEC-073 amended with metric 11 = catches per generated agent (grep-fed, AC2-compliant). Verify: probe capture + fixture emit + `bash tests/test-meta.sh`. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>

# Sub-goal 06: operator-persona design lens

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table: a fixture critique WITH `persona:` dispatches 6 lenses and the merge carries the appended persona `### Scores` row · NEGATIVE CONTROL: without the arg, exactly the 5 existing lenses fire, output byte-compatible with today · the DEC amending DEC-003's boundary exists and kit-health check 13 carries the carve-out (kit-health run captured, no "persona theater" flag on the sanctioned path).
**Depends on:** none.
Model: sonnet
Effort: high
**Branch:** feat/kit-face-06-persona
**PR base:** master

## Outcome

`/kit:ui-design` and `/kit:visual-team` accept an operator-supplied `persona: <archetype>` ("HIG-steeped Apple platform designer", "Linear/Stripe-caliber product designer"): an INLINE 6th dispatch prompt (SPEC-016 "no new agent files"; code-reviewer's "through the X lens only" shape) returning the SAME contract (2-5 findings, CRITICAL/HIGH/MEDIUM/LOW + concrete fix + 0-10 score) so the merge stays uniform. `$ARGUMENTS` seeds a `Persona:` line in the `## UI design` brief so repeat runs read it without re-supplying. 0-or-1 persona per run; critique-only. The governance boundary is RECORDED: a DEC states why a runtime operator archetype is distinct from the baked-in personas DEC-003 rejected (the kit ships no persona; taste liability stays with the operator), plus the kit-health check-13 carve-out.

## Quality bar

The DEC is the load-bearing artifact , without it, kit-health and the next maintainer will read this as re-litigating a settled rejection. No-arg behavior is byte-compatible (the NC proves it). Persona-shaped GENERATION is a named non-goal (the brief's Tone/Differentiation fields own that).

## How to close the loop

`/spec` + `/spec-validate` first (the spec cites DEC-003 + SPEC-020 and carries the new DEC). Then the fixture runs (with/without persona) + a kit-health run + existing visual-team tests. Assumptions: ROADMAP 06 block.

**Done =** both fixture runs green (6-lens with, 5-lens byte-compatible without), DEC + kit-health carve-out committed, spec VALIDATED citing the prior rejections.

## Scope edges

**In:** visual-team.md ($ARGUMENTS, 6th lens dispatch, 6th score row), ui-design.md (persona threads the Step-3 seam, brief `Persona:` line), the DEC, kit-health check-13 line.
**Out:** the quiescence loop (07); multiple personas per run; persona-shaped generation.
**Not:** new agent files; a persona registry/config file; touching the 5 existing lens prompts.

## Where to look

commands/visual-team.md (Step 2 dispatch, :69-74 Scores template, :92 the stripped-personas note), commands/ui-design.md Step 3 (the brief-param seam), docs/specs/SPEC-016-*.md DEC-003 + :76 rationale, docs/specs/SPEC-020-*.md:171 non-goal, commands/kit-health.md:176, commands/review-team.md (the parameterized-dispatch shape).

## PR body

Operator-persona design lens: `persona: <archetype>` as an inline 6th visual-team lens (same contract, uniform merge), brief-persisted via a `Persona:` line; DEC records the boundary vs DEC-003 (runtime operator archetype, kit ships no persona) + kit-health carve-out. NC: no-arg = 5 lenses byte-compatible. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>

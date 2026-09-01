# Sub-goal 06: data-driven-routing

**Merge policy:** gate (dwarves-kit + a routing decision; team review)
**Time budget:** ~1 session, AFTER v2 SG-09 lands
**Proof:** run-table , given v2 SG-09's measured token+turns data, the router's suggested
model/effort per sub-goal matches the measured-cheapest-at-quality-parity choice on the fixture.
**Depends on:** v2 SG-09 (the measurement). BLOCKED until SG-09 produces data.
**Branch:** `feat/v3-routing`
**PR base:** dwarves-kit `main`

## Outcome
The meta-agent (SG-05) becomes data-driven: it reads v2 SG-09's measured token+turns-to-green data
and SUGGESTS the model/effort routing per sub-goal (and flags decompositions that measured
expensive), instead of a human guessing the `model:`/`effort:` fields. "Build the thing that builds
the thing", grounded in real numbers.

## Quality bar
Suggestions match what the data actually shows is cheapest at quality parity, not a heuristic. It is
a SUGGESTER (gated), never a silent auto-router. When the data is thin, it says so rather than
overfitting.

## How to close the loop
PRECONDITION: v2 SG-09 has produced measured per-lever token+turns data on the SG-12 fixture. If
not, this sub-goal is BLOCKED, do not start. Then, in dwarves-kit:
```
# feed SG-09's measured data; ask the router to suggest routing for the fixture sub-goals
# compare suggestions against the measured-cheapest-at-parity choice
bash tests/test-routing.sh
```
Capture a run-table: for each fixture sub-goal, suggested model/effort vs measured-cheapest;
agreement rate; a thin-data abstention case.

**Done =** the router suggests per-sub-goal model/effort from SG-09's measured data, the run-table
shows its suggestions match the measured-cheapest-at-parity choice on the fixture, and it abstains
(not overfits) on thin data.

## Scope edges
**In:** the data-driven routing suggester, consuming SG-09's data format + extending SG-05's
meta-agent.
**Out:** the drafter itself (SG-05); the measurement harness (v2 SG-09 owns that); auto-applying
routing without review.
**Not:** a live online-learning loop; routing decisions made silently; starting before SG-09's data
exists.

## Where to look
v2 SG-09 measurement: `_meta/megagoals/token-optim-v2/goals/09-measurement.md` + its output data
format. SG-05's meta-agent. v2 SG-03 (the model/effort routing fields this suggests).
`research/2026-06-29-token-coherence-design.md` (the "Opus is 86.5% of spend" lever).

## PR body
feat(kit): data-driven model/effort routing , the meta-agent suggests routing from v2 SG-09's
measured token+turns data. Extends SG-05. Gated. BLOCKED until SG-09 data exists. Verification:
suggestion-vs-measured run-table. token-optim-v3 sub-goal 06.

## Notes

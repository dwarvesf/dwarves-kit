# Implementation notes: SPEC-091 generic advisor (kit-hardening SG-03)

Delta from SPEC-091 / ADR-0028.

## 2026-07-02 "Final integration/UAT boundary" maps to review-team Step 2b + ship/mega

Context: the kit has no UAT/deploy phase (ROADMAP terminus: internal tooling, no
runtime surface). ADR-0028 P5/P6 name the "final integration/UAT boundary".
Decision: critique (P5) is wired into `/kit:review-team` Step 2b (the code-review
boundary = the last static review before ship); over-suggest (P6) is documented as a
pass at the ship / mega-lane final boundary, which SG-08's `/kit:mega` will dispatch.
Why: those are the real final-boundary dispatch points that exist today; there is no
UAT phase to hang it on.
Impact: SG-08 consumes the over-suggest pass at the mega final boundary; until then
the P6 mode is defined + tested as present, wired at ship.

## 2026-07-02 Gate mode added to test-agent-effectiveness.sh

Context: SPEC-091 AC6 + goal-03 verification call `test-agent-effectiveness.sh
agents/advisor.md` (a per-agent gate). The SG-01 test had no path-arg mode.
Decision: added a GATE MODE to `tests/test-agent-effectiveness.sh`: given an agent
path, it runs the deterministic lens subset (read-only tools, valid model tier,
on-axis name) and exits 0/1. This is the CI proxy for "gated by the 01 validator";
the full four-lens LLM judgment stays the runtime agent's job.
Why: a reusable machine gate the SG-03/04 meta-agent-scaffolded agents pass through,
without a live model in CI. SG-04's new agents reuse the same gate mode.

## 2026-07-02 Advisor model = sonnet (cheap-first, it is a kit default)

Per SPEC-091 AC5: the advisor runs on EVERY applicable run, so opus-by-default would
burn the expensive tier every time. `model: sonnet` is the default; the frontmatter
`model:` IS the per-run config knob (an operator raises it for a high-stakes run).

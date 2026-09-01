# SPEC-091: Generic advisor (extra lens + over-suggest)

Status: VALIDATED
Date: 2026-07-02
Lane: full (new kit-default review agent + WORKFLOW wiring)
Type: feature
Relates-to: ADR-0028 (P5 extra lens, P6 over-suggest; 2026-07-01 additive refinement), ADR-0029 (named-noun `advisor`), SPEC-088 (agent-effectiveness gate), ADR-0005 (read-only verifier), SPEC-087 (distilled return)
Board: kit-hardening mega-goal SG-03 (ops-toolkit `_meta/megagoals/kit-hardening`)

## Problem
The V-model's specialized per-phase reviewers are each narrow by design. Nothing runs a
uniform cross-cutting lens over the WHOLE assembled work at the final boundary, and
nothing proposes enhancements beyond what was scoped. ADR-0028 P5/P6 call for both, as
ONE configurable generic advisor with two modes, added ON TOP of the specialized
reviewers (2026-07-01 refinement: additive, not a replacement).

## Decision
Add one `advisor` agent (named-noun form, ADR-0029) with two modes:
- **critique (P5)** -- an extra cross-cutting review lens dispatched on top of the 3
  specialist lenses in `/kit:review-team` (Step 2b). KIT DEFAULT, additive, advisory.
- **over-suggest (P6)** -- a generative pass surfaced to the human just before the
  final review, proposing additional ideas/sub-goals. Dispatched at the ship/mega
  final boundary (SG-08 consumes it). Proposals only.

Read-only tools (ADR-0005). Its `model:` (default `sonnet`) is the cheap-first tier
knob so a kit-default lens never silently burns opus every run. Gated by the SG-01
`agent-effectiveness` validator.

## Acceptance criteria
- AC1: `agents/advisor.md` exists, conforms to ADR-0029 (named-noun), read-only tools only.
- AC2: both modes (critique/P5 + over-suggest/P6) are documented in the agent + WORKFLOW.md.
- AC3 [additive]: the advisor does NOT replace the specialized reviewers -- `/kit:review-team` still dispatches the 3 specialist lenses AND adds the advisor (Step 2b).
- AC4 [kit-default]: the advisor is wired as a default (not opt-in) at the final boundary.
- AC5 [tier knob]: the advisor's model tier is a config knob (default sonnet, cheap-first).
- AC6 [gated]: `bash tests/test-agent-effectiveness.sh agents/advisor.md` passes (the SG-01 gate).

## Tasks
- T1: author `agents/advisor.md` (two modes, read-only, tier knob).
- T2: wire critique into `commands/review-team.md` Step 2b + document both modes in WORKFLOW.md.
- T3: roster sync (MANUAL.md + docs/architecture.md).
- T4: `tests/test-advisor.sh` covering AC1-AC6.

## Verification
```
bash tests/test-advisor.sh                          # both modes; additive; kit-default; tier knob
bash tests/test-agent-effectiveness.sh agents/advisor.md   # SG-01 gate passes
bash tests/test-meta.sh                             # roster + naming-axis green
```
Proof-of-done: table-first run-table with the additive row (specialists still run), the both-modes rows, and the 01-gate pass.

## Review
Integration-branch + gated-final (ADR-0028): targets `mega/kit-hardening`, auto-merges past its own ship-gate; the single human review runs at the final `-> master` PR.

## Out of Scope
- The specialized per-phase reviewers (untouched; advisor is additive).
- The right-arm agents (SG-04).
- Making the advisor a hard gate or opt-in; a second agent for over-suggest (one agent, two modes).

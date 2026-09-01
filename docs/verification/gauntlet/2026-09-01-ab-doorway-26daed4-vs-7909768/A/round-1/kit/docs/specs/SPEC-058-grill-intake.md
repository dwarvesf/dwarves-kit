# SPEC-058: /kit:grill, the universal intake interview

Status: SHIPPED ([Unreleased])
Lane: full (kit-machinery: WORKFLOW.md + AGENTS.md wiring)
Backlog: ID-049
Branch: feat/north-star-07-grill
Relates-to: PHILOSOPHY §6 N1/N3, SPEC-057 (the 11 types whose banks this ships), SPEC-054 (type routing), grill-with-docs by Matt Pocock (the absorbed source)

## Problem

The maintainer's pre-kit workflow had a grilling step: before any work, the LLM interviewed him
until the task was actually understood, and the answers were written down. The new intake
(classify -> lane/loop -> Done=) lost it: /kit:think challenges an IDEA (BUILD only) and
/kit:design explores a SOLUTION (opt-in), but nothing gathers REQUIREMENTS, for any type, and
nothing writes the answers where the second brain can find them later.

## Decision

A new command `/kit:grill`, slotted between type classification and the phase-0 done
definition, for every type (tiny lane exempt):

- **One question at a time, each with a recommended answer** (the operator corrects rather than
  composes). Mechanics absorbed from mattpocock/skills `grill-with-docs`.
- **Question banks shaped per work type** (all 11): an incident grill asks what fired and what
  changed; a research grill asks scope and success; a feature grill asks behavior and edges.
- **Contradiction checks**: claims are cross-referenced against the repo before being accepted.
- **Write-as-you-go**: a resolved term -> the repo glossary (CONTEXT.md if present); a resolved
  decision meeting the 3-criteria bar (hard to reverse + surprising without context + genuine
  trade-off) -> a sparse ADR; the Q&A digest -> the goal draft's Context. Never batched.
- **Exit**: dependencies resolved, or the operator says enough. The answers are the raw
  material for the `Done =` line that phase 0 defines next.

Altitudes stay distinct: grill = requirements (what IS this), think = challenge (should we),
design = solution (how). A full-lane spec-feature may run all three, in that order.

## Acceptance criteria

- AC1: `commands/grill.md` exists with 11 type-shaped question banks + the four mechanics above.
- AC2: AGENTS.md task loop routes classify -> grill -> Done=; assign.md invokes the grill before
  the Done= requirement; WORKFLOW phase-0 lead-in names the grill.
- AC3: README credits cite the source; the command table + architecture inventory include grill
  (counts updated, parity kept).
- AC4: meta pins guard the command's heading + the three wiring legs; negative control recorded.
- AC5: adversarial review run on the diff; verdict recorded here.

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | command completeness | `grep -cE '^### (incident|reconcile|operate|planning|learning|eval|research|doc|migration|data-tool|spec-feature)$' commands/grill.md` == 11 |
| 2 | wiring | `grep -qF 'kit:grill' AGENTS.md && grep -qF 'kit:grill' commands/assign.md && grep -qF 'grill' WORKFLOW.md` |
| 3 | inventory parity | architecture.md total updated; meta suite green (no count drift) |
| 4 | negative control | drop the grill step from AGENTS.md -> intake pin RED; restore |
| 5 | review | kit:reviewer on the diff; verdict + fixes recorded in ## Review |

## Rollback

`git revert`. One new command + doc wiring; no lib change, no host state.

## Review

Date: 2026-06-10. Reviewer: kit:reviewer subagent (correctness + consistency lens), probed with
live greps + full meta suite. Round-1 verdict: **FIX-FIRST, 7/10**. Core passed (11 banks
correct + type-appropriate, three wiring legs consistent, no ordering contradiction with the
SPEC-057 wave, altitude mapping clean, source fidelity + citation verified, inventory
25/36 exact, 413/413). Findings, all fixed same-PR:

1. MEDIUM, CHANGELOG implied an automated negative control; the control was run MANUALLY during
   build (the AGENTS grill block sed-dropped -> SPEC-058 pin RED (1 FAIL) -> restored -> 413/413
   green). Recorded here; CHANGELOG rephrased honestly.
2. MEDIUM, this section was a placeholder while Status said SHIPPED; filled (this text).
3. LOW, ID-049 BACKLOG row said executing while the spec said SHIPPED; flipped to shipped via
   `backlog.sh set` (consistent with the wave's other rows).
4. LOW, assign.md called /kit:think "the existing idea-griller", a name collision with
   /kit:grill; renamed to "the 6-forcing-questions idea challenger".

Verdict after fixes: SHIP.

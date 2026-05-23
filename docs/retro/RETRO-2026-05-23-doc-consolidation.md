# Retro: documentation consolidation (ID-033 / I1: operating-manual integration)
Date: 2026-05-23
Sprint: single session, 2026-05-23 (goal-loop continuation: map -> merge x4 -> verify -> retro)

## Why
The kit had grown a cluster of narrative explainers that each re-sliced the same
intake-to-shipped machine from a different angle, cross-linked with "see that other doc
for the real answer" relays. A reader could not tell which file owned what, and any
workflow change had to be mirrored across four to seven docs. The maintainer had already
filed this as backlog **ID-033** ("I1: operating-manual integration: fold the /goal loop +
the orchestration layer into one coherent operating manual"). This run executes that.

## What merged into what (and why)

| Folded (deleted) | Into | Why |
|---|---|---|
| `RUNBOOK.md` | `MANUAL.md` "## Troubleshooting and recovery" | "When it breaks" is operator content; MANUAL already carried Debug mode + Logs, which RUNBOOK duplicated. |
| `docs/ORCHESTRATION.md` | `WORKFLOW.md` "## Flow and loop reference" | ORCHESTRATION was "the rules contract this manual visualizes". The diagrams are the visual layer of the contract, not a second doc. Its duplicate lane/spine tables were dropped; the net-new diagrams, the 3 engine loops, the alt-flows, the hard-stops table, and the quick-reference were kept. |
| `docs/PLAYBOOK.md` | `MANUAL.md` "## Operator scenarios" | Scenario -> trigger -> response is operator usage; it belongs beside the command reference. |
| `docs/operating-layer-vision.md` | `docs/architecture.md` "## SDLC state machine" | The enduring artifact was the state machine (states, transitions, sub-machines, hard-stops-as-guards), a model; architecture is the models doc. The vision prose, the 15-scenario catalog, the gap analysis, and the kickoff path were retired as historical (the gaps they tracked, SPEC-026 / SPEC-027, shipped). |

## Before / after
- Explainer set (root + `docs/` top-level narrative, excluding the contracts README/AGENTS/CLAUDE/CONTRIBUTING/PHILOSOPHY and the ledgers): **8 -> 4**.
- Survivors, each answering one question no sibling answers:
  - `WORKFLOW.md`: the lifecycle contract (cycle, lanes, gates, V-model, spine, + flow/loop diagrams).
  - `MANUAL.md`: the operator reference (commands, hooks, agents, natural-language scenarios, troubleshooting).
  - `docs/architecture.md`: the WHAT/HOW (components, data flow, the SDLC state machine, deps).
  - `docs/ABSORPTION.md`: the upstream-absorption ritual (left standalone; distinct job, heavily test-guarded).

## What was NOT touched (scope fence held)
- Contracts: README, AGENTS.md, CLAUDE.md, docs/PHILOSOPHY.md, CONTRIBUTING.md (pointer updates only).
- Ledgers: docs/specs, docs/decisions, docs/retro, docs/research, docs/handoff, docs/absorption, CHANGELOG, _meta/BACKLOG. The BACKLOG "Source" provenance entries that name the now-folded docs are point-in-time and stay true; **ID-033 should be marked done by the maintainer at ship** (the goal fenced off BACKLOG writes).

## Verification
- `tests/test-meta.sh` 311/311 exit 0; `tests/test-hooks.sh` 120/120 exit 0, after every merge.
- One test guard moved: the BUILDING -> SPECIFYING amend-row check (SPEC-027) now greps `docs/architecture.md` instead of the folded vision doc; the row was preserved verbatim so the guard still has teeth.
- Dangling-reference check: no live doc references any of the four deleted files. All in-doc pointers (WORKFLOW header, MANUAL header + execute card, CLAUDE.md, README "Project structure") were repointed in the same step as each delete.

## What worked
- Incremental: one merge at a time, both suites green before the next. The test guards (especially WORKFLOW's CYCLE_PHASES / HANDS_OFF / doc-impact sed-ranges) caught nothing because new content was appended outside those ranges by design.
- Reading the test suite first mapped which docs were load-bearing (locked to a job) vs. free to fold, which set the target shape before any edit.

## What to watch
- `WORKFLOW.md` (~690 lines) and `MANUAL.md` (~520 lines) are now large single-purpose docs. That is the intended trade (one authoritative doc per question beats four overlapping ones), but if either grows another job, split on the job boundary, not back into angle-docs.
- Not committed: this is a multi-feature branch (`docs/backlog-reeval`) with the SPEC-036 work also uncommitted; ship structuring is a maintainer call.

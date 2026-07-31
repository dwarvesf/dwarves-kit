# SPEC-206: /kit:prototype, the throwaway-spike beat

Status: Draft · 2026-07-31 · Owner: Han
Lane: normal
Relates-to: docs/research/2026-07-31-mattpocock-trio-adoption.md §3+§4 (adoption design;
board row ID-448), SPEC-205 (sibling absorb), ID-450 (/kit:wayfind, whose prototype
tickets need this command as their executor)

## Problem

The cycle goes straight from prose (think/design) to contract (spec). When a
design question resists prose (a state model that only feels wrong once pushed
through real cases, a layout choice argued in the abstract), the kit has no
sanctioned way to answer it with throwaway code. Spikes happen anyway,
unmarked, and either rot in main or vanish with their evidence.

## Solution shape

One new command, `commands/prototype.md`, ported from mattpocock/skills
prototype (MIT: router + LOGIC.md + UI.md folded into one body, re-voiced):

1. **Router**: the question decides the shape. Logic/state question -> the
   logic branch (pure portable module driven by a full-frame TUI). "What
   should this look like" -> the UI branch (3-5 structurally different
   variants on one route, `?variant=` param, prod-gated floating switcher).
   Wrong branch wastes the prototype; ambiguity defaults to the surrounding
   code and states the assumption.
2. **Shared rules**: throwaway from day one and named so; one command to run;
   no persistence by default; no tests/polish; surface full state after every
   action.
3. **Capture contract (kit-adapted)**: fold the validated decision into the
   owning brief/spec section, commit the prototype to a `prototype/<name>`
   branch out of master, and leave a context pointer on the owning board row
   or spec. Master keeps only the validated decision.
4. **Phase wiring**: opt-in beat beside `/kit:design`, advisory, HITL by
   contract (the human drives the prototype; the agent never answers the
   design question for them). Gate grammar: `record <rid> Prototype ran`.
   The WORKFLOW.md phase-table row ships with ID-450's wiring change, not
   here (this spec adds the command only, so the lane stays normal).

## Out of scope

WORKFLOW.md edits (ID-450); any lib/ or hooks/ change; a proof-of-done
obligation for prototype branches (class inert: nothing behavioral lands on
master).

## Verification

- `commands/prototype.md` exists with both branches and the capture contract
  (`grep` for "prototype/<name>", "?variant=", "pure", "throwaway").
- `bash tests/test-docs-wiring.sh` passes.

## After state

A design question can be answered by a marked, runnable spike whose evidence
survives on a `prototype/<name>` branch, and wayfind's prototype tickets have
an executor.

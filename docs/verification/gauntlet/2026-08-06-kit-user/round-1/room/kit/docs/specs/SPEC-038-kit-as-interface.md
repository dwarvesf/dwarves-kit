# SPEC-038: Kit as interface, not a command catalog

Status: VALIDATED
Lane: normal
Backlog: ID-033 (re-opened 2026-05-23; drop reversed)
Branch: docs/kit-as-interface

## Problem

Using the kit currently means learning commands. `MANUAL.md` opens with `## The commands` and ~240 lines of one-section-per-`/kit:` reference before the reader reaches the part that matters for driving it: `## Operator scenarios (what you say -> what happens)` at line 250 and the cheat-sheet at line 358. `README.md` leads with install plus a numbered command list (`## Your first cycle`, `## Workflow`). The result is that a user must memorize a catalog instead of stating intent and letting the orchestration layer run the commands. The intent-first interface is present, but buried, so in practice the kit reads as a command list.

This is the unmet intent of ID-033. The 2026-05-23 drop was wrong: it treated "the orchestration docs were folded" as "the docs are interface-first." They are not.

## Solution

Make the intent-first map the spine of the operating docs. The user scans by what they want to do, not by command name. Commands stay documented but become a reference the kit invokes, not the entry point.

**Chosen: intent-first map as spine (Approach A).** Promote the existing "what you say -> what happens" content to the top of `MANUAL.md`; demote the per-command catalog to a clearly-labeled reference appendix; give `README.md` a talk-to-it opening. Reuses material already written (no duplication: the cheat-sheet is moved, not copied).

**Rejected: front-door-only rewrite (B)** as too cosmetic (body still a catalog). **Rejected: single conversational front door (C)** as a large reorg that reverses the deliberate AGENTS/WORKFLOW/MANUAL/architecture split and risks doc drift.

## Scope

In: `MANUAL.md` structure, `README.md` opening, one `tests/test-meta.sh` guard.
Out: `WORKFLOW.md` and `docs/architecture.md` (they are internals, stay as-is); AGENTS.md (already intent-first; no change beyond a pointer if needed); no command behavior, hook, or agent changes; no new commands.

## Tasks

- [ ] `MANUAL.md`: add a top spine section `## Drive it by intent (start here)` directly after the intro, containing a one-paragraph "say what you want; the kit runs the commands" framing, the cheat-sheet table (moved up from its current location, not copied), and pointers down to `## Operator scenarios` (the detailed playbook) and the command reference (the lookup).
- [ ] `MANUAL.md`: remove the cheat-sheet from its old location so there is exactly one copy (kit no-duplication rule).
- [ ] `MANUAL.md`: retitle `## The commands` to `## Command reference (the kit invokes these from your intent; you rarely type them)` so the catalog reads as a lookup, not the entry point.
- [ ] `README.md`: reframe the opening so it leads with driving-by-intent plus a one-line example, before install / first-cycle / workflow; keep install and the first cycle (newcomers need them) but show the intent path alongside.
- [ ] (lead, at convergence) `tests/test-meta.sh`: add a guard asserting (a) in `MANUAL.md` the intent map ("what you say") appears before the command reference heading, and (b) `README.md`'s opening contains the talk-to-it framing. Hands-off for the worker.

## Verification

`bash tests/test-meta.sh` exits 0. A cold read of `MANUAL.md` hits the intent map before any command catalog; a cold read of `README.md` learns "say what you want, the kit drives" before any command list.

## After state

- `MANUAL.md`'s first H2 after the intro is the intent map, not `## The commands`.
- There is exactly one cheat-sheet table in `MANUAL.md` (moved, not duplicated).
- The command catalog H2 is retitled to signal it is a reference, not the entry point.
- `README.md`'s opening states you drive by intent, with an example, before the command/workflow content.
- A meta-test pins the intent-map-precedes-command-reference ordering, so the catalog cannot creep back to the top.
- `tests/test-meta.sh` passes.

## Touches

- `MANUAL.md`
- `README.md`

(`tests/test-meta.sh` and `_meta/BACKLOG.md` are hands-off shared surfaces per WORKFLOW.md; the lead writes them at convergence, not the worker.)

## Open questions

- Should AGENTS.md get a one-line pointer to the MANUAL intent map, or stay untouched? (Lean: untouched; it is already intent-first and is the tool-agnostic contract, not the operator UX.)

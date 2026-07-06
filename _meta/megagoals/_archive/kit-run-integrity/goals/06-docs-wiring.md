# Sub-goal 06: docs-wiring (+ no-orphan check) , HELD for Han

**Merge policy:** gated-final (HELD for Han , this is the operator's click, per merge-autonomy gated-final)
**Time budget:** 2-4 hours.
**Proof:** run-table: each of 01-05 is reflected in the docs that govern it (AGENTS.md / WORKFLOW.md / CLAUDE.md / the relevant ADR / the affected READMEs) , a doc-vs-code check that every new gate/emit is documented where an agent would look for it · the NO-ORPHAN check: every new gate/emit proves a LIVE invocation path (01's marker is emitted by a real gate; 02's reservation is called by the wavefront path; 03/04 gates are actually hooked into the lifecycle; 05's generator is invoked) , a defined-but-never-dispatched gate/emit is a BLOCKING finding · `kit:doc-verifier` (or equivalent) passes. No new behavioral claim beyond docs, so a coverage-delta row is not owed; the no-orphan check is the proof.
**Depends on:** 01, 02, 03, 04, 05 (ALL). Docs-last: reflect the final wired state. Branches off master after 01-05 merge.
Model: sonnet
Effort: medium
**Branch:** feat/kri-06-docs-wiring
**PR base:** master (post-05-merge)

## Outcome

The docs wire 01-05 into the kit's governing surfaces so an agent (or a human) discovers them where they would look, AND a no-orphan check proves nothing shipped orphaned. Wire: the gate-outcome marker (01) into wherever the ledger/marker convention is documented (AGENTS.md task-loop / CLAUDE.md / the ADR that owns the marker set); the spec-race reservation (02) where spec-next / the wavefront is documented; the advisory coverage-delta + mutation-smoke gates (03/04) into WORKFLOW.md's lanes + gate-at-each-phase-boundary AND the advisory-vs-block boundary (flag them advisory, name the block-promotion path as Han's call); the generated proof-table (05) into the proof-of-done / SPEC-016 docs. Then the no-orphan wiring check: every new gate/emit is proven to be actually invoked, not merely defined.

## Quality bar

Docs-last is deliberate (the kit-face lesson: docs that predate the final wiring go stale). Reflect the FINAL merged state of 01-05, not the plan. The NO-ORPHAN check is the load-bearing artifact: it is not a doc, it is a verification that each new surface has a live caller (a `grep`/dispatch-trace proving 01's marker is emitted, 02's reservation is called, 03/04 are hooked, 05 is invoked); a defined-but-never-dispatched surface is a BLOCKING finding that sends work back to the owning sub-goal, not a doc note. Surgical doc edits , touch only what 01-05 changed; do not refactor adjacent docs.

## How to close the loop

`bash lib/lane-classify.sh classify "wire the kit-run-integrity gates/emits into the governing docs and run a no-orphan check"` then run that lane (doc type-loop). No `/spec` design block needed (docs reflect merged behavior); read each of 01-05's merged diff + PR body and update the doc that governs it. Run `kit:doc-verifier` (docs match code) + the no-orphan check (every new gate/emit has a live invocation path). Record gates via `bash lib/gate-ledger.sh record`. HELD: open the PR, do NOT merge , it is Han's click (gated-final). Assumptions: ROADMAP `## Assumptions` (the cross-cutting wiring gate).

**Done =** 01-05 are each reflected in their governing doc (doc-verifier passes), the no-orphan check confirms every new gate/emit has a live invocation path (zero orphans, else a blocking finding routed back), the PR is OPEN and HELD for Han, gates recorded, committed at phase boundaries.

## Scope edges

**In:** the doc edits (AGENTS.md / WORKFLOW.md / CLAUDE.md / the relevant ADR / affected READMEs) reflecting 01-05, the no-orphan wiring check, doc-verifier.
**Out:** any behavioral change (docs-only + a verification); merging (HELD for Han).
**Not:** a design change; refactoring adjacent docs (surgical); promoting 03/04 to blocking (that is Han's separate call, only NAMED here); merging without Han's click.

## Where to look

`AGENTS.md` (the task-loop + the marker/ledger references , where 01 + 02 belong), `WORKFLOW.md` (the lanes + the gate at each phase boundary + the advisory-vs-block boundary , where 03 + 04 belong), `CLAUDE.md` (the CC layer , hooks/commands if any changed), `docs/decisions/` (the ADR that owns the marker set / the gate set , find the right one; add a short entry if 03/04 warrant one), `docs/specs/SPEC-016*` (where 05 belongs), each of 01-05's merged PR body (the source of truth for what to document), `kit:doc-verifier` (the doc-vs-code check).

## PR body

Docs-wiring for kit-run-integrity: reflect 01-05 (gate-outcome emit, spec-race reservation, advisory coverage-delta + mutation-smoke gates, generated proof-table) into the governing docs (AGENTS.md / WORKFLOW.md / CLAUDE.md / ADR / READMEs), plus a no-orphan wiring check proving every new gate/emit has a live invocation path (a defined-but-never-dispatched surface is blocking). Docs-last (reflects the final merged state). 03/04 documented as ADVISORY; the block-promotion path is named as Han's call, not taken. HELD for Han's click (gated-final). Verify: doc-verifier + no-orphan check. Roadmap: ops-toolkit `_meta/megagoals/kit-run-integrity/ROADMAP.md`.

## Notes

<empty>

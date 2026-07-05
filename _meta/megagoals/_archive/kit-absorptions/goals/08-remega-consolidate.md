# Sub-goal 08: remega-consolidate (Consolidate mode in plan-for-mega-goal)

**Merge policy:** gate
**Time budget:** 2-3 hours of loop work
**Proof:** full reviewable proof: the Consolidate mode section complete in the skill + a READ-ONLY DRY-RUN consolidation report over two REAL archived same-project mega-goals (e.g. the safari-net family) showing inventory, overlap analysis, dedupe/merge decisions, the re-sliced Touches, and provenance lines; the read-only NC (archives byte-identical after the run).
**Design:** bearing
Model: opus
**Depends on:** 02 (same dotfiles stack)
**Branch:** `feat/remega-mode`
**PR base:** `feat/contracts-batch`

## Outcome

ID-259 whole: `plan-for-mega-goal` gains a **Consolidate mode** (input: 2+ same-repo mega-goal scaffold dirs; output: ONE new scaffold + superseded markers on the old ones). The seven-step procedure from the design note, verbatim intent: inventory (done sub-goals import as `[x] PR #N`, never re-run; in-flight finishes under its old mega or imports claimed); overlap analysis (dispatch-gate Touches intersection + semantic dedupe); re-decompose the UNION (dep graph from actual code deps; Touches re-sliced per module, the step that CREATES wave parallelism); front-load clarifications ONCE over the union; spec-number block reserve + release; provenance per sub-goal (`from: mega-A/SG-03 + mega-B/SG-01`); supersede-not-delete (`superseded_by:` header, archive per lifecycle, board rows collapse). Plus the when-NOT table (>=80% done; different postures/tenants; under ~2x3 overlapping remaining).

## Quality bar

Planning machinery gets the smart tier (Model: opus, per the routing rule: this is design-dominant authoring). The mode composes the skill's EXISTING beats over a union input, no new scaffold shapes. The dry-run proof is the bar: if the report's decisions read wrong on real archives, the mode is wrong.

## How to close the loop

- The mode section lands in the skill GUIDE (+ a one-line pointer in SKILL.md), chezmoi-clean.
- DRY-RUN: run the mode's procedure read-only against two real archived megas; commit the consolidation REPORT as the sample artifact.
- Read-only NC (load-bearing): shasum the archive dirs before/after, byte-identical, asserted in the run-table.
- dotfiles NOT kit-adopted: proof in the PR body. Gate: Han reviews the mode + the dry-run report before merge.

**Done =** mode section complete + the real dry-run report committed + the read-only NC green. Held for Han.

## Handoff on completion

1. Flip ROADMAP box + PR #, emit the gate banner. 2. HOT `HANDOFF.md`: 09 (kit stack) may now mirror; name the knobs to mirror. 3. `DECISIONS.md`: any procedure refinement discovered against the real archives. 4. EXIT.

## Scope edges

**In:** the skill's GUIDE/references (dotfiles), the dry-run report artifact.
**Out:** `/kit:mega` mirror (09); actually consolidating any LIVE mega-goal (dry-run only); ID-258's scheduler practice (nothing to build, the runbook exists).
**Not:** a consolidation BINARY/lib (procedure + judgment, manual-first); auto-superseding without operator confirmation.

## Where to look

`research/2026-07-04-megagoal-portfolio-scheduling.md` §2 (the full design); `_meta/megagoals/_archive/` for real candidates; dispatch-gate.sh for the Touches intersection reuse.

## PR body

Consolidate mode (remega): re-decompose overlapping same-project mega-goals into one, waves created by Touches re-slicing; proven by a read-only dry-run report over two real archived megas. HELD FOR REVIEW. Stacked on contracts-batch. Covers ID-259 (ID-258 adopted-as-practice, nothing to build).

## Notes


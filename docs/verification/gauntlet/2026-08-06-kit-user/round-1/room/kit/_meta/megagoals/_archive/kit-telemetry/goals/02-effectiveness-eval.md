# Sub-goal 02: effectiveness eval (SPEC-073, executed)

**Merge policy:** auto
**Time budget:** 3-5 hours.
**Proof:** the eval report itself , per-criterion verdict table (SPEC-073's design), each verdict citing the ledger record / proof file / audit section it rests on. A verdict with no citation is not a verdict.
**Depends on:** 01 (evaluate the DURABLE corpus, not the wipeable one).
Model: opus
Effort: high
**Branch:** feat/kit-telem-02-eval
**PR base:** feat/kit-telem-01-ledger (stacked on 01)

## Outcome

SPEC-073 (telemetry + feedback-loop + proof-of-done effectiveness eval, VALIDATED since 2026-06-10, execution parked for real data) has RUN. Input corpus: the 8 kit-harden run ledgers + their captured proofs + `ops-toolkit/research/2026-07-02-process-effectiveness-audit.md` (consume its 60-day proof-effectiveness evidence; do NOT redo git forensics). Output: `docs/research/2026-07-02-effectiveness-eval.md` with per-criterion verdicts and a ranked fix list. Kit board ID-067 flips to shipped.

## Quality bar

Evidence-cited or it does not count. Where the ops audit already answered a criterion (e.g. proof-of-done = forcing-function, read-once), CITE and move on. Honest nulls are findings ("criterion X not measurable with N=9 runs" beats a vibes verdict). Report-first: small classifier/proof fixes may ride inline; structural changes become board rows, never scope creep.

## How to close the loop

SDD: `/spec` is largely done (SPEC-073 IS the spec); run `/spec-validate` against it if it has drifted, else proceed per its design. Then execute the eval and:

```
cd dwarves-kit && ls docs/research/2026-07-02-effectiveness-eval.md   # exists
rg -c "verdict" docs/research/2026-07-02-effectiveness-eval.md        # per-criterion table present
```

Every SPEC-073 criterion has a row: verdict + citation. Gate-ledger records per phase as usual.

**Done =** the eval report exists with every SPEC-073 criterion carrying a cited verdict, ID-067 flipped in this PR, and any inline fixes covered by their own test.

## Handoff on completion

1. Flip 02's ROADMAP box, PR # + SHA; flip kit board ID-067 -> shipped IN this PR.
2. HOT `HANDOFF.md`: next = 03 or 04 per roadmap; carry the eval's ranked fix list pointer.
3. WARM `DECISIONS.md`: the eval's top findings (one line each).
4. Report IN records, EXIT.

## Scope edges

**In:** executing SPEC-073's design, the report, small inline fixes with tests.
**Out:** the lane-rule audit (03, sibling); the dashboard (04); re-running the ops audit's git forensics.
**Not:** redesigning SPEC-073; new telemetry instrumentation; changing the proof-of-done format wholesale.

## Where to look

`docs/specs/SPEC-073-telemetry-eval-design.md` (the design , read FIRST), the migrated run ledgers (01's new path), `docs/verification/` proofs from the kit-harden wave, the ops audit file, kit board ID-067.

## PR body

Executes SPEC-073 on the kit-harden corpus + the 2026-07-02 ops audit; per-criterion cited verdicts + ranked fix list at `docs/research/2026-07-02-effectiveness-eval.md`. Board ID-067. Stacked on #<01's PR>; review after it. Roadmap: ops-toolkit `_meta/megagoals/kit-telemetry/ROADMAP.md`.

## Notes

<empty>

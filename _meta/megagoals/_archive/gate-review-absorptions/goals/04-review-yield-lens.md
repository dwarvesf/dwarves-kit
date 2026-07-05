# Sub-goal 04: review-yield-lens (rejected-findings adapter + FP-rate query)

**Merge policy:** auto
**Time budget:** 2 hours of loop work
**Proof:** full reviewable proof: golden fixture (seeded rejected-findings files + kit_gates rows -> exact expected `review-yield` table); honest-zero NC (no review emits + no ledger files -> zero rows, clean exit, never a crash or fabricated rate); real run over ops-toolkit + dwarves-kit captured honestly (low-n noted as low-n); coverage-delta row.
**Design:** bearing
**Depends on:** 02 MERGED (verify `gh pr view`; the `findings=/rejected=` grammar + ledger-file format are its outputs). Stacked on 03 in the ops chain.
Model: sonnet
**Branch:** `feat/review-yield-lens`
**PR base:** `feat/plannotator-gate-trial`
**Over-test: yes** (a wrong FP-rate would mis-price review lenses and steer gate-attention decisions)

## Outcome

ID-263 ops half, the reader completing 02's emitter family:

(a) **`rejected_findings` adapter** in `tools/ledger-observatory`: walks the repos named in a `LEDGER_OBS_REPOS` list (or reuses the `_meta/boards.txt` registry; pick ONE, record it in DECISIONS; today's config convention is single-repo env vars, so multi-repo is a stated sub-decision, not an on-the-fly call), reading each repo's `docs/verification/rejected-findings.md`; extracts NUMBERS ONLY (repo, lens, n_rejected, first/last date; finding text stays in the repo file), single-sourced schema per the schemas.py pattern.
(b) **`review-yield` CLI query**: FP-rate = rejected/raised, alongside the existing catch data so one table answers "does this lens earn its attention budget". Ground truth about the merged #683 reader (advisor P5, verified): `kit_gates` stores the emit detail as ONE opaque `reason` VARCHAR (no findings/rejected columns), and the review emit is a WHOLE-REVIEW aggregate, never per-lens. Therefore: this query regex-extracts `findings=`/`rejected=` out of `kit_gates.reason` itself (kit_gates' parser stays untouched); the raise denominator is per-RUN; and the per-lens FP-rate is an APPROXIMATION (per-lens numerator over per-run denominator), labeled so in the output. A lens-level emit is a NAMED follow-on row, not this sub-goal. `suppressed=` (SPEC-081 confidence-gate auto-suppression) is a different axis from human `rejected=` and is out of scope for the yield metric; say so in the query docs. Low-n rows labeled low-n, never hidden.
(c) One anomaly hook: FP-rate over threshold on adequate n PROPOSES a lens-conditioning row via the existing propose path (propose-never-autofile).

## Quality bar

Read-only lens over canonical files (the observatory contract: files stay canonical, delete-and-rematerialize holds). Honest-negative discipline: a lens with more rejected than caught reports exactly that. No schema duplication (the known adapters-vs-materialize drift hole; follow the parity note).

## How to close the loop

- Golden fixture with hand-computed expected rates; assert exact table.
- Honest-zero NC proven load-bearing by deliberate break (make the query fabricate a 0.0 row from no data, watch red, restore).
- Real run over both repos, output pasted honestly.
- Over-test: malformed ledger rows skipped-with-count, division-by-zero guard, lens present in file but absent from kit_gates (and inverse); coverage-delta row.

**Done =** golden fixture exact-match + honest-zero NC break-capture + real-run output committed.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: all sub-goals done -> convergence gate. 3. `DECISIONS.md`: FP-rate formula + thresholds. 4. EXIT.

## Scope edges

**In:** `tools/ledger-observatory/` (adapter, schema row, query, anomaly hook, tests, docs per its verification layout).
**Out:** the kit-side emit (02); new detectors beyond the one FP anomaly; dashboarding.
**Not:** reading finding CONTENT into the lens (numbers only); auto-filing backlog rows; touching kit_gates' parser (consume it as-is).

## Where to look

`research/2026-07-04-pxpipe-plannotator-improve-absorption.md` §3 (A3); 02's DECISIONS.md entry (grammar + file format verbatim); `tools/ledger-observatory/docs/` for the adapter/query/anomaly patterns + the schema-parity note; harness-observatory RUN_REPORT for what already landed in the tool.

## PR body

review-yield lens: rejected_findings adapter (counts only) + FP-rate per review lens joined against kit_gates raise counts + one propose-only anomaly. Golden fixture exact-match, honest-zero NC proven by deliberate break, real two-repo run recorded with low-n honesty. Reader for 02's emitter family. Covers ID-263 (ops half).

## Notes

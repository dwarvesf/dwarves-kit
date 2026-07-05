# Sub-goal 04: anomalies-advisor (ceremony + token-runaway + time-to-done advisor)

**Merge policy:** auto
**Time budget:** 1.5-2 hours of loop work
**Proof:** full reviewable proof: fixture-driven assertions per detector (fire + no-fire), the ceremony FP NC, a real `ledger anomalies --table` capture, coverage-delta row.
**Design:** obvious
**Depends on:** 02
Model: sonnet
**Branch:** `feat/lo-anomaly-advisor`
**PR base:** `feat/lo-deviation-rate`
**Over-test: yes** (FP NC load-bearing: a correctly-skipped gate proposed for cutting = the detector teaching bad habits)

## Outcome

`anomalies.py` DEFAULTS + `detect()` extended, keeping the shipped PROPOSE-not-autofile contract, with three detectors: **ceremony** (a gate high-ran + zero-caught over >= N runs proposes CUT/CONDITION, conditioned on the `caught` signal or zero fix-correlation, never a bare skip-rate); **token-runaway** (a run over its token budget, once a token source feeds the lens; degrade to not-armed with a clear message until 05 lands); **time-to-done advisor** (serial-when-parallel: dep-independent sub-goals that ran in separate waves proposes "collapse to one wave, ~X min saved"; slow-gate ranking; kill-churn; discovery-heavy).

Covers: ID-245 change 4 (+ the advisor from the benchmark scope).

## Quality bar

Every detector PROPOSES with the metric embedded in the proposal text (the human judges from the row alone). Thresholds in DEFAULTS, overridable via the existing `--threshold KEY=VALUE` path, listed in `--help`.

## How to close the loop

- Per-detector fixtures: one firing case + one non-firing case each, asserted.
- Ceremony FP NC (load-bearing): a gate with high skip but legitimate reason-coded skips (e.g. ui-design on non-UI runs) is NOT proposed; asserted on fixture.
- Advisor: fixture with two dep-independent sub-goals run serially fires serial-when-parallel with a plausible minutes-saved estimate; a genuinely dependent pair does NOT fire.
- `--propose` stages rows into the cc-backlog staging buffer (existing path), duplicate-safe; asserted.
- Real capture: `uv run ledger anomalies --table` post-rebuild.
- Kit lane + gate-ledger records before push.

**Done =** all fire/no-fire fixtures + the ceremony FP NC asserted green, real capture committed, coverage-delta row in the canonical proof.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 05-sessions-digest; note token-runaway's not-armed state awaiting the sessions table. 3. `DECISIONS.md`: threshold defaults + the ceremony conditioning rule. 4. EXIT.

## Scope edges

**In:** `anomalies.py`, its tests, proof docs.
**Out:** the sessions adapter (05); any CLI command changes beyond anomaly listing.
**Not:** auto-filing; a scheduler; cutting any real gate (the detector proposes, Han decides).

## Where to look

`anomalies.py` (DEFAULTS/detect/stage_proposals shipped shape); `docs/benchmark-followup.md` change 4; gate-yield output from 02; the advisor detectors in `research/2026-07-03-megagoal-execution-hygiene.md` + ledger duration data.

## PR body

Ceremony + token-runaway + time-to-done advisor detectors, propose-not-autofile preserved. Stacked; review after deviation-rate. Verification per proof-of-done (fire/no-fire fixtures + FP NC). Covers ID-245 (3/3).

## Notes


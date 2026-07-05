# Sub-goal 05: mega-durations

**Merge policy:** auto
**Time budget:** 1-2 hours once unparked
**Proof:** OVER-TEST: golden-fixture run-table + honest-zero negative control + one real run over the live ledgers with the row count named (numbers with an n)
**Design:** bearing (metric design against the REAL kit_gates schema; the gate-review advisor pass already caught one metric designed against an imagined schema, do not repeat it)
**Depends on:** PARKED. Unpark ONLY when gate-review-absorptions' 04-review-yield-lens PR is MERGED (its # is on that mega's ROADMAP line 04; verify `gh pr view`). Base on main AFTER that merge. If still unmerged when 01-04+06 are done, leave this unstarted with a blocker fingerprint in NOTES; do NOT build on a conflicting base.
Model: sonnet
**Branch:** `feat/mega-durations`
**PR base:** main (after the dependency merges)

## Outcome

`ledger-observatory mega-durations` answers "where do the 2-3 hours actually go": per-rid wall time (max end_ts - min start_ts) and a per-gate/phase split, over the real kit_gates data. This is the meter the fast-path claims get judged against; until it exists, "megas are slow because of ceremony" is a guess.

## Quality bar

Read the ACTUAL adapter schema first (`tools/ledger-observatory/src/ledger_observatory/adapters.py`, kit_gates columns: rid, gate, outcome, caught, reason, start_ts, end_ts) and design the metric against what is there, including NULL/absent timestamps (rows without end_ts are excluded and COUNTED as excluded, shown in the output). Honest-zero: no qualifying rows -> zero rows, never a fabricated duration. Every aggregate prints its n.

## How to close the loop

- New query in the observatory CLI following the existing query pattern (gate-yield is the template: data-driven GROUP BY, no whitelist).
- Golden fixture: a small ledger set with known durations; expected table asserted.
- NC: fixture stripped of end_ts -> "0 rids with complete timestamps (N rows excluded)" and exit 0.
- Real run over live ledgers captured in proof-of-done (this is the first actual answer to Han's 2-3h question; paste the table).

**Done =** fixture test green + honest-zero NC green + the live table with its n captured in proof-of-done.

Kit-adopted repo: record gate-ledger phases before push.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. Overwrite HANDOFF.md per whatever remains (usually the convergence gate).
3. Append to DECISIONS.md: the exclusion rule for incomplete timestamps + any schema surprises.
4. Report IN the records, then EXIT IMMEDIATELY.

## Scope edges

**In:** the new query + fixture + docs row in the observatory's README/proof index.
**Out:** the review-yield query and rejected-findings adapter (gate-review's 04 owns them; you are building on top of its MERGED state).
**Not:** dashboards, scheduled reports, changes to what emits into kit_gates.

## Where to look

`tools/ledger-observatory/src/ledger_observatory/{adapters.py,cli.py}`; gate-review-absorptions ROADMAP line 04 for the dependency PR.

## PR body

- Outcome: `mega-durations` observatory query (per-rid wall time + phase split, honest-zero, n on every aggregate).
- Verification: fixture + NC run-table + the live table (inline).
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes


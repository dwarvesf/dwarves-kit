# Sub-goal 07: mega-review-dashboard

**Merge policy:** auto
**Time budget:** 3-6 hours of loop work
**Proof:** (SPEC-197) 2-3 screenshots of the rendered dashboard for a REAL archived mega (harness-ops or kit-modularity ledger data): the overview, one sub-goal group, one attention state; plus a run-table for the wiring NC (TIER4_CLOSE off -> no render attempted, captured). Rung 2. COVERAGE-DELTA row (over-test on the render's data joins).
**Design:** bearing (a new composition surface over three data sources)
**Depends on:** 02
Model: sonnet
**Branch:** `feat/loop-07-mega-dashboard`
**PR base:** master

## Touches

lib/stats (a compose entry or `--surface artifact` reuse), lib/queue/orchestrate.sh (TIER-4 close hook point), lib/mega.sh (status data reuse), docs/specs/, tests/

## Outcome

`mega review --html <slug>` (final verb per ADR-0034 §4) renders ONE self-contained static HTML page per mega from live data, no daemon, recomputable: per-sub-goal groups showing gate rows (ran/skip/override with reasons), proof-of-done links, PR + CI + merge state (gh), token totals, OUTCOME wall times (SG-02's data), attention-colored so what needs eyes reads at a glance, plus ONE footer row of harness-wide starvation counters (staged candidates + oldest age, learned-ledger queued count, unpaid debt count), read best-effort from the consumer files, honest-dash when absent: the dashboard is the one surface with a guaranteed reader, so the counters the Learn leg surfaces must appear HERE, not only in a text digest. TIER-4 close generates it automatically next to RUN_REPORT.md; it is the surface Han eyeballs before the gated-final click. A projection, never a stored source of truth (SPEC-182 discipline).

## Quality bar

Glanceable sign-off in under a minute: green groups collapse visually, the one red thing is unmissable. Boring, diffable HTML (the stats artifact formatter's discipline); opens from `file://`, zero JS dependencies beyond what the formatter already ships.

## How to close the loop

1. Spec; Design block = the data-source join diagram (ledger + gh + proof paths).
2. Build the compose; render for an archived mega with real ledgers; screenshots (overview / group / attention state).
3. Wire at TIER-4 close behind the existing TIER4_CLOSE knob; NC: knob off -> no render, run captured.
4. Honest-empty: a mega with no ledger rows renders a page saying so, never fabricated rows (captured).
5. Suite green.

**Done =** dashboard rendered from real archived-mega data (screenshots committed under docs/proof/) + TIER-4 wiring NC + honest-empty NC + suite green.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HANDOFF.md: 10 needs the dashboard path for its README section. 3. DECISIONS.md: output location convention (scaffold dir vs docs/verification/generated/). 4. EXIT.

## Scope edges

**In:** the compose verb, TIER-4 wiring, screenshots, spec.
**Out:** a live/served variant (Hermes cards are the NOTES successor), historical backfill, new lenses.
**Not:** a web server, auto-refresh, sign-off state STORED in the page (the gate click stays in the PR/merge flow).

## Where to look

`lib/stats` render/artifact formatter (SG-03 of harness-observatory shipped it), the auto-improvement design doc's "review mechanism" table, `lib/queue/orchestrate.sh` `_tier4_close`, `lib/mega.sh` (claim-vs-git reconcile data), RUN_REPORT.md precedents in the archived megas.

## PR body

`mega review --html`: one static sign-off page per mega composed from ledger + gh + proofs, auto-generated at TIER-4 close (TIER4_CLOSE-gated). Verify: 3 screenshots + wiring/honest-empty NCs in the proof-of-done. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-07.

## Notes

# Absorption proposal: YYYY-MM-external[-N]

Run date: YYYY-MM-DD
Lanes run: A (Credits drift) + B (seed-rescan)
Capability check: WebFetch + gh available? [yes/no, if no -> "external lane unavailable", stop, do not write a misleadingly-empty proposal]

## Candidates (top <=15, ranked)

Rank by rubric total, tie-break by interest-area weight (agents/workflow > QA/UI).

| # | Source repo (URL) | Lane | Interest area | What it is | Rubric /16 | NO-list | 2-phase | Duplicate? | Recommendation | Rationale |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | owner/repo | B | agents | [pattern] | 12 | pass | yes | no | ADOPT | [why] |

## Overflow appendix (gate-passers below the display cap, never dropped)

Every candidate that passed the gate (>=10 + all gates) but fell below the top-15 display cap. The cap orders display; it never decides what passes.

| Source repo | Interest area | Rubric /16 | Recommendation | Rationale |
|---|---|---|---|---|

## Recommend external (binary / runtime-needing candidates)

Good patterns the kit should NOT absorb because they need a binary/paid dep/runtime (PHILOSOPHY section 3). Surfaced, not absorbed.

| Source repo | What it is | Why external |
|---|---|---|

## No drift / no candidates

If a lane found nothing new this run, say so here so this dated file is still the run-history ledger (staleness stays visible).

## Baseline footer (machine-readable, lane-B since-last-run SHAs)

The HEAD SHA of each lane-B seed repo at this run. The next run compares against these to detect "changed since last run".

```
owner/repo=<HEAD-sha>
```

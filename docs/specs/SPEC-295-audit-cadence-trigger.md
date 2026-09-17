# SPEC-295: the audit-loop instances declare a cadence, and one verb says which are due

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Board:** ID-487. **Proof:** `docs/verification/audit-cadence-trigger.md`.

## Problem

`docs/patterns/audit-loop.md` names a driver ladder: one interactive pass, then `/loop` or a
schedule, then the loop-engineering runtime. Eight instances ship in this repo. Not one has
ever wired the cadence rung, so every pass runs when a human remembers it.

Two hand passes of `backlog-reconcile` on 2026-08-31 found 6 stale rows across 96 checked.
None came from malice. Each came from a dependency shipping or a component moving to a
sibling repo while the row stayed put. That is exactly the decay a cadence catches and an
on-demand-only loop does not.

Nothing in the repo records that a pass ran, either. A CLEAN pass ships no branch and no PR,
so even git history cannot answer "when did doc-drift last run".

## Solution

Two pieces, no scheduler.

**1. A `## Cadence` table in `docs/patterns/audit-loop.md`.** One row per instance, carrying
the period (`weekly` 7d, `biweekly` 14d, `monthly` 30d, `quarterly` 90d) and why that period.
The table is the single source of truth: `lib/audit/audit.sh` parses it, so a new instance
becomes schedulable by adding a row, with no second list to keep in sync.

**2. `bin/audit`**, a stable consumer entrypoint over `lib/audit/audit.sh`, three verbs:

| Verb | What |
|---|---|
| `audit due` | per instance: cadence, last run, age, DUE or not |
| `audit cadences` | the declared table as `<instance><TAB><days>` |
| `audit ran <instance> [note]` | record that a pass finished |

The last-run marker is one line in the kit's existing append-only ledger
(`lib/ledger/ledger.sh`, stream `audit-runs.log`). No new store, no new env var. An instance
with no marker reads as DUE, which is the honest answer for a pass nobody has run.

Each instance skill gains a `## Cadence` section telling it to record a finished pass,
including a CLEAN one. Without that the verb would be decorative.

### Not built: the scheduled caller

No cron, no launchd job, no GitHub Actions workflow. `due` is read-only reporting; a human or
a job decides what to do with the list. The caller comes later if the verb proves useful, and
picking it now would guess at a cadence host before anyone has read one report.

### Not built: a reverse completeness lint

`tests/test-audit-cadence.sh` pins the instance set by set-equality, the same precedent as the
bin census. A heuristic that derives the instance set from skill prose was tried and rejected:
every candidate marker (the phrase "An audit-loop instance", a reference to the pattern doc,
the word "scheduled" in the description) matched a different subset of the eight and pulled in
`loop-engineering`, which is the driver, not an instance.

## Acceptance criteria

| Criterion | Check |
|---|---|
| The Cadence table declares exactly the in-kit instance set | test-audit-cadence: census |
| Every declared instance has a `skills/<name>/SKILL.md` | test-audit-cadence: skill directory |
| Each cadence word maps to its period in days | test-audit-cadence: parse |
| Only the Cadence section feeds the instance set | test-audit-cadence: parse NC |
| A never-run instance reports DUE | test-audit-cadence: due |
| Recording a run clears that instance and no other | test-audit-cadence: due after ran |
| A marker older than the period brings the instance back | test-audit-cadence: aged marker |
| `audit ran` refuses an undeclared instance and writes no marker | test-audit-cadence: NC |
| An unknown verb refuses | test-audit-cadence: NC |
| `bin/audit` forwards to `lib/audit/audit.sh` | test-bin-forwarders: audit dispatch |
| `bin/` census includes `audit` | test-bin-forwarders: census |

## Verification

```bash
bash tests/test-audit-cadence.sh
bash tests/test-bin-forwarders.sh
bash tests/test-meta.sh
bash tests/run-all.sh --changed
```

## After state

`bin/audit due` answers which audit passes the cadence has come around for. Nothing schedules
them yet, and the report says so.

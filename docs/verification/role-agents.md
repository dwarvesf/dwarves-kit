# Proof of done: starter role-specialized agent roster (SPEC-111, kit-face wave)

A starter roster of 6 domain specialists (2 workers + 4 reviewers), each gated + provenance-stamped,
with two live dispatch paths (workers -> execute.md 2b-0 reuse via `agent-for`; reviewers ->
review-team domain lens), reconciling the SPEC-089 static-known vs dynamic-novel boundary.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | 6 new domain agents generated, one per applicable role-classify domain, mixed by fit | PASS (2 workers + 4 reviewers) |
| 2 | Existing agents NOT duplicated (security->security-reviewer, generic->Mode-C) | PASS |
| 3 | Each new agent carries `generated-by:` provenance (SPEC-108) | PASS |
| 4 | 4 REVIEWERS pass the mechanical effectiveness gate (read-only, valid tier, on-axis name) | PASS (3/3 each) |
| 5 | 2 WORKERS pass the agent-effectiveness AGENT 4-lens judgment (role-aware) | PASS (both) |
| 6 | WIRING: `agent-for` makes a domain-classified task resolve to THAT worker (reuse-hit source) | PASS |
| 7 | Reviewers have a live dispatch path (review-team domain lens) , no orphans | PASS |
| 8 | On-role fixture: 1 reviewer + 1 worker produce real on-role output | PASS |
| 9 | SPEC-089 boundary stated (spec + WORKFLOW.md); no second router; `generic`->Mode-C | PASS |
| 10 | Roster-sync (MANUAL.md + architecture.md rows) + all 12 CI suites green | PASS |

## Implementation

- `agents/{db-migration,data-etl}-worker.md` (write-capable) + `agents/{performance,api,frontend,infra}-reviewer.md`
  (read-only), each with `generated-by:` + tools/model justification.
- `lib/role-classify.sh`: `agent-for <domain>` (workers -> worker name; reviewers/security/generic -> empty).
- `commands/execute.md` 2b-0 step 2: consults `agent-for` for a deterministic worker reuse hit.
- `commands/review-team.md`: opt-in domain-lens step (dispatch a domain reviewer when the diff touches
  its domain); fixed 3 lenses unchanged.
- `MANUAL.md` + `docs/architecture.md`: 6 roster rows each. `WORKFLOW.md`: the two-path boundary.
- `tests/test-role-classify.sh`: agent-for lookup + generic-empty + reuse-hit chain. `tests/test-meta.sh`:
  SPEC-108 `GEN_ROSTER` expanded to the 11 generated agents (the 6 new ones are generated, not hand-written).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| lookup: workers | `role-classify agent-for db-migration` / `data-etl` | worker names | db-migration-worker / data-etl-worker |
| lookup: reviewers/generic | `agent-for performance` / `generic` | empty | empty (review-team / Mode-C) |
| reuse-hit chain | classify "write a migration...backfill" -> agent-for | db-migration-worker | PASS (test-role-classify 24/24) |
| reviewer gate x4 | `test-agent-effectiveness.sh agents/<r>.md` | 3/3 read-only+tier+name | 3/3 each |
| worker gate x2 | agent-effectiveness AGENT 4-lens | PASS | PASS (both; write tools not flagged) |
| on-role: reviewer | performance-reviewer on an N+1 diff | severity findings + score + catches N+1 | CRITICAL N+1 + 3 more findings + 2/10 |
| on-role: worker | db-migration-worker on an add-column+backfill task | UP + DOWN + batched backfill | up + DROP COLUMN rollback + 10k-batch idempotent backfill |
| roster-sync | `bash tests/test-meta.sh` | green | 651/651 |
| all CI suites | 12 suites | green | all pass |

## Run detail (captured 2026-07-03)

```
$ bash lib/role-classify.sh agent-for db-migration   -> db-migration-worker
$ bash lib/role-classify.sh agent-for performance    -> (empty)
$ D=$(role-classify classify "write a migration to add a column and backfill"); agent-for "$D" -> db-migration-worker
$ for a in performance api frontend infra; do test-agent-effectiveness.sh agents/$a-reviewer.md; done  -> 3/3 each
$ bash tests/test-meta.sh   -> 651/651 ; All meta tests passed.
# on-role fixture (agent-effectiveness AGENT + adopted-body dispatch):
#   performance-reviewer -> CRITICAL: N+1 fan-out (headline) + HIGH SELECT* + MEDIUM slice-prealloc + LOW no-ctx; score 2/10
#   db-migration-worker  -> UP (ADD COLUMN NULL, CONCURRENTLY index) + batched IS-NULL-guarded backfill + DOWN (DROP)
# workers 4-lens: db-migration-worker PASS, data-etl-worker PASS (write tools = worker contract, not over-grant)
# 12 CI suites: hooks, e2e 20/20, review-team-plants, orchestrate, role-classify 24/24, lane-classify 23/23,
#   lane-telemetry 25/25, mega-merge 30/30, ledger-durability 35/35, meta 651/651, meta-agent 72/72, proof-visual 4/4
```

## Notes

- Advisory (worker gate, non-blocking): `db-migration-worker`'s verify leans on the project test
  suite (no dedicated `Bash(alembic*|flyway*|...)` grant) , defensible by design (avoids an unscoped
  bash over-grant); if a repo uses a migration CLI, the dispatching lead grants that pattern. Left
  as-is per the agent-effectiveness rubric's over-grant caution.
- SPEC-089 boundary: `agent-for` returns non-empty ONLY for worker domains (2b-0 reuse); reviewers
  dispatch via review-team; `generic`/unknown -> Mode-C synthesis (the dynamic long tail preserved).

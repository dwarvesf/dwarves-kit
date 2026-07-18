# The usage-telemetry path around the five stages

The kit's improvement cycle is the five stages (ADR-0034, renamed by the 2026-07-18
amendment): **Shape -> Build -> Watch -> Check -> Learn**, feedback closing Learn
back into Shape. This
page does NOT define a new cycle; it names how session-audit rides that loop
for one signal class: usage telemetry from CC session transcripts. One engine,
one truth: where an existing stage verb already owns a step, this tool defers
to it.

```
              (existing stages)                    (this tool's contribution)

 Shape ──► Build ──► Watch                         session-audit run
 ▲                   │                             = the deep Watch pass:
                    ▼                                dated report, owner tags,
                    Check                            metric contracts
                    │
 └────── Learn ◄────┘                              session-audit triage
         (propose gate)                              = a Learn-stage proposer:
                                                     report footer -> kanban
                                                     proposal rows, human accepts
```

## The steps, in stage terms

1. **Watch (collect + report).** Three depths, same stage: `session observe`
   (deterministic parsing, free), `session semantic` (cheap LLM topic signal,
   cron), `session audit run` (expensive agentic deep audit, weekly / on
   demand). The audit writes one dated report; every recommendation carries an
   OWNER (`kit` | `user-habit` | `harness` | `instrumentation`) and a METRIC
   CONTRACT (name, current value, exact re-run command), and the report closes
   with a machine-readable json footer of the same rows. Only HIGH-tier
   findings are stable currency across runs; MEDIUM/LOW are leads.
2. **Learn (propose).** `session audit triage` turns the footer into the kit's
   ONE proposal currency: `## [staged]` blocks appended to
   `_meta/backlog-staging.md` via `lib/learn/staging-format.py` (ADR-0034
   decision 1), byte-compatible with `learn propose` and `stats anomalies
   --propose`. The metric contract rides on `Approach`, the report + owner on
   `Source`. Dedup runs against every staging state (staged/expired/rejected/
   promoted) + the board, so a rejected proposal never returns. Human gate
   unchanged (ADR-0034 decision 2/5): review with `learn drain`, accept with
   `board promote`. Nothing auto-files.
3. **Shape -> Build -> Check (enhance).** An accepted row is ordinary kit
   work through the normal lanes and gates. Nothing special; the audit only
   supplied the evidence and the metric.
4. **Watch again (measure).** The next `session audit run` receives the
   previous report as `{PREV}` automatically and MUST open with a
   metric-by-metric diff: for each earlier recommendation, did its metric
   move? A fix whose metric did not move returns to the Learn gate as a new
   finding, with the failed attempt as context.

## Division of labor inside Watch (why three tools + stats coexist)

| Surface | Reads | Depth | Cadence |
|---|---|---|---|
| `stats` `sessions` table + `stats digest` | transcripts, numeric allowlist ONLY (SPEC-135 privacy wall) | scorecard numbers | weekly |
| `session observe` / `session intel` | transcripts, content-adjacent detail | deterministic usage/friction views + digest | weekly cron |
| `session audit run` | transcripts, agentic exploration | evidence-tiered findings + owner-tagged recommendations | weekly / on demand |

The audit is the only layer that produces *change decisions with metric
contracts*; the other two stay cheap and deterministic. Known debt: three
weekly artifacts overlap at the raw-count layer; if that hurts, fold the audit
report in as a `session intel` source rather than minting a fourth digest.

## Cadence

Weekly, riding the consumer's existing session-intel schedule slot (no new
daemon, no listener). On-demand runs are fine any time; {PREV} chaining keeps
the diff meaningful regardless of spacing.

## Invariants

- Propose-don't-dispose at every joint: the audit writes reports, triage writes
  stdout, only a human writes the board (ADR-0034 decision 2/5, same rule
  SPEC-195 enforces for `learn propose`).
- Claims never exceed evidence; a recommendation without a metric contract is
  not triage-able and should be treated as prose, not a proposal.
- The loop measures itself: hook-block counts, error decomposition, and
  delegation shape in each report include the friction this very process
  generates (the 2026-07-14 baseline run caught its own ship-gate and
  commit-format blocks).

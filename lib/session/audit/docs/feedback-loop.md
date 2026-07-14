# The usage feedback loop

The kit improves itself from evidence, not vibes. This page is the contract for
how usage telemetry becomes a shipped enhancement, and how the next audit proves
the enhancement worked. Five stages; the first two and the last are this tool's
job, the middle two are the kit's normal operating lanes.

```
COLLECT ──> REPORT ──> TRIAGE ──> ENHANCE ──> MEASURE
   │           │          │           │           │
 session-    audit-     session-    normal      next run's
 observe /   YYYY-MM-   audit       kit lanes   {PREV} metric
 semantic /  DD.md      triage      (board row  diff: did the
 audit       (owner     (kanban     -> spec ->  metric move?)
 (this       tags +     proposal    execute ->
 tool)       metric     rows,       ship)
             contracts) human
                        accepts)
```

## Stage contracts

1. **COLLECT.** `session-observe` (deterministic parsing, free), `session-semantic`
   (cheap LLM topic signal, cron), `session-audit run` (expensive agentic deep
   audit, weekly / on demand). Read-only over transcripts, always.
2. **REPORT.** One dated file per audit run. Every recommendation carries an
   OWNER (`kit` | `user-habit` | `harness` | `instrumentation`) and a METRIC
   CONTRACT (name, current value, exact re-run command). The report closes with
   a machine-readable json footer of the same rows. Only HIGH-tier findings are
   stable currency across runs; MEDIUM/LOW are leads, labeled as such.
3. **TRIAGE.** `session-audit triage` extracts the footer into kanban proposal
   rows (`| ?? | change | audit ref · owner · metric | queued |`). PROPOSALS
   ONLY: a human reviews, assigns real IDs, and pastes accepted rows into the
   consumer repo's `BACKLOG.md`. Rejected rows die here; nothing auto-files.
4. **ENHANCE.** An accepted row is ordinary kit work: it flows queued -> speccing
   -> executing -> shipped through the normal lanes and gates. Nothing special;
   the audit only supplied the evidence and the metric.
5. **MEASURE.** The next `session-audit run` receives the previous report as
   `{PREV}` automatically and MUST open with a metric-by-metric diff: for each
   earlier recommendation, did its metric move? A fix whose metric did not move
   goes back to TRIAGE as a new finding, with the failed attempt as context.

## Cadence

Weekly, riding the consumer's existing session-intel schedule slot (no new
daemon, no listener). On-demand runs are fine any time; {PREV} chaining keeps
the diff meaningful regardless of spacing.

## Invariants

- Propose-don't-dispose at every joint: the audit writes reports, triage writes
  stdout, only a human writes the board.
- Claims never exceed evidence; a recommendation without a metric contract is
  not triage-able and should be treated as prose, not a proposal.
- The loop measures itself: hook-block counts, error decomposition, and
  delegation shape in each report include the friction this very process
  generates (the 2026-07-14 baseline run caught its own ship-gate and
  commit-format blocks).

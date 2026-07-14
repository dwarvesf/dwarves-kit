# SPEC: session-audit

## Problem

The session subsystem can locate waste deterministically (session-observe) and
cluster topics cheaply (session-semantic), but neither produces evidence strong
enough to drive changes: no verifiable citations, no owner (is a fix the kit's,
the user's, or the harness's?), no dollar attribution, and no way for a later
run to check whether a fix moved anything. The 2026-07-14 head-to-head
(ops-toolkit `experiments/log-intel-prompt-v2/`) showed a forensic-style agentic
prompt closes all four gaps: its HIGH-tier numbers reproduced exactly on
independent re-run, and it surfaced kit-actionable findings (ship-gate as the
top named friction; Edit-before-Read as the top tool error) that the thin
prompt structurally cannot see.

## Solution

`session-audit run` renders the co-located `prompt.md` (forensic-audit shape:
schema-first exploration, evidence tiers HIGH/MEDIUM/LOW, no dark buckets,
per-hook block attribution, owner-tagged recommendations each carrying a metric
contract) and pipes it to an agent runtime that explores the transcripts itself.
One dated report per run; the previous report is auto-passed as `{PREV}` so
each run opens with a metric diff: the collector-to-enhancement feedback loop.

## Contract

- `run [--root D] [--days N] [--deep-read K] [--model M] [--out DIR] [--pricing-file F] [--json]`:
  renders `prompt.md` ({ROOT}, {DAYS}, {K}, {PRICING}, {PREV}), pipes it to
  `SESSION_AUDIT_CMD` (default `claude -p --model M --allowedTools
  Bash,Read,Grep,Glob --output-format json`), writes `DIR/audit-YYYY-MM-DD.md`
  (header comment: date, root, days, model, cost, prev) and prints the path +
  cost. Accepts both object-form and array-form runtime JSON.
- `{PREV}` = newest existing `audit-*.md` in `--out`, else "none provided for
  this run".
- `triage [--out DIR] [--report F] [--json]`: extracts the newest (or given)
  report's machine-triage json footer (the LAST fenced json block that parses
  as a list of {change, owner, ...}) and prints kanban proposal rows
  (`| ?? | change | audit ref · owner · metric | queued |`). Propose-only:
  stdout, never writes a board. Degrades: no report -> "no audit report found";
  no valid footer -> `_none_`.
- Degrades to `_unavailable_` (exit 0, no report) when the runtime is missing,
  fails, or returns unparseable output; never fabricates.
- Propose-only: writes nothing but the report. Read-only over transcripts (the
  prompt instructs it; the allowed-tools list carries no Write/Edit).
- Cost is a feature decision: measured ~$3.5 and ~10 min per run on Sonnet over
  a 3-day window. Weekly or on-demand, never per-session.

## Non-goals

- Replacing session-semantic's cheap cron slot (78x slower, ~70x cost).
- Acting on the recommendations (human reviews; owner tags route them).
- Scheduling itself.
- Guaranteeing LOW/MEDIUM-tier stability across runs (only HIGH-tier rows are
  reproducible by construction; the report labels the rest as estimates).

## Verification

```bash
bash lib/session/audit/tests/smoke.sh   # -> smoke: N passed, 0 failed
```

Covers: report write + header params, full placeholder substitution, PREV
chaining across runs, array-form runtime JSON, degrade on failing command and
on garbage output.

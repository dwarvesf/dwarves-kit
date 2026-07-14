# Proof of Done: session-audit

**Feature:** LLM deep-audit verb over CC session transcripts (forensic prompt + chained metric-diff reports).
**Date:** 2026-07-14 · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Provenance:** ops-toolkit `experiments/log-intel-prompt-v2/`

Deterministic (fixture runtime via `SESSION_AUDIT_CMD` + `SESSION_AUDIT_DATE`), so the
smoke is the proof. Live-model quality was validated in the origin experiment
(HIGH-tier claims reproduced exactly on independent re-run; see the experiment's
`results/comparison.md`).

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `run` writes one dated report containing the runtime's result body + a header with run params | SPEC Contract |
| A2 | All 5 placeholders ({ROOT} {DAYS} {K} {PRICING} {PREV}) substituted; none leak into the prompt | SPEC Contract |
| A3 | First run passes PREV="none provided for this run" | SPEC Contract |
| A4 | Second run passes the first report's path as {PREV} (the metric-diff chain) | SPEC Contract |
| A5 | Array-form runtime JSON parsed as well as object-form | observed CLI variance |
| A6 | Failing runtime degrades to `_unavailable_`, exit 0, and writes NO report (never fabricates) | NEGATIVE CONTROL |
| A7 | Garbage (non-JSON) runtime output also degrades to `_unavailable_` | NEGATIVE CONTROL |
| A8 | `triage` turns the report's machine-triage json footer into kanban proposal rows (propose-only banner, owner + metric in notes) | feedback-loop TRIAGE stage |
| A9 | `triage` picks the LAST valid json block (decoy blocks in prose are ignored) | footer contract |
| A10 | `triage` degrades to `_none_` on a report without the footer, and to "no audit report found" on an empty dir | NEGATIVE CONTROL |

## Implementation

| Piece | What | Where |
|---|---|---|
| Prompt template | forensic audit shape: schema-first, tiers, no dark buckets, owner tags, metric contracts, {PREV} diff | `prompt.md` |
| Render + chain | placeholder substitution; newest `audit-*.md` in --out becomes {PREV} | `render_prompt()` / `latest_report()` |
| Runtime | `claude -p --allowedTools Bash,Read,Grep,Glob --output-format json`, prompt on stdin, `SESSION_AUDIT_CMD` override | `run_agent()` |
| Output parse | object-form and array-form `--output-format json` | `parse_runtime_json()` |
| Report | `DIR/audit-YYYY-MM-DD.md`, header comment (date/root/days/model/cost/prev) | `main()` |
| Triage | last-valid fenced json footer -> `\| ?? \| change \| audit ref · owner · metric \| queued \|` rows, stdout only | `cmd_triage()` / `extract_recommendations()` |
| Loop contract | COLLECT -> REPORT -> TRIAGE -> ENHANCE -> MEASURE stage contracts + invariants | `docs/feedback-loop.md` |
| Tests | fixture runtime + capture helper, 18 assertions incl. 3 negative controls | `tests/smoke.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Smoke (all) | `bash lib/session/audit/tests/smoke.sh` | `smoke: 18 passed, 0 failed` | PASS |
| Report write (A1) | items 1-3 | dated file, body + header params present | PASS |
| Substitution (A2) | items 4-5 | ROOT present, no `{...}` placeholder remains | PASS |
| PREV first run (A3) | item 6 | "none provided for this run" in rendered prompt | PASS |
| PREV chained (A4) | item 7 | first report path in second rendered prompt | PASS |
| Array-form (A5) | items 8-9 | status ok + body written | PASS |
| Degrade fail (A6, NEGATIVE CONTROL) | items 10-11 | `_unavailable_`, exit 0, no report file | PASS |
| Degrade garbage (A7, NEGATIVE CONTROL) | item 12 | `_unavailable_` | PASS |
| Triage rows (A8) | items 13-15 | 2 rows, owner+metric notes, propose-only banner | PASS |
| Triage decoy (A9) | item 16 | decoy json block ignored | PASS |
| Triage degrade (A10, NEGATIVE CONTROL) | items 17-18 | `_none_` / "no audit report found" | PASS |

## Run detail

```
$ bash lib/session/audit/tests/smoke.sh
  ok: report written
  ok: body present
  ok: header params
  ok: ROOT substituted
  ok: all placeholders resolved
  ok: PREV=none on first run
  ok: PREV chained
  ok: array-form parsed
  ok: array body written
  ok: degrades on failure
  ok: no report on failure
  ok: degrades on garbage
  ok: triage: 2 proposal rows
  ok: triage: notes carry owner+metric
  ok: triage: propose-only banner
  ok: triage: decoy block ignored
  ok: triage: no-block degrades
  ok: triage: empty degrades
smoke: 18 passed, 0 failed
Exit: 0
```

## Reproduce

```bash
cd <dwarves-kit> && bash lib/session/audit/tests/smoke.sh
```

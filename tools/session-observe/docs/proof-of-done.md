# Proof of Done: cc-observe

**Feature:** report Claude Code skill/tool usage + per-hook latency from session transcripts.
**Date:** 2026-06-14 · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Mega-goal:** cc-elevation sub-goal 01

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `skills` view: each Skill counted, with error rate | sub-goal Done |
| A2 | `tools` view: each tool counted, errors attributed via `tool_use_id` | sub-goal Done |
| A3 | `hooks` view: per-hook count + p50/p95/max latency from `hookInfos[].durationMs` | sub-goal Done |
| A4 | Latency discriminates: a known-slow hook surfaces, a known-fast one stays small (negative control) | sub-goal Done |
| A5 | Hook errors surfaced from `hookErrors` | sub-goal Done |
| A6 | `--json` machine-readable output (for vps-mon ingest) | sub-goal "report into vps-mon" |
| A7 | Read-only, no instrumentation, runs on real transcripts | sub-goal quality bar |
| A8 | `tests/smoke.sh` green | sub-goal close-the-loop |

## Implementation

| Piece | What | Where |
|---|---|---|
| Parser | single stdlib pass: `tool_use`/`tool_result` -> usage + errors; `hookInfos`/`hookErrors` -> latency | `bin/cc-observe` `collect()` |
| Hook label | basename for script hooks; hash for inline-echo; first token otherwise | `bin/cc-observe` `hook_label()` |
| Views | `skills` / `tools` / `hooks` / `report`, aligned tables or `--json` | `bin/cc-observe` `emit()` |
| Fixture | synthetic transcript: Skill, 2x Bash (1 err), Read, system entry w/ 500ms + 12ms hooks + 1 hook error | `tests/fixtures/sample.jsonl` |
| Tests | 9 assertions incl. the slow-vs-fast negative control | `tests/smoke.sh` |

No wrapper, no daemon, no dotfiles change (the transcript already records hook timing). See `docs/implementation-notes/01-observability.md`.

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Smoke (all) | `bash tests/smoke.sh` | `smoke: all 9 passed` | PASS |
| Skills (A1) | `cc-observe skills --file fixture` | `prose-rag 1` | PASS |
| Tools + errors (A2) | `cc-observe tools --file fixture` | `Bash 2 1`, `Read 1 0` | PASS |
| Hook latency (A3) | `cc-observe hooks --file fixture` | `slow-hook.sh max 500` | PASS |
| Negative control (A4) | same | fast `inline-echo` max 12 (< 100) | PASS |
| Hook errors (A5) | same | `1 hook errors` | PASS |
| JSON (A6) | `cc-observe report --file fixture --json \| python3 -m json.tool` | valid JSON | PASS |
| Real data (A7) | `cc-observe report --days 2` | 225 transcripts parsed in 0.47s | PASS |
| Smoke green (A8) | `bash tests/smoke.sh` | exit 0 | PASS |

## Run detail

```
$ bash tools/cc-observe/tests/smoke.sh | tail -1
smoke: all 9 passed

$ tools/cc-observe/bin/cc-observe report --days 2 --top 4
# skills  (225 transcripts)
  skill               count  errors  rate
  prompt-improver        14       0    0%
  plan-for-mega-goal      7       0    0%
# tools  (225 transcripts)
  tool   count  errors  rate
  Bash    3697     219    6%
  Edit    1517     113    7%
  Read    1457     124    9%
# hooks  (18 hook errors across 225 transcripts)
  hook              runs  p50ms  p95ms  maxms
  slop-cleaner.sh   1072   2967   6211  10303
```

The real run produced an actionable finding the tool was built to find: `slop-cleaner.sh` runs on ~every turn at p50 ~3s, max ~10s (logged to the mega-goal NOTES proposed-additions as a candidate fix).

## Negative control

Two controls prove the numbers are real, not incidental:
- **Latency discrimination**: in the same fixture the slow hook reports max 500ms and the fast hook 12ms; smoke items 4 and 5 assert both. If `collect()` ignored `durationMs`, both would read 0 and items 4-5 fail.
- **Error attribution**: Bash has 1 error (the errored `tool_result` references `tu_2`), Read has 0. If `tool_use_id` mapping were broken, the error would land on the wrong tool or none, failing item 2/3.

## Reproduce

```bash
cd tools/cc-observe
bash tests/smoke.sh                              # -> smoke: all 9 passed
bin/cc-observe report --days 7 --top 10          # real digest, last 7 days
bin/cc-observe hooks --days 7 | sort -t$'\t' -k5 # slowest hooks first
```

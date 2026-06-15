# Proof of Done: cc-observe

**Feature:** report Claude Code skill/tool usage + per-hook latency + subagent-spawn mix from session transcripts.
**Date:** 2026-06-14 (skills/tools/hooks); 2026-06-15 (subagents view) · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Mega-goal:** cc-elevation sub-goal 01; subagents view per ID-100 / `research/2026-06-15-claude-code-usage-metrics-and-tooling.md`

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
| A9 | `subagents` view: Agent/Task spawns per day + by `subagent_type`, normalized `per100` prompts | ID-100 |
| A10 | Sidechain spawns excluded (each spawn counted once from the main session) | ID-100 negative control |
| A11 | `subagents` included in `report` + the `--json` object | ID-100 (cc-intel weekly digest picks it up) |

## Implementation

| Piece | What | Where |
|---|---|---|
| Parser | single stdlib pass: `tool_use`/`tool_result` -> usage + errors; `hookInfos`/`hookErrors` -> latency | `bin/cc-observe` `collect()` |
| Hook label | basename for script hooks; hash for inline-echo; first token otherwise | `bin/cc-observe` `hook_label()` |
| Views | `skills` / `tools` / `hooks` / `subagents` / `report`, aligned tables or `--json` | `bin/cc-observe` `emit()` |
| Subagents | count `Agent`/`Task` spawns by day + `subagent_type`, skip `isSidechain`; per100 = spawns / user-prompt turns | `bin/cc-observe` `collect()` + `subagent_*_rows()` |
| Fixture | synthetic transcript: Skill, 2x Bash (1 err), Read, system entry w/ 500ms + 12ms hooks + 1 hook error, a text prompt, 2 main Agent spawns, 1 sidechain spawn | `tests/fixtures/sample.jsonl` |
| Tests | 12 assertions incl. slow-vs-fast latency + sidechain-exclusion negative controls | `tests/smoke.sh` |

No wrapper, no daemon, no dotfiles change (the transcript already records hook timing). See `docs/implementation-notes/01-observability.md`.

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Smoke (all) | `bash tests/smoke.sh` | `smoke: all 12 passed` | PASS |
| Skills (A1) | `cc-observe skills --file fixture` | `prose-rag 1` | PASS |
| Tools + errors (A2) | `cc-observe tools --file fixture` | `Bash 2 1`, `Read 1 0` | PASS |
| Hook latency (A3) | `cc-observe hooks --file fixture` | `slow-hook.sh max 500` | PASS |
| Negative control (A4) | same | fast `inline-echo` max 12 (< 100) | PASS |
| Hook errors (A5) | same | `1 hook errors` | PASS |
| JSON (A6) | `cc-observe report --file fixture --json \| python3 -m json.tool` | valid JSON | PASS |
| Real data (A7) | `cc-observe subagents --days 6` | 853 transcripts, per-day + per-type table | PASS |
| Smoke green (A8) | `bash tests/smoke.sh` | exit 0 | PASS |
| Subagents (A9) | `cc-observe subagents --file fixture` | `2026-06-14 2 1 200.0` | PASS |
| Sidechain excl. (A10) | same | `2 spawns` (not 3), `Explore 1` (not 2) | PASS |
| In report+json (A11) | `cc-observe report --file fixture[ --json]` | `# subagents` section + `subagents` json key | PASS |

## Run detail

```
$ bash tools/cc-observe/tests/smoke.sh | tail -1
smoke: all 12 passed

$ tools/cc-observe/bin/cc-observe subagents --days 6
# subagents  (232 spawns, 2302 prompts, 853 transcripts)
  day         spawns  prompts  per100
  ----------  ------  -------  ------
  2026-06-15      20      201    10.0
  2026-06-14      26      340     7.6
  2026-06-13      30      383     7.8
  2026-06-12      12      182     6.6
  2026-06-11      58      520    11.2
  2026-06-10      43      425    10.1

  subagent_type     count  share
  ----------------  -----  -----
  general-purpose      93    40%
  reviewer             54    23%
  Explore              36    16%

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

The real run produced an actionable finding the tool was built to find: `slop-cleaner.sh` runs on ~every turn at p50 ~3s, max ~10s (logged to the mega-goal NOTES proposed-additions as a candidate fix). The `subagents` view answered the question that prompted it (`research/2026-06-15-...metrics`): raw counts looked flat-to-down (06-11 peak 58, 06-14 only 26), but the type table showed `general-purpose` now dominates (40%) over `Explore` (16%), the costlier-per-spawn shift that the raw count hid.

## Negative control

Two controls prove the numbers are real, not incidental:
- **Latency discrimination**: in the same fixture the slow hook reports max 500ms and the fast hook 12ms; smoke items 4 and 5 assert both. If `collect()` ignored `durationMs`, both would read 0 and items 4-5 fail.
- **Error attribution**: Bash has 1 error (the errored `tool_result` references `tu_2`), Read has 0. If `tool_use_id` mapping were broken, the error would land on the wrong tool or none, failing item 2/3.
- **Sidechain exclusion**: the fixture has 3 Agent spawns but one is `isSidechain` (a subagent's own run). `subagents` reports 2, with `Explore 1` not 2; smoke items 10-11 assert it. If `collect()` did not skip sidechain, every spawn would be double-counted (once in the main session, once in the subagent's transcript) and the count would read 3 / Explore 2.

## Reproduce

```bash
cd tools/cc-observe
bash tests/smoke.sh                              # -> smoke: all 12 passed
bin/cc-observe report --days 7 --top 10          # real digest, last 7 days
bin/cc-observe subagents --days 7                # spawn mix per day + per type, per100 prompts
bin/cc-observe hooks --days 7 | sort -t$'\t' -k5 # slowest hooks first
```

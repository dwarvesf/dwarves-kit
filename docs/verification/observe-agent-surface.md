# Proof of done · observe-agent-surface (+ money plane, forge skin)

Branch: `feat/forge-observability` (PR #289). Covers the branch's behavioral changes:
the forge-skinned dashboard with chart layer, the money plane (computed spend), the
cognitive-debt score (ADR-0031 read side), the run-explorer drill-down logs, the
Config & tool-policy section, the `tool-policy-guard.sh` PreToolUse hook, the
`stats`/`debt` agent verbs, and the `observe` skill. Design records:
`docs/briefs/DECISION-BRIEF-cognitive-debt-score.md`,
`lib/bench/docs/dashboard-design.md` (v2 section).

## Confirmation run-table (2026-07-25, this branch)

| Check | Command | Exit | Verdict |
|---|---|---:|---|
| Dashboard suite (9 checks: fixtures, alerts, privacy negative control, cost math with hand-computed dollars, run-rate refusal, debt formula, render + node --check) | `python3 lib/bench/tests/test_dashboard.py` | 0 | PASS 9/9 |
| Bench / TUI / viewer / report suites | `python3 lib/bench/tests/test_{bench,tui,viewer,report}.py` | 0 | PASS (6/7/3/3) |
| Live build over real data | `python3 lib/bench/dashboard.py build --monthly-budget 400 --max-transcripts 120` | 0 | 209 runs, 1491 events, 91 sessions; page probes for every new section pass; embedded JS `node --check` clean |
| Agent verb: debt | `python3 lib/bench/dashboard.py debt` | 0 | `cognitive debt score: 96/100 (open defers 0 high / 0 low, last paydown 2026-07-20)` |
| Agent verb: stats | `python3 lib/bench/dashboard.py stats \| jq keys` | 0 | `["alerts","debt","fleet","money"]` |
| Hook: deny path | `echo '{"tool_name":"mcp__plugin_playwright_x"}' \| KIT_TOOL_POLICY=<deny.json> bash hooks/tool-policy-guard.sh` | 2 | blocked with preferred-rung message |
| Hook: ask path | same with `action=ask` | 0 | warning on stderr naming the preferred rung |
| Hook: fail-open paths | missing policy file; malformed stdin | 0 | silent allow (by design; a broken policy must not brick tool calls) |

## Negative controls (revert -> RED -> restore)

1. **Debt formula.** Reverted the high-significance weight `10 -> 9` in
   `debt_metrics`; `tests/test_dashboard.py` went RED
   (`test_debt_score_formula` computes the expected score by hand). Restored the
   weight; suite GREEN again. Run recorded 2026-07-25 in-session.
2. **Hook policy is the deciding input.** With `action=deny` for the same tool the
   hook exits 2 (blocked); flipping only the policy's action to `allow` exits 0.
   `deny rc=2 (want 2) | allow rc=0 (want 0)`.
3. **JS integrity.** During the build, an f-string `\n` produced a literal newline
   inside the CSV-export string literal and `node --check` went RED
   (`SyntaxError: Invalid or unexpected token`); after escaping, GREEN. The
   node-check now lives in the test suite, so this class of regression stays caught.

## Reproduce

```sh
cd lib/bench
python3 tests/test_dashboard.py && python3 tests/test_bench.py \
  && python3 tests/test_tui.py && python3 tests/test_viewer.py && python3 tests/test_report.py
python3 dashboard.py debt
python3 dashboard.py stats | python3 -m json.tool | head
python3 dashboard.py build --out /tmp/dash.html   # then open; sidebar has
                                                  # Cognitive debt + Config & policy
```

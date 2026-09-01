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


## Addendum (same day): TUI relocation + policy v2 + runtimes

| Check | Command | Exit | Verdict |
|---|---|---:|---|
| Data-plane split | `python3 lib/bench/tests/test_events.py` | 0 | PASS 4/4 (protocol/adapter tests retargeted at events.py; render tests moved to forge cli/test_forge_tui.py, PASS 3/3 there) |
| viewer/report/dashboard on events.py | all suites | 0 | 5 suites green after the tui.py -> events.py rewire (report.py's stale tui import caught by the suite and fixed) |
| Hook v2 schema | v2 policy from DEFAULT_TOOL_POLICY: computer-use match | 0 | ask-warns naming preferred rung "macos-ladder" |
| Hook v1 legacy | v1 policy, deny match | 2 | still blocks (backward compatible) |
| Runtimes detector | `dashboard.collect_runtimes()` | 0 | 6/6 runtimes detected on this host with real store stats (claude-code 1763 files, codex 11, pi 28, opencode, gemini, cursor) |
| forge-tui standalone | `env -i PATH=... python3 cli/forge-tui demo` | 0 | runs with an empty environment, zero kit imports |


## Addendum 2 (same day): parity, sharing, charts, efficiency

| Check | Command | Exit | Verdict |
|---|---|---:|---|
| Efficiency ranking on real data | `dashboard.efficiency_rankings(collect_sessions(...))` | 0 | 8 members ranked, grades B..E; top B/67 layout ($41/M-out, 87% cache), worst E/32 ($152/M-out, 45% cache) |
| Volume floor holds | ranking with `min_cost` default | 0 | members under $1 excluded; no single-session member on the board |
| New charts | page probes | 0 | "Full-conformance runs per day" + "Runs by lane · weekly" present, legend + fixed category order |
| Share deep-links | page probes | 0 | 210 share buttons; `#run/<rid>` handler + hashchange listener; `openRun` expands the row's log |
| forge-tui parity verbs | `forge-tui runs \| debt \| stats` (text + json) | 0 | all three emit parseable JSON; conformance resolves 3/3 and 12/12 with `DWARVES_KIT_ROOT` |
| forge-tui self-test | `python3 cli/test_forge_tui.py` | 0 | PASSED 4/4 (count now derived, not hardcoded) |
| Kit suites after all edits | 5 suites | 0 | green |

### Negative control (this addendum)

**`expected_plan` unguarded `__file__`.** The new query-verb test exercised the
module in an exec'd context and went RED with
`NameError: name '__file__' is not defined` — a genuine bug affecting any
embedded use, not a test artifact. After guarding (prefer `DWARVES_KIT_ROOT`,
guess the filesystem root only when `__file__` exists), the same path was
re-run in a module deliberately built with **no** `__file__` at all and returned
rows normally. Restoring the unguarded line reproduces the failure.


## Addendum 3: the session detail page (correction)

Addendum 2 claimed "session detail + share" was delivered. It was not: what shipped
was an inline expandable row plus a `#run/<rid>` deep link inside the dashboard
bundle, which is not a detail page. Corrected here.

| Check | Command | Exit | Verdict |
|---|---|---:|---|
| One session page | `dashboard.py session board-tool --out s.html` | 0 | 16 KB standalone page: routing decision, 37-row gate timeline with reasons, conformance tiles, ship outcomes, reproduce block, share button |
| Standalone (no bundle dependency) | grep for dashboard-only ids in the output | 0 | no `policy-data` / `navbtn` references; page carries its own `<style>` and script |
| Batch render | `dashboard.py sessions --out-dir sessions` | 0 | 211 pages + index written |
| Explorer wiring | page probes | 0 | 213 `rid-link` anchors to `sessions/<rid>.html` |
| Suites after the change | 5 suites | 0 | green |

**Negative control.** Rendering a nonexistent rid returns `None` and the CLI exits
with `no run ledger for <rid>` on stderr rather than writing an empty page; with a
real rid the page contains the timeline rows. The missed-gate path is exercised by
any run whose lane expects a gate it never recorded (rows render with the
`◌ MISSED` chip and the `s-missed` row style).


## Addendum 4: transcripts, redaction, efficiency board

| Check | Command | Exit | Verdict |
|---|---|---:|---|
| Transcript render (real session) | `dashboard.py transcript <session>.jsonl` | 0 | 111 turns, 37 tool calls with results, per-turn tokens/cost, 136 KB standalone page |
| Redaction unit | `redact("api_key=... sk-ant-... ghp_...")` | 0 | 3 hits, all three shapes masked |
| Redaction end-to-end | render the fixture carrying a planted key | 0 | page contains `REDACTED`; asserted NOT to contain the planted key |
| Synthetic fixture | `python3 examples/fixtures/make_demo_session.py` | 0 | 10 records covering text / thinking / tool_use / tool_result / error |
| Efficiency board | page probes | 0 | own section + nav entry: podium, grade distribution, weighting chart, leaderboard, legend |
| Markup balance | `<p>` open/close count on the built page | 0 | 238/238 |
| Suites | 5 kit suites | 0 | green |

### Negative control

The redaction check is a real control: it asserts the planted credential is **absent**
from the rendered page, so deleting any entry from `SECRET_PATTERNS` turns the fixture
render RED. The fixture plants the key specifically so that check can fail.

### Honest limitations recorded on the page itself

`redact()` is a MASK over free-form text, and masks fail open: an unrecognised secret
shape passes through. That is why real transcripts stay out of any tree that ships
publicly, why the pages carry `noindex`, and why the hit count is printed in place.

### Process note

The commit that introduced this work (2ce461c) referenced "Proof addendum 4" before this
file existed: the writing script used a path relative to `lib/bench` while this file
lives at the repo root, so the append silently targeted a nonexistent path. Recorded here
rather than quietly backfilled.


## Addendum 5: pool allocation + periodic report

| Check | Command | Exit | Verdict |
|---|---|---:|---|
| Feature attribution coverage | branch scan over the sample | 0 | 92/92 sessions carry a git branch; `main` dominates and is labeled unattributed |
| CLI text / json / md | `dashboard.py allocation --budget 1500 --format …` | 0 | all three render; md is a paste-ready weekly report |
| Web section | page probes | 0 | share bars, member x feature matrix, period comparison, proposed plan, `data-sec="allocation"` |
| Markup + JS | `<p>` balance, `node --check` | 0 | 243/243, JS clean |
| Suites | `tests/test_dashboard.py` + 4 others | 0 | PASSED 12/12 and green |

### Negative controls (both are real bugs caught by running on live data)

1. **Residual force-feeding.** The first water-fill dumped leftover budget on whoever was
   under the cap: with a $1,500 pool, a member who spent $44 was proposed **$549** while
   the $3.9k member sat at the $600 cap. Fixed with demand ceilings; guarded by
   `test_allocation_plan_respects_demand_ceiling_and_reports_headroom`, which asserts every
   proposal stays within 3x actual spend and that the remainder appears as unallocated.
2. **Floor outrunning demand.** The starvation floor lifted a $50 spender to a $1,250
   proposal on a large budget. Fixed by capping the floor at 3x demonstrated demand
   (a zero-history member still gets the plain floor); the same test asserts it.

### Sampling honesty

Period-over-period comparison is **suppressed** when either bucket is partial. On this
host the raw number would have read **+4963% week over week**, which is entirely an
artifact of the sample starting mid-week; the report now prints the raw change plus
"not comparable" and the reason.

## Addendum 6 (2026-07-25): one-page merge, export data plane, observe backend

Operator direction: "don't maintain 2 pages, merge them into one page, fully
functioning with design document, backend, frontend, deployment; handle onboarding
with no data."

| # | Check | Command | Result |
|---|---|---|---|
| 1 | export emits the schema-1 payload | `dashboard.py export --max-transcripts 120 --out sections.json` | 215 runs, 1533 events, 12 sections, js 5642 bytes |
| 2 | build is retired with a pointer | `dashboard.py build` | pointer text on stderr, exit 2 |
| 3 | all suites green after the refactor | `for t in tests/test_*.py; do python3 $t; done` | 5/5 PASS (render test now asserts the 12-id section contract + node-checks FLEET_JS) |
| 4 | SPA integrity | tag-balance scan + `node --check` on extracted scripts | imbalance none; JS OK |
| 5 | single-file bundle | `bundle.py` then parse the inline payload | schema 1, 12 sections, 215 runs |
| 6 | backend round-trip | `export --push https://forge-api...` then authed GET | PUT 200 (932 KB), GET returns same generated_at/counts |
| 7 | negative: junk payload | PUT `{"nope":true}` with auth | 422 |
| 8 | negative: no auth | PUT valid shape, no bearer | 401 (GET no-auth also 401) |

Found live: Cloudflare's bot filter 403s Python-urllib's default User-Agent; the
push now sends `dwarves-kit-observe/1` (worker code was never at fault; a curl
probe isolated it).

Reproduce: kit `lib/bench` (this branch) + forge `site/dashboard/`; the worker is
`forge/api/worker.js` deployed to staging (version 1e56da29). Token via
`op://Toolkit/forge-api-staging-admin/credential` as `FORGE_ADMIN_TOKEN`.

# Proof of done · lib/bench (bench plane prototype)

Scope: the bench-plane feature arc on `feat/bench-plane` (runner + scoreboard,
TUI frontend, web diagram player, real-session replay + conformance overlay,
control-plane report). Brief: `docs/briefs/DECISION-BRIEF-bench-plane.md`.
Rows: ID-420..424.

## Acceptance criteria

| # | Criterion | Where verified |
|---|---|---|
| 1 | Matrix runner replays a frozen hashed suite across models/executors and appends immutable config x outcome rows | `tests/test_bench.py` + recorded live runs `runs/2026-07-25-smoke-code*.jsonl` |
| 2 | Checks are hand-verified and accept a reference solution (a check nothing can pass measures nothing) | `test_checks_pass_on_reference_solutions` |
| 3 | `diff` detects regressions across runs of the same suite hash, exit 1 | `test_diff_detects_regression` + live diff run1 vs r2 (FIXED + REGRESSED both caught) |
| 4 | TUI renders a run live from the event protocol, with retry/failure fingerprints and non-TTY fallback | `tests/test_tui.py` |
| 5 | Web viewer plays event streams as a flow diagram (hover/click/scrub), JS parses | `tests/test_viewer.py` (incl. `node --check`) |
| 6 | Real kit sessions replay from gate-ledger history, decisions (skip/override reasons) preserved | `test_ledger_adapter` + live `tui.py run board-tool` |
| 7 | Expected-vs-actual overlay: missed required gates become ghost nodes; required-gate conformance scored | `test_ledger_conformance_overlay` |
| 8 | Control-plane report renders fleet timeline, model minutes, gate matrix, waves, incidents from real ledgers + declared overlay | `tests/test_report.py` + live build from 6 real kit-absorptions rids |

## Confirmation run-table (2026-07-25, this branch)

| Check | Command | Result |
|---|---|---|
| Runner suite | `python3 tests/test_bench.py` | PASSED 6/6 |
| TUI suite | `python3 tests/test_tui.py` | PASSED 7/7 |
| Viewer suite | `python3 tests/test_viewer.py` | PASSED 3/3 |
| Report suite | `python3 tests/test_report.py` | PASSED 3/3 |
| Live bench run 1 | `bench.py run --suite suites/smoke-code --models haiku,sonnet` + agent cells | 6 cells recorded, `runs/2026-07-25-smoke-code.jsonl` |
| Live bench run 2 (replay) | same command, r2 | 6 cells, real variance captured (sonnet flipped both directions) |
| Live diff | `bench.py diff --baseline runs/...smoke-code.jsonl --candidate ...-r2.jsonl` | `FIXED dedup-urls/sonnet/model`, `REGRESSED parse-semver/sonnet/model`, exit 1 |
| Real-session replay | `python3 tui.py run board-tool --speed 100` | 15 stages incl. 2 skips + 1 override with reasons; conformance 12/12 required gates present |
| Control-plane report | `report.py build --rids kit-template-fields,grill-conditioning,kit-emit-sweep,kit-pitch,lane-de-escalation,mega-mirror-sync --overlay examples/kit-absorptions.overlay.json` | 6 runs rendered from real ledgers |

## Negative controls

- `test_diff_detects_regression`: a pass->fail flip exits 1 with `REGRESSED` (the
  diff cannot silently bless a regression).
- `test_fail_run_reports_fingerprint`: a failing run's report carries the verbatim
  failing case, never only a count.
- `test_ledger_conformance_overlay`: a run missing required gates (fixture) renders
  them `missed` and scores 3/5, not full marks.
- Suite-hash guard: `bench diff` warns loudly across differing hashes (cross-hash
  deltas are narrative, not evidence).

## Reproduce

```sh
cd lib/bench
python3 tests/test_bench.py && python3 tests/test_tui.py \
  && python3 tests/test_viewer.py && python3 tests/test_report.py
python3 tui.py demo                # interaction demo, no model calls
python3 tui.py run board-tool      # real recorded session replay
```

Live-model steps (cost money, optional): the two `bench.py run` commands in the
run-table; results append-only, never overwrite the committed baselines.

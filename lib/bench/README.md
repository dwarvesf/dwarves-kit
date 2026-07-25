# bench

The kit's **bench plane**: a standalone comparative benchmark runner. It
replays a frozen, content-hashed task suite under a config matrix (model x
executor, later x modules x tool), scores each cell with the task's own
hand-verified check script, and appends one immutable JSONL row per cell.
Comparing models, workflows, or tools is then a GROUP BY over one fact table.

Design brief: `docs/briefs/DECISION-BRIEF-bench-plane.md`. Metric contract:
`docs/METRICS.md` (what is measured, why, and on which surface it is shown).
Board rows: ID-420 (config stamping), ID-421 (this module), ID-422 (signal
registry + tool suites).

**Standalone by contract (N4):** stdlib-only Python, no kit required. Delete
the kit and `bench.py` still freezes, runs, scores, diffs, and renders. With
the kit present, rows carry `kit_version` and join the wider ledgers by
`session_id`.

## Quickstart

```sh
# race two models over the smoke suite, 4 cells in parallel
python3 bench.py run --suite suites/smoke-code --models haiku,sonnet --out runs.jsonl

# scoreboard: terminal table + self-contained HTML
python3 bench.py render runs.jsonl --html scoreboard.html

# new-model protocol: same suite, only the model dim changes, diff vs baseline
python3 bench.py run --suite suites/smoke-code --models new-model --out candidate.jsonl
python3 bench.py diff --baseline runs.jsonl --candidate candidate.jsonl  # exit 1 on regression

# flake rate: repeat every cell
python3 bench.py run --suite suites/smoke-code --models haiku --repeats 3 --out flake.jsonl
```

## Executors

| Executor | What it measures | How |
|---|---|---|
| `model` | raw model capability, single completion, no tools | `claude -p`, code written by bench |
| `agent` | the full tool-using workflow | `claude -p --permission-mode acceptEdits` inside the cell dir |

The delta between the two FOR THE SAME MODEL is the first workflow
measurement: what the harness adds beyond the raw model. The kit-on vs
kit-off headline (gates + verifiers as a togglable dimension) extends the
`agent` executor and is queued on ID-421.

## Suites

A suite is a directory: `suite.json` (name + task list) + `tasks/<id>/task.md`
(the prompt) + `tasks/<id>/check.py` (the verifier: prints `PASSED x/y`,
exit 0 iff all pass). The suite hash covers every byte, so a baseline is only
comparable to runs of the byte-identical suite; `diff` warns across hashes.

Rules for suite authors:
- Expected values are worked BY HAND before any model runs the task (N3).
- `check.py` is copied into the cell only AFTER the executor finishes; an
  executor can never read the verifier (anti-overfit).
- Smoke tier stays tiny: minutes and cents per config, so "run it again on
  the new model" is the default reaction, not a project.

`suites/smoke-code/` ships as the seed. Next suites per the brief: more task
types (research, ETL, review) and tool capability probes (browser-use first:
pinned fixture pages + drift-checked live targets, recorded traces as the
user-facing proof, flake rate first-class).

## Row schema

One JSON object per line, append-only. Config dims first, outcomes second:

| Field | Meaning |
|---|---|
| `ts`, `suite`, `suite_hash` | when, what corpus, which frozen version |
| `task`, `model`, `executor`, `repeat` | the cell coordinates |
| `kit_version`, `session_id` | join keys to the kit ledgers + transcripts |
| `pass`, `tests_passed`, `tests_total` | outcome, with granularity |
| `duration_s`, `model_duration_s` | wall clock vs model-reported time |
| `cost_usd`, `turns`, `tokens_in`, `tokens_out` | efficiency dims |
| `error` | harness failure, kept distinct from task failure |

## The verb surface (complete)

Eight verbs. Query verbs print JSON for agents; render verbs write self-contained HTML
for humans. Nothing here needs a server.

| Verb | What it produces | Primary caller |
|---|---|---|
| `stats` | fleet + money + debt + alerts as one JSON blob | agent |
| `debt` | cognitive-debt score, open defers, last paydown (ADR-0031) | agent |
| `allocation` | pool → member → feature, period comparison, proposed allowances | lead / agent |
| `export` | the fleet data payload (`sections.json`) the forge dashboard SPA loads; `--push` PUTs it to the gateway | machine (the SPA / CI) |
| `session <rid>` | ONE standalone session-log page (gate timeline, conformance, outcomes) | human, shareable |
| `sessions` | a session page per run, plus an index | human |
| `transcript <id>` | ONE full-transcript page (prompts, tool calls, results, commentary) | human, shareable |
| `transcripts` | the most recent N transcript pages, plus an index | human |

```sh
# agent surfaces
python3 dashboard.py stats
python3 dashboard.py debt --format json
python3 dashboard.py allocation --period week --budget 1500 --format json

# the lead's weekly/monthly report (paste-ready markdown)
python3 dashboard.py allocation --period month --budget 6000 --format md

# pages
python3 dashboard.py export --monthly-budget 1500 --period week \
  --out <forge>/site/dashboard/data/sections.json
python3 dashboard.py session <rid> --out session.html
python3 dashboard.py sessions --out-dir sessions/
python3 dashboard.py transcript <session-id> --out transcript.html   # opt-in: reads content
python3 dashboard.py transcripts --limit 20 --out-dir transcripts/
```

### What each surface is honest about

- **Money is computed**, never invoiced: a list-price table in this file, stated on the page.
- **Transcripts are opt-in.** Aggregates elsewhere stay counts-only. Content passes a
  redaction mask whose hit count is printed and whose fail-open nature is stated. Real
  transcripts are never committed to a tree that ships publicly.
- **Allocation proposals export, never apply.** Feature attribution is the git branch;
  `main`/`HEAD` are labeled unattributed. Period-over-period is suppressed when a bucket
  is partial.
- **Efficiency measures token economics, not value delivered**, and carries a volume floor.

The `observe` skill (kit `skills/observe`) makes these auto-firable from agent
sessions. The run TUI is a forge product now (`forge/cli/forge-tui`, with
`runs`/`debt`/`stats` mirroring the agent verbs); this repo keeps the data plane
in `events.py` (protocol + adapters + conformance overlay).

## Live TUI (the run frontend)

`forge/cli/forge-tui` renders a workflow run as an animated step list: pending ○ → spinner →
✓/✗, sub-items under the running stage, retry badges, accumulating cost, and an
expressive final report (verdict banner, per-stage table, failure fingerprints,
reproduce line). Falls back to plain per-event lines when not a TTY (CI logs).

```sh
forge-tui demo                    # feel the interaction: synthesized full-lane
                                       # run incl. verifier fail -> fix-agent -> retry
forge-tui demo --record run.events.jsonl
forge-tui replay run.events.jsonl --speed 2
forge-tui watch  run.events.jsonl # follow a live runner appending events
forge-tui run <rid>               # replay a REAL recorded kit session from
                                       # logs/runs/<rid>.log (gate-ledger history)
```

### Replaying real sessions (the condition tree)

Every kit run already locks its history: gate-ledger writes `logs/runs/<rid>.log`
(`START` = the routing decision, `GATE <phase> ran|skipped|override <reason>`,
`OUTCOME` = ship timings). `ledger_to_events` adapts that record into the event
protocol, so a recorded session replays in the TUI (`tui.py run <rid>`) or the
web viewer (`viewer.py build --ledger name=<rid>`). The decision tree is shown
as the path taken: the `route` root node carries lane-chosen vs lane-classified
(misfires flagged ⚑), skipped gates render dashed ⊘ with the skip reason (the
branch NOT taken and why), overrides render ⚑ with the override reason. Hour
gaps compress to watchable pacing; real wall-clock stays in the summary.
Terminal twin: `bash lib/telemetry/lane-telemetry.sh trace <rid>` (SPEC-063).

### Web diagram player

`viewer.py build` emits a self-contained HTML player for the same event streams:
stages as flow-diagram nodes, the pointer advancing with the run, hover tooltip
with the step's numbers and fingerprints, click to pin a detail panel, run
summary on finish, plus scenario picker / play / pause / speed / scrub.

```sh
python3 viewer.py build --out viewer.html                 # built-in demo scenarios
python3 viewer.py build --events "my run"=run.events.jsonl --out viewer.html
```

The built-in scenarios cover the variant axes: task types (feature, research,
eval), workflow shapes (full lane, tiny lane, loops), and a fault-injection
failure run (retry exhausted), so the red path is designed, not hoped.

### Control-plane data plane (one page lives in forge)

`dashboard.py export` emits the fleet payload the forge dashboard SPA injects:
12 section fragments (Fleet, Run explorer, Event stream, Tool activity, Cost &
tokens, Efficiency, Allocation, Runtime, Cognitive debt, Config & policy,
Bench/RCA, Alerts) plus their behavior JS, as one `sections.json`
(`schema: 1`). The PAGE itself is a forge product (`site/dashboard/index.html`);
the old `build` verb that emitted a second standalone page is retired (one-page
rule, 2026-07-25). `--push <url>` PUTs the payload to the gateway's
`/admin/observe` (Bearer from `FORGE_ADMIN_TOKEN`) for the dashboard's connected
mode. Design record: `docs/dashboard-design.md` v6.

```sh
python3 dashboard.py export --out sections.json          # ~0.5s over 200+ ledgers
python3 dashboard.py export --alerts examples/alerts.json --window-days 14
python3 dashboard.py export --push https://forge-api.infras.workers.dev
```

### Control-plane report (many runs, one surface)

`report.py build` renders the RUN_REPORT as a page: fleet timeline (swimlanes,
per-worker bars colored by model), worker minutes by model, the gate-coverage
matrix (● recorded / ○ skipped-with-reason / ⚑ override / − not recorded,
reasons on hover), an optional wave dispatch board, and incidents.

```sh
python3 report.py build --rids rid1,rid2,rid3 \
  --overlay examples/kit-absorptions.overlay.json --out report.html
```

Honest data split: spans, gates, statuses, and reasons come ONLY from the run
ledgers; model / PR / lane / incidents ride a declared overlay JSON until the
trace spine (ID-423) records those dims natively, at which point the overlay
shrinks to nothing. Zero-JS output; tooltips are title attributes.

### Event protocol

Runner and frontend are decoupled by JSONL events, one object per line; any
runner that emits these gets the TUI (and any future frontend) for free. The
real L1/L2/L3 runners plug in by emitting the same stream (`watch` mode).

| Event | Fields | Meaning |
|---|---|---|
| `run_start` | `run_id, scenario, layer, config, stages[]` | announce the plan; TUI shows all stages as pending |
| `stage_start` | `stage` | stage begins (spinner) |
| `item` | `stage, name, status, detail?, fingerprint?` | a sub-step inside a stage (worker, verifier, lens, check) |
| `retry` | `stage, attempt` | bounded retry; badge on the stage |
| `stage_end` | `stage, status, detail?, duration_s?, cost_usd?` | stage verdict |
| `run_end` | `status, totals{cost_usd,duration_s,retries,reproduce}` | final verdict + summary |

`dt` (seconds since previous event) is optional pacing metadata for `replay`.
Failure `item`s carry `fingerprint`: the verbatim failing case, so a red run
always answers "failed on what, exactly". The case inventory these runs will
cover lives in `docs/test-catalog.md` (L1 mechanism / L2 stage / L3 E2E).

## Tests

```sh
python3 tests/test_bench.py   # runner: hashing, scoring, summarize/diff, HTML render
python3 tests/test_tui.py     # frontend: state machine, mid-run frame, reports, roundtrip
```

Offline self-checks, no model calls.

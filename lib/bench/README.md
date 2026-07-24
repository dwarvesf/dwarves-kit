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

## Tests

```sh
python3 tests/test_bench.py
```

Offline self-check: hashing stability, fence-stripping, check-output parsing,
summarize/diff logic, HTML render. No model calls.

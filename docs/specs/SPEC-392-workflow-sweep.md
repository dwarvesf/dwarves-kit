# Spec: workflow sweep (test budget, serial waves, wrap land, load warning, suite timing history)

Generated: 2026-10-04
Status: VALIDATED (design: obvious, docs edits plus two small shell helpers; no validation fan-out run)
Lane: normal
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 05 (D5: warn on host load, never reroute; R11: persisted timing history, brief test budget).

## Problem

The kit-speed run lost about 90 minutes to five full `--all` runs. Two causes: nothing persisted per-suite timings, so every re-tune meant re-running everything, and worker briefs prescribed full runs, so a worker set `KIT_RUN_ALL=1` and walked past the `--all` refusal. The 2026-09-30 and 2026-10-01 retros name three more habits: same-module branches in one wave, hand-rolled push and merge loops, and heavy runs on an overloaded host.

## Design

- **a. Test budget in briefs.** `docs/patterns/worker-brief.md`, the goal-file template in `commands/mega.md`, and the two prompts that inline the brief (`commands/execute.md` builder prompt, `commands/dispatch.md` worker prompt) require: checks and negative controls on affected suites only (`bin/test-affected`, `tests/run-all.sh --changed`), never `--all` or `KIT_RUN_ALL=1`, timing questions answered from the suite history, and a stated wall-clock budget. A goal file never prescribes N full-suite runs.
- **b. Serial same-module branches.** `commands/mega.md` Step 4 (Touches text) and `commands/dispatch.md` Step 2 state: branches that touch the same module run one after the other inside a wave, and the first merges before the next worker starts.
- **c. Land with `bin/wrap land`.** `commands/ship.md` Step 8 and `commands/mega.md` Step 5 point at `bin/wrap land <worktree>` for landing a kit PR; the hand push-PR-merge recipe is rewritten to that pointer.
- **d. Host-load warning.** `lib/host/load-warn.sh` prints ONE line to stderr when the 1-minute load average is over a threshold (default 16; `KIT_LOAD_WARN` env, else `kit.toml` `[test].load_warn`). It suggests Devin or self-hosted CI. It always exits 0. `KIT_LOAD_STUB` replaces the real load for tests. `bin/test-affected` calls it before a run that executes suites (not `--list`), and `lib/queue/orchestrate.sh run` calls it once per real run (a dry run stays quiet). Both calls are fail-open.
- **e. Suite timing history.** Every `tests/run-all.sh` run appends one TSV line per suite (`utc_time sha suite seconds exit load1`) to `${KIT_SUITE_TIMES_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv}`, keeping the last `KIT_SUITE_TIMES_CAP` lines (default 20000). A write failure is swallowed: the run's exit code is unchanged. `tests/lib/suite-times.sh`, reached as `bash tests/run-all.sh --times <verb>`, prints per-suite p95 and run counts (`p95`), prints the expected wall time of a full run (`expected`), and rewrites `bin/test-affected.timeouts` by D4's rule, 2 x p95 with a 60 s floor, keeping every hand-set line that carries a comment (`tune`). `run-all.sh --all` under `KIT_RUN_ALL=1` prints one `expected wall` line from the history before starting; no history, no line.

## Verification

```
grep proofs for a, b, c (one Command/Exit/Verdict block each)
bash tests/test-host-load-warn.sh         # stub above, below, threshold 0 negative control, exit unchanged
bash tests/test-run-all-times.sh          # two runs append, p95 reads them, missing log falls back, unwritable dir keeps the exit code
bash tests/test-run-all-*.sh tests/test-test-affected.sh tests/test-bin-forwarders.sh tests/test-config-registry.sh
```

## Not proven

- The orchestrate suites were not run (test budget); the driver call is one fail-open line.
- The p95 helper is exercised on fixture history, not on a month of real runs.

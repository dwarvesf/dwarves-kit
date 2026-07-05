# SG-12: benchmark fixture (the measurement foundation)

Merge policy: gate
Time budget: ~1-2 sessions
Depends on: (none hard , no #80/#81; do this EARLY to establish baseline before the levers land)
Model: opus
Effort: high

## Directional outcome
Build the fixed, resettable benchmark that SG-09's ablation runs against. This is the
foundation: a bad benchmark gives bad proof (cherry-pick risk), so it is a `gate` , Han blesses
the task suite + checks before any number is trusted.

## Done =
`experiments/token-eval-bench/` with: (1) a git-resettable fixture (a small fixture repo or
directory whose pre-state is restored between trials); (2) a task suite of sub-goal-shaped
tasks, each with a DETERMINISTIC pass check , at minimum a code task (add a flag + test), a doc
task (write a doc with required sections), a debug task (planted failing test -> green), and
crucially ONE multi-sub-goal MINI-MEGA-GOAL (3 linked sub-goals) that exercises the
cross-sub-goal context reset (the orchestrator's headline claim); (3) a runner that resets the
fixture, runs a task through a configurable arm (e.g. `CLAUDE_CMD` / mode / model), and records
tokens (from the run transcript) + pass/fail + turns-to-green. A README documents the suite and
why each task is in it (anti-cherry-pick: include at least one task expected to NOT favor the new
approach). PR opened.

## Close the loop (verification)
```
ls experiments/token-eval-bench/README.md
bash experiments/token-eval-bench/reset.sh && bash experiments/token-eval-bench/run-task.sh <task> --arm baseline --dry-run
# the mini-mega-goal task is present (the cross-sub-goal test)
grep -ri 'mini-mega\|multi-sub-goal' experiments/token-eval-bench/
```

## Scope edges
`experiments/token-eval-bench/` only. The fixture must be SELF-CONTAINED and resettable (no
dependence on live repos / network / credentials, so trials are reproducible). Deterministic
checks only (no human judgement in the pass gate; quality-of-output review is SG-09's separate
spot-check). Do NOT wire it into the kit; it is an eval rig.

## Where to look
The token-hygiene SG-05 meta-agent experiment (its head-to-head + transcript-token reading is the
shape), `tools/token-forensic` (the token source), SG-09 (the consumer of this fixture , read its
ablation ladder so the runner's `--arm` matches).

## Proof expectation
A README + a runnable `reset.sh`/`run-task.sh` with a captured dry-run showing the suite + the
mini-mega-goal task present, and at least one real recorded arm-run (tokens + pass/fail) proving
the runner works end to end. Full reviewable proof.

## PR body
feat(experiment): token-eval-bench , a resettable benchmark fixture (tasks + deterministic checks
+ a mini-mega-goal) for the SG-09 ablation. Gated: the benchmark design is the proof foundation.

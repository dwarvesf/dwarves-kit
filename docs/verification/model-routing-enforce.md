# Proof of done , model-routing enforcement (SPEC-116, orchestrate-hardening sub-goal 01)

## Acceptance criteria (per the sub-goal's `Done =` line)

| # | Criterion | Status |
|---|---|---|
| 1 | Delegate call passes `--model` from the goal file's `Model:` field, default-applied, for opus/sonnet/haiku | met (run-table below; existing mechanism, SPEC-087, newly proven per-tier) |
| 2 | `route-suggest.sh`'s heuristic confirmed non-contradictory with an explicit `Model:` | met (structural: zero call sites in the dispatch path) |
| 3 | No-`Model:`-field fallback lands on the documented default (not a crash, not a silently wrong tier) | met (fallback = inherit, per SPEC-107; negative-control row below) |
| 4 | Open-fork 3 (enforcement site) resolved | met: `lib/orchestrate.sh`, pinned in SPEC-116 |
| 5 | Tests green | met (below) |

## Why this is a proof-and-pin, not a new feature

`_route()` (SPEC-087) and both delegate dispatch sites (serial `cmd_run`, concurrent `_wave_run`)
already threaded `Model:` into `--model` before this sub-goal started. `tests/test-orchestrate.sh`
TEST 8 already proved the `sonnet` tier + the inherit fallback on the serial path only. This sub-goal
adds the missing tiers (opus, haiku), the wave-path case, the route-suggest structural check, and
writes down the two decisions (enforcement site, fallback tier) that were previously implicit in code
comments and a different spec (SPEC-107), not yet load-bearing as an explicit pin. See
`docs/implementation-notes/model-routing-enforce.md` for the full delta trail.

## Run-table

`_route()` reads a goal file's bare `Model:` line and both delegate dispatch sites build
`route_flags="--model <tier>"`, threaded into the real `"$CLAUDE_CMD" -p $route_flags ...` call.

| Path | Goal file | Dispatched as | Result |
|---|---|---|---|
| serial | `Model: opus` | `--model opus` | default-applied, proven |
| serial | `Model: sonnet` | `--model sonnet` | default-applied, proven |
| serial | `Model: haiku` | `--model haiku` | default-applied, proven |
| serial | (no `Model:` line) | no `--model` flag | inherit fallback, proven (negative control) |
| wave (concurrent) | `Model: opus` | `--model opus` | default-applied, proven |
| n/a | `route-suggest.sh` call sites in `lib/orchestrate.sh` dispatch functions | 0 | structurally cannot contradict an explicit `Model:` |

## GREEN run

```
$ bash tests/test-model-routing.sh
PASS route-suggest alignment: lib/orchestrate.sh has no route-suggest.sh call site (cannot contradict an explicit Model: field)
PASS serial: Model: opus -> dispatch '--model opus' (default-applied)
PASS serial: Model: sonnet -> dispatch '--model sonnet' (default-applied)
PASS serial: Model: haiku -> dispatch '--model haiku' (default-applied)
PASS serial: no Model: field -> no --model flag (inherit fallback, no crash)
PASS wave: Model: opus -> dispatch '--model opus' (default-applied, concurrent delegate path)

=== 6/6 passed, 0 failed ===
```

Regression (unchanged, still green):

```
$ bash tests/test-orchestrate.sh
... (60 assertions) ...
ALL PASS

$ bash tests/test-meta.sh
Passed: 662 / 662
All meta tests passed.
```

`tests/test-routing.sh` (route-suggest.sh's own suite, untouched by this diff) needs bash 4+; green
under `/opt/homebrew/bin/bash`, fails on this host's stock `/bin/bash` 3.2 , a pre-existing environment
gap unrelated to this change (confirmed present on `master` before this diff too).

## Independent review

`kit:code-reviewer` (test-coverage lens) mutation-tested the new suite: broke the `--model` flag build
on the serial dispatch line and, separately, the wave dispatch line, in a scratch copy of
`lib/orchestrate.sh`; the matching test cases correctly flipped to FAIL in each case, ruling out a
rubber-stamp test. No blocking findings. Two advisory gaps filed in the implementation notes (pre-
existing `_route()` parse edge cases untested repo-wide; wave path covers only the opus tier by
design).

## Reproduce

```bash
cd <dwarves-kit-worktree>
bash tests/test-model-routing.sh
bash tests/test-orchestrate.sh
bash tests/test-meta.sh
```

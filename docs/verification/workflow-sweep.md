# Proof of done: workflow sweep

Branch `docs/workflow-sweep` off master 8e7f970e. Spec: `docs/specs/SPEC-392-workflow-sweep.md`. Notes: `docs/implementation-notes/workflow-sweep.md`.

Verdict summary: items a to e each hold with their own block below; negative controls recorded for a, b, c (grep on master), d (threshold 0) and e (unwritable state dir, plus a mutation that makes run-all propagate the helper's failure). No full-suite run was made (test budget); suites run are listed with exit and wall time.

## Item a: test budget in briefs

```
Command: for f in docs/patterns/worker-brief.md commands/mega.md commands/execute.md commands/dispatch.md; do grep -q "KIT_RUN_ALL=1" $f && grep -q "tests/run-all.sh --times p95" $f && grep -qiE "wall[- ](clock )?budget" $f && echo "ok $f" || echo "MISSING $f"; done; ! grep -riE "KIT_RUN_ALL=1 .*(x[0-9]|[0-9] (full|runs))" commands/mega.md docs/patterns/worker-brief.md
Exit: 0
Output: ok docs/patterns/worker-brief.md / ok commands/mega.md / ok commands/execute.md / ok commands/dispatch.md; the final negated grep (no prescribed N full runs) found nothing
Verdict: PASS
```

```
NEGATIVE CONTROL
Command: git show 8e7f970e:<file> | grep -qiE "wall[- ](clock )?budget"   (file = worker-brief.md, mega.md)
Exit: 1, 1
Output: MISSING-on-master for both files, so the grep is not vacuous
Verdict: PASS
```

## Item b: same-module branches run serially inside a wave

```
Command: grep -q "run serially inside a wave" commands/mega.md && grep -q "Touches" commands/mega.md && grep -q "serially inside the wave" commands/dispatch.md
Exit: 0
Verdict: PASS
```

```
NEGATIVE CONTROL
Command: git show 8e7f970e:commands/mega.md | grep -q "run serially inside a wave"
Exit: 1
Verdict: PASS (the rule is absent on master)
```

## Item c: landing a kit PR points at bin/wrap land

```
Command: grep -q "bin/wrap land <worktree>" commands/ship.md && grep -q "bin/wrap land <worktree>" commands/mega.md && ! grep -q "Run .git pus[h] origin \[branch\]." commands/ship.md
Exit: 0
Verdict: PASS (the hand publish line in ship.md Step 8 is now the pointer)
```

```
NEGATIVE CONTROL
Command: git show 8e7f970e:commands/ship.md | grep -q "bin/wrap land <worktree>"
Exit: 1
Verdict: PASS (the pointer is absent on master)
```

## Item d: host-load warning

```
Command: KIT_LOAD_STUB=40.5 bash lib/host/load-warn.sh "bin/test-affected"
Exit: 0
Output: load-warn: 1-min load 40.5 is over 16; bin/test-affected will be slow and flaky here, consider Devin or self-hosted CI (warning only, nothing rerouted)
Verdict: PASS (one line, exit unchanged)
```

```
Command: KIT_LOAD_STUB=3.2 bash lib/host/load-warn.sh "bin/test-affected"
Exit: 0
Output: (nothing)
Verdict: PASS
```

```
NEGATIVE CONTROL
Command: KIT_LOAD_WARN=0 bash lib/host/load-warn.sh "bin/test-affected"   (real load, no stub)
Exit: 0
Output: load-warn: 1-min load 25.69 is over 0; bin/test-affected will be slow and flaky here, ...
Verdict: PASS (threshold 0 prints on a host that is quiet by the default threshold's standard)
```

```
Command: bash tests/test-host-load-warn.sh
Exit: 0
Output: load-warn: 18 passed, 0 failed   (includes bin/test-affected on a fixture repo: green suite exit 0 and red suite exit 1 with one warning each, --list silent)
Verdict: PASS
```

## Item e: suite timing history

```
Command: bash tests/test-run-all-times.sh
Exit: 0
Output: run-all-times: 17 passed, 0 failed   (two runs append 4 lines; p95 reads them; missing log falls back with a stderr note and exit 0; tune keeps hand-set lines; expected-wall line prints once; cap trims; unwritable state dir keeps exit 1 / 0)
Verdict: PASS
```

```
NEGATIVE CONTROL
Command: mutate tests/run-all.sh (`|| true` becomes `|| exit 9`) and tests/lib/suite-times.sh (append exits 1 on a failed mkdir); bash tests/test-run-all-times.sh; restore both from saved copies
Exit: 1
Output: FAIL: rc=9 (twice, the red and the green unwritable-dir cases); run-all-times: 15 passed, 2 failed. After the restore: 17 passed, 0 failed
Verdict: PASS (the unwritable-dir case detects a run-all that lets a log failure change its exit code)
```

## Suites run (one at a time, host load average 19 to 38)

| Suite | Exit | Wall |
|---|---|---|
| test-config-registry | 0 (59/59) | 35 s |
| test-test-affected | 0 (58/58) | 19 s |
| test-bin-forwarders | 0 (48/48) | 15 s |
| test-run-all-changed | 0 (12/12) | 4 s |
| test-run-all-time | 0 (4/4) | 9 s |
| test-run-all-timeout | 0 (8/8) | 5 s |
| test-run-all-times (new) | 0 (17/17) | 4 s |
| test-host-load-warn (new) | 0 (18/18) | 1 s |
| test-meta-agent | 0 | 1 s |
| test-meta-agents-commands | 0 | 5 s |
| test-meta-goal-ledger | 0 | 1 s |
| test-meta-plugin-hooks | 0 | 7 s |
| test-meta-review-verifiers | 0 | 1 s |
| test-meta-spec-depth | 0 | 1 s |
| test-meta-vmodel-dispatch | 0 | 2 s |
| test-meta-docs-registry (with the regenerated FEATURES.md) | 0 | 356 s |

The meta suites are the ones `bin/test-affected --base 8e7f970e --list` picked for this diff. No `--all`, no `KIT_RUN_ALL=1` outside fixture kits, no full sweep.

## Convergence-gate fixes

Fixes for the convergence-gate findings, made after the first proof. Each block names the test that holds it; every behavioral fix has a mutation negative control (mutate, run the test, restore from a saved copy with `command cp -f`).

```
Command: bash tests/test-test-affected-cache.sh   (case 1: PASS once, edit a glob-read input under commands/, run again)
Exit: 0
Output: test-affected-cache: 17 passed, 0 failed; the second run prints PASS tests/test-meta-agents-commands.sh, not CACHED, and an unchanged input still prints CACHED
Verdict: PASS (fix 1: the cache key hashes every changed path that picked the suite)
```

```
NEGATIVE CONTROL
Command: mutate the picked-path read in cache_key to /dev/null (the test builds the mutant itself, case 1b); run it on the same edit sequence
Exit: 0 (the test asserts the defect)
Output: ok: mutant: the changed glob-read input comes back CACHED (the defect)
Verdict: PASS
```

```
Command: bash tests/test-test-affected-cache.sh   (case 2: a change that hits the runner fallback, `bin/test-affected --list`)
Exit: 0
Output: tests/test-meta-agents-commands.sh  (runner tests/test-meta.sh: reads lib/board/unnamed.sh (no area attributed)); tests/test-meta.sh is not listed; each area runs under its own line of the timeouts file (TIMEOUT tests/test-meta-agents-commands.sh (limit 1s))
Verdict: PASS (fix 2: the runner is expanded the way run-all does)
```

```
NEGATIVE CONTROL
Command: sed the runner check in expand_runner to `# NORUNNER:`; bash tests/test-test-affected-cache.sh; command cp -f the saved bin/test-affected back
Exit: 1
Output: test-affected-cache: 11 passed, 6 failed (the area suites are not listed, tests/test-meta.sh is listed, no per-area timeout). Restored: 17 passed, 0 failed
Verdict: PASS
```

On the real tree, with a temporary untracked `lib/gate/ledger-key.sh`, `bin/test-affected --list` lists the eight area suites as `runner tests/test-meta.sh: reads ...` and never `tests/test-meta.sh`.

```
Command: bash tests/test-run-all-times.sh   (case 5: tune rules; the dry run, --allow-lower, --write twice)
Exit: 0
Output: run-all-times: 29 passed, 0 failed. test-heavy stays 900 (a p95 of 100 would lower it); --allow-lower gives 200. test-few (3 samples) stays 500, test-thin (2 samples, no line) is not added, test-newcomer (5 samples) is added at 80. test-killed (kills at 120 and 100) becomes 120, test-killedmany (candidate 60, kill at 250) becomes 250, test-wedged (one kill at 90, no line) becomes 90. An unknown flag exits 64.
Verdict: PASS (fix 3: kill rows are a floor, 5 samples before a line is replaced, never lowered without --allow-lower)
```

```
NEGATIVE CONTROL
Command: set MIN_SAMPLES=1 and drop the no-lowering condition in tests/lib/suite-times.sh; bash tests/test-run-all-times.sh; command cp -f the saved helper back
Exit: 1
Output: run-all-times: 27 passed, 2 failed (the tune dry run and the --allow-lower comparison). Restored: 29 passed, 0 failed
Verdict: PASS
```

```
Command: bin/test-affected --base HEAD~1 --list   (with a temporary untracked lib/gate/ledger-key.sh, then moved away)
Exit: 0
Output: tests/test-lane-telemetry.sh  (references lib/gate/ledger-key.sh)
Verdict: PASS (fix 4). The reference scan skips lines that start with #, so the name sits on a code line (`: "lib/gate/ledger-key.sh"  # ...`), not in a comment. The file lives on another branch, so the pick appears once it lands.
```

```
Command: bash tests/test-run-all-times.sh   (case 11 and case 5 header check)
Exit: 0
Output: with a stubbed load of 77 run-all prints one `load-warn:` line, ahead of the `run-all: 2 suites` line; a red suite on a loaded host still exits 1. `tune --write` replaced the old "three full parallel runs" paragraph with `# Source: suite-times history, 26 exit-0 samples across 7 suites, runs 2026-10-04 to 2026-10-04 (tuned <date>)`, kept the other header lines, and a second `--write` left one Rule line and one Source line.
Verdict: PASS (fix 5)
```

```
Command: bash tests/test-test-affected-cache.sh   (case 3) and bash tests/test-run-all-times.sh   (cases 1, 10)
Exit: 0
Output: a bin/test-affected run appends one row per suite that ran (none for a CACHED one) and one `run:test-affected` row with kind=run, selected=N, wall, exit, load, sha; --list appends nothing; run-all appends `run:run-all` rows; `bash tests/run-all.sh --times runs` prints the last 20 run rows and p50/p95 wall per entry point (run lines never show as suites in p95)
Verdict: PASS (addition)
```

Suites run for these fixes, one at a time, none of them a full sweep: test-test-affected 0 (44 s), test-test-affected-cache 0 (20 s), test-run-all-changed 0 (16 s), test-run-all-time 0 (10 s), test-run-all-timeout 0 (8 s), test-run-all-times 0 (16 s), test-host-load-warn 0 (6 s), test-lane-telemetry 0 (91 s), test-bin-forwarders 0 (12 s).

## Rollback

Revert the branch. The one durable side effect is the per-host log `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv`, which every `tests/run-all.sh` run now appends to. It lives outside the repo and holds only suite names, seconds, exit codes, a git sha and a load number. Deleting it loses history and nothing else; set `KIT_SUITE_TIMES_FILE` to a scratch path to stop writing to the default.

## Not proven

- The orchestrate suites (`test-orchestrate*`, picked because `lib/queue/orchestrate.sh` changed) were not run (test budget). The driver change is one `|| true` call, covered by a grep only.
- The p95 and tune verbs ran on fixture history, not on weeks of real runs. The `expected` wall is an estimate, since the log keeps no per-run wall time.
- The eight `test-meta` area suites were not re-run after these fixes (the fixes touch `bin/test-affected` and `tests/`, which no area reads by glob); the earlier run in this proof stands for the docs.
- Other suites that reference `kit.toml` or `commands/*.md` were not run, only the ones named above.

## Recorded run (lead: orchestrate suites the worker skipped)

Load average about 27 (over the default load_warn of 16).

Command: `bash tests/test-orchestrate.sh; bash tests/test-orchestrate-gate-dispatch.sh; bash tests/test-orchestrate-hardening.sh; bash tests/test-orchestrate-orca.sh` (each under its bin/test-affected.timeouts limit)
Exit: 0
Verdict: PASS, all four green (97 s, 23 s, 12 s, 146 s); the load warning goes to stderr and changes no verdict.

## Recorded run (lead: kill rule doubles)

A kill at N seconds means p95 is at least N, so D4 gives a limit of at least 2N; the first cut set exactly N, which kills the suite again.

Command: `bash tests/test-run-all-times.sh` with the pre-fix tests/lib/suite-times.sh copied in (NEGATIVE CONTROL)
Exit: 1
Verdict: 27 passed, 2 failed, as expected.

Command: `command cp -f <saved fixed copy> tests/lib/suite-times.sh; bash tests/test-run-all-times.sh`
Exit: 0
Verdict: PASS, 29 passed, 0 failed, tree clean.

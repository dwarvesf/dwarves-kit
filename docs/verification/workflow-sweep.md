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

## Rollback

Revert the branch. The one durable side effect is the per-host log `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv`, which every `tests/run-all.sh` run now appends to. It lives outside the repo and holds only suite names, seconds, exit codes, a git sha and a load number. Deleting it loses history and nothing else; set `KIT_SUITE_TIMES_FILE` to a scratch path to stop writing to the default.

## Not proven

- The orchestrate suites (`test-orchestrate*`, picked because `lib/queue/orchestrate.sh` changed) were not run (test budget). The driver change is one `|| true` call, covered by a grep only.
- The p95 and tune verbs ran on fixture history, not on weeks of real runs. The `expected` wall is an estimate, since the log keeps no per-run wall time.
- Other suites that reference `kit.toml` or `commands/*.md` were not run, only the ones named above.

## Recorded run (lead: orchestrate suites the worker skipped)

Load average about 27 (over the default load_warn of 16).

Command: `bash tests/test-orchestrate.sh; bash tests/test-orchestrate-gate-dispatch.sh; bash tests/test-orchestrate-hardening.sh; bash tests/test-orchestrate-orca.sh` (each under its bin/test-affected.timeouts limit)
Exit: 0
Verdict: PASS, all four green (97 s, 23 s, 12 s, 146 s); the load warning goes to stderr and changes no verdict.

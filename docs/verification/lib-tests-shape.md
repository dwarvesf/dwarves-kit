# Proof of done: lib-tests-shape

`tests/run-all.sh` and `bin/test-affected` now collect the module suites under `lib/<m>/tests/` as well as `tests/test-*.sh`. 39 suites that ran nowhere are wired in (37 module suites, the ported queue suite, the session-recall entry). 21 `lib/` modules gained a README. Design notes: `docs/implementation-notes/lib-tests-shape.md`.

## Gate table

| Claim | Evidence |
|---|---|
| Every module suite runs under the shared runner, alone and in parallel | run 1 |
| The ported queue suite and the session-recall entry run under the runner | runs 2 and 3 |
| The collection guard and the selection logic hold in fixture repos and on the real tree | run 4 |
| The runner and selector suites still pass | runs 5 and 6 |
| The module-table lint and the forwarder census still pass | run 7 |
| The meta suites still pass (registry freshness included) | run 8 |
| The diff-selected set is green except one suite that is red on origin/master | run 9 and run 10 |
| The collection change is load-bearing | negative control |

## Green runs

Run 1, the 37 module suites (plus one `tests/` suite whose name contains `lib-`):

```
Command: bash tests/run-all.sh --only lib- --time
Exit: 0
Output:

run-all: slowest:
  28s lib-stats-test-sessions-digest
  27s lib-stats-test-anomalies-advisor
  26s lib-stats-test-ceremony-lens
  25s lib-stats-test-feedback
  13s lib-stats-test-memory-lens
  8s lib-stats-test-review-yield
  7s lib-stats-test-deviation-rate
  5s lib-session-observe-smoke
  4s lib-stats-test-mega-durations
  4s lib-stats-test-ledger-cli

run-all: all 38 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 2, the queue suite ported from bats (29 cases, one assertion mutated to confirm a failure shows):

```
Command: bash tests/run-all.sh --only test-queue --time
Exit: 0
Output:
run-all: slowest:
  14s test-queue

run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 3, the session-recall entry:

```
Command: bash tests/run-all.sh --only test-session-recall --time
Exit: 0
Output:
run-all: slowest:
  1s test-session-recall

run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 4, the collection guard (fixture repos for `run-all.sh`, `--changed`, `--failed` and `--only`; the real tree for orphans):

```
Command: bash tests/run-all.sh --only test-suites-collect --time
Exit: 0
Output:
run-all: slowest:
  3s test-suites-collect

run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 5, the runner suites:

```
Command: bash tests/run-all.sh --only run-all --time
Exit: 0
Output:
test-run-all-tmpdir                            ok (0s)

run-all: slowest:
  11s test-run-all-timeout
  8s test-run-all-time
  4s test-run-all-times
  3s test-run-all-changed
  0s test-run-all-tmpdir

run-all: all 5 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 6, the selector suites:

```
Command: bash tests/run-all.sh --only test-affected --time
Exit: 0
Output:

run-all: slowest:
  24s test-test-affected
  22s test-test-affected-parallel
  5s test-test-affected-cache
  1s test-test-affected-replay

run-all: all 4 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 7, the module-table lint and the forwarder census:

```
Command: bash tests/run-all.sh --only test-kit-contract --time
Exit: 0
Output:
  4s test-kit-contract

run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only test-bin-forwarders --time
Exit: 0
Output:
  5s test-bin-forwarders

run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 8, the meta suites:

```
Command: bash tests/test-meta.sh
Exit: 0
Output:
=== Results ===
Passed: 930 / 930
All meta tests passed.
Verdict: PASS
```

Run 9, the diff-selected set against `origin/master`. 141 suites ran. One is red, and it is red on `origin/master` too (run 10):

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 1
Output:

run-all: slowest:
  87s test-wrap-apply
  84s test-wrap-land
  80s test-wrap-merge
  79s test-wrap-adopt
  47s test-lane-telemetry
  46s test-board-work
  40s test-precedent
  40s test-intake-sweep-parity
  39s test-wrap-ci
  36s test-runaway-guards

run-all: FAILED -> test-codex-hooks
run-all: 141 suites run, 0 skipped for missing tooling
bash tests/run-all.sh --changed origin/master --time  535.17s user 708.67s system 284% cpu 7:17.42 total
Result: 140 of 141 green; the one red suite is not touched by this change (run 10)
```

Run 10, the stale pin behind that red suite, on a clean export of `origin/master` (`git archive origin/master hooks lib/codex`):

```
Command: bash lib/codex/repin.sh check <export of origin/master>
Exit: 1
Output:
repin: stale pin: hooks/commit-format.sh
Result: red before this change. The pin went stale when commit-format.sh was edited without a repin; `bash lib/codex/repin.sh` fixes it.
```

Selection demo: a one-line edit to `lib/session/audit/prompt.md` (reverted after) picks the module suites with the reason `module lib/session`:

```
Command: bash bin/test-affected --base HEAD --list
Exit: 0
Output:
test-affected: 1 changed files against HEAD
  lib/session/audit/tests/smoke.sh  (module lib/session)
  lib/session/intel/tests/smoke.sh  (module lib/session)
  lib/session/observe/tests/smoke.sh  (module lib/session)
  lib/session/observe/tests/test-vps-report.sh  (module lib/session)
  lib/session/tests/test-handoffs.sh  (module lib/session)
  lib/session/tests/test-parse-transcript.sh  (module lib/session)
  tests/test-meta-plugin-hooks.sh  (reads lib/session/audit/prompt.md)
  tests/test-session-recall.sh  (module lib/session)
Verdict: PASS
```

`docs/reference/FEATURES.md` is generated. It drifted by four test-count cells and was regenerated with `bash lib/registry/feature-registry.sh check --fix docs/reference/FEATURES.md`.

## Negative control

Revert the collection change: `suite_list` goes back to `tests/test-*.sh` only. The check is the collection guard, then a direct check that `run-all.sh --only` finds a module suite.

## Negative control (negctl)
Command: bash tests/test-suites-collect.sh
Exit: 0 (green before mutation)
Output:
    ok: run-all --changed runs lib-m-test-x, lib-m-smoke, lib-m-sub-test-y and nothing else
    ok: a nested path picks the whole module's suites, sub-tool ones included
    ok: a changed module suite picks itself only
  [6] --failed reruns a module suite from the history by its id
    ok: only lib-m-sub-test-y reran
  [7] real tree: every module suite on disk is collected, ids are unique
    ok: no module suite is left out of suite_list; no duplicate id
  [8] real tree: every Python test under lib/ is reached by a tests/test-*.sh
    ok: bench, sync, webcheck and session-recall each have a root entry
  test-suites-collect: all 12 passed

Mutation: perl -0pi -e 's/ lib\/\*\/tests\/test-\*\.sh lib\/\*\/tests\/smoke\.sh \\\n\s+lib\/\*\/\*\/tests\/test-\*\.sh lib\/\*\/\*\/tests\/smoke\.sh;/;/' tests/lib/suites.sh
Changed: tests/lib/suites.sh
Exit: 1 (under mutation, RED expected)
Output:
  lib/stats/tests/test-render-skill.sh
  lib/stats/tests/test-review-yield.sh
  lib/stats/tests/test-schema-conform.sh
  lib/stats/tests/test-schema-parity.sh
  lib/stats/tests/test-sessions-digest.sh
  lib/telemetry/tests/smoke.sh
  lib/worktree-provision/tests/smoke.sh dupes: 
  [8] real tree: every Python test under lib/ is reached by a tests/test-*.sh
    ok: bench, sync, webcheck and session-recall each have a root entry
  test-suites-collect: 2 passed, 10 FAILED

Restore: git checkout HEAD -- tests/lib/suites.sh
Exit: 0 (green after restore)
Verdict: PASS

## Negative control (negctl)
Command: bash tests/run-all.sh --only lib-skill-curator-test-surface | grep -E '^lib-skill-curator-test-surface +ok'
Exit: 0 (green before mutation)
Output:
  .
  lib-skill-curator-test-surface                 ok

Mutation: perl -0pi -e 's/ lib\/\*\/tests\/test-\*\.sh lib\/\*\/tests\/smoke\.sh \\\n\s+lib\/\*\/\*\/tests\/test-\*\.sh lib\/\*\/\*\/tests\/smoke\.sh;/;/' tests/lib/suites.sh
Changed: tests/lib/suites.sh
Exit: 1 (under mutation, RED expected)
Output:
  

Restore: git checkout HEAD -- tests/lib/suites.sh
Exit: 0 (green after restore)
Verdict: PASS

The mutation is restored by `git checkout HEAD -- tests/lib/suites.sh`, which negctl runs; the tree is clean afterwards.

## Rollback

Revert the three code commits on `chore/lib-tests-shape`: the collection change, the READMEs, and the ceiling line. `tests/test-queue.bats` returns with the revert. Nothing else needs undoing: no state, no config, no deployed artifact. Until reverted, a host without `uv` skips the stats suites with a stated reason, and `RUN_ALL_TIMEOUT_SECS` still overrides every ceiling.

## Not proven

- GitHub Actions was not dispatched. The module suites ran here with a fake `HOME`, no `claude`, Python 3.15 and a cold uv cache, which is the nearest local stand-in for a runner.
- The 120 s and 180 s ceilings on the uv-backed stats suites are hand-set from this host. Re-measure on a CI run before tightening.
- `tests/lib/test-affected-replay.sh` does not yet replay module-suite picks.
- `tests/test-codex-hooks.sh` is red on `origin/master` and stays red here.

## Codex hook repin

`hooks/commit-format.sh` changed on master without a repin, so `tests/test-codex-hooks.sh` was red there. `bash lib/codex/repin.sh .` refreshed its pin on this branch.

```
Command: bash tests/test-codex-hooks.sh
Exit: 0
Output:
94 passed, 0 failed
Verdict: PASS
```

## ubuntu 26.04 failures (CI run 40370883570)

Three module suites that never ran on Linux before failed on ubuntu-latest (26.04). Causes and fixes: `docs/implementation-notes/lib-tests-shape.md`, section "ubuntu 26.04 round".

### Baseline (before the fix, same container)

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash lib/session/tests/test-handoffs.sh'   (at 3723a187)
Exit: 1
Output:
  FAIL: expected UNCITED tag, got:
/home/runner/kit/lib/session/handoffs.sh: line 200: File: unbound variable
Verdict: FAIL (the baseline this fix addresses)
```

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash lib/skill-curator/tests/test-curate.sh'   (at 3723a187)
Exit: 1
Output:
  ok: CC_SI_* alias resolves + warns; canonical wins when both set
test-curate: 9 passed, 2 FAILED
Verdict: FAIL (the baseline this fix addresses)
```

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash lib/stats/tests/test-memory-lens.sh'   (at 3723a187)
Exit: 1
Output:
PASS  O8-real-index-flags-orphan OK (a real link index still flags its orphan + missing link)
== 39 passed, 1 failed ==
Verdict: FAIL (the baseline this fix addresses)
```

### After the fix

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash lib/session/tests/test-handoffs.sh'
Exit: 0
Output:
  ok: empty root reported, not silent
smoke: all 43 passed
Verdict: PASS
```

```
Command: bash lib/session/tests/test-handoffs.sh   (macOS)
Exit: 0
Output:
  ok: empty root reported, not silent
smoke: all 43 passed
Verdict: PASS
```

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash lib/skill-curator/tests/test-curate.sh'
Exit: 0
Output:
  ok: CC_SI_* alias resolves + warns; canonical wins when both set
test-curate: all 11 passed
Verdict: PASS
```

```
Command: bash lib/skill-curator/tests/test-curate.sh   (macOS)
Exit: 0
Output:
  ok: CC_SI_* alias resolves + warns; canonical wins when both set
test-curate: all 11 passed
Verdict: PASS
```

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash lib/stats/tests/test-memory-lens.sh'
Exit: 0
Output:
PASS  O8-real-index-flags-orphan OK (a real link index still flags its orphan + missing link)
== 40 passed, 0 failed ==
Verdict: PASS
```

```
Command: bash lib/stats/tests/test-memory-lens.sh   (macOS)
Exit: 0
Output:
PASS  O8-real-index-flags-orphan OK (a real link index still flags its orphan + missing link)
== 40 passed, 0 failed ==
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only lib-   (CI=true, ubuntu 26.04 container)
Exit: 0
Output:
lib-stats-test-memory-lens                     ok
lib-session-intel-smoke                        ok
run-all: all 38 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

### Negative control

macOS has a BSD `stat` that rejects `-c`, so the BSD-first line passes there by accident. The control puts GNU `stat` first on PATH (`$GSTAT/stat` is a symlink to Homebrew `gstat`), which is the Linux behavior, and restores the old BSD-first mtime line in `lib/session/handoffs.sh`. The suite goes red with the Linux symptom; it is green with the fix.

```
Command: bash lib/gate/negctl.sh "$PWD" "PATH=$GSTAT:$PATH bash lib/session/tests/test-handoffs.sh" "<restore: mtime=\"$(stat -f '%m' \"$f\" 2>/dev/null || stat -c '%Y' \"$f\" 2>/dev/null)\">"
Command: PATH=/private/tmp/claude-501/-Users-tieubao-workspace-tieubao-ops-toolkit/ec4ab502-2444-4394-bd5d-3a50deac26b5/scratchpad/m/gstatdir:$PATH bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Output:
    ok: two roots, given order, one total
  [32] bare --under expands the wrap.roots knob (stubbed), root-only
    ok: bare --under walks both knob roots in listed order
    ok: bare --under followed by a flag still expands the knob
  [33] NC bare --under with an empty knob: usage error naming wrap.roots, exit 64
    ok: exit 64: handoffs list: --under given no directory and wrap.roots is empty
  [34] NC a root with no git repos: stderr note, zero total, exit 0
    ok: empty root reported, not silent
  
  smoke: all 43 passed

Mutation: python3 /private/tmp/claude-501/-Users-tieubao-workspace-tieubao-ops-toolkit/ec4ab502-2444-4394-bd5d-3a50deac26b5/scratchpad/m/r4/mut.py
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Output:
  [7] NC empty repo: honest 'no handoffs', exit 0
    ok: no handoffs, exit 0
  [8] NC unknown subcommand: usage error, exit 64
    ok: exit 64 on unknown subcommand
  [9] liveness: a file with no cited row IDs is tagged UNCITED
    FAIL: expected UNCITED tag, got: 
  warning: templates not found in ~/.git_template
  warning: templates not found in ~/.git_template
  warning: templates not found in ~/.git_template
  ~/workspace/dwarvesf/dwarves-kit/.claude/worktrees/lib-tests-shape/lib/session/handoffs.sh: line 201: File: unbound variable

Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

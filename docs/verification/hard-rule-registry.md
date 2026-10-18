# Proof of done: hard claims need code, queue and converge completion need evidence

Acceptance: (1) `docs/hard-rules.tsv` lists every rule code really blocks on and `tests/test-meta-hard-claims.sh` fails a doc HARD mark that names no row and a row whose enforcer, rule, test or needle is missing; (2) `_wave_converge` emits `merged` only when `gh pr view` reports the PR MERGED, else `merge-dry-run`; (3) `queue.sh` journals `done` only when HEAD moved or a PR was created since the window opened, else `gated` with reason `no-delta`; (4) the drift rows named in the brief are fixed in their docs. Lane: full (the diff touches `lib/queue/` and the gate docs). Files: `docs/hard-rules.tsv`, `tests/test-meta-hard-claims.sh`, `tests/test-wave-converge.sh`, `lib/queue/orchestrate.sh`, `lib/queue/queue.sh`, `lib/queue/watch-board.sh`, the queue suites and their fixture mux, plus the docs and comments of the drift rows.

## The gaps this closes

| Claim | Where | What the code did |
|---|---|---|
| a gate is HARD | `docs/WORKFLOW.md`, `workflow-map.md`, `workflow-paths.md` for spec-drift-guard, the verification pipeline, the design-record lens | `spec-drift-guard` only warns; the pipeline and reviewer 6 are command prose |
| wave converge recorded `merged` | `lib/queue/orchestrate.sh` | `mega-merge.sh merge` is a dry run that exits 0; converge emitted `merged` on the exit code |
| `done` | `lib/queue/queue.sh`, `watch-board.sh` | a `RUNNER_DONE` pane marker or `EXIT_SIGNAL: true` was journaled `done` with no commit and no PR |

## Green run

```
Command: bash tests/test-meta-hard-claims.sh
Exit: 0
Output:
  registry has rows (27)
  every registry row is real (enforcer, rule, test, needle, gate)
  NC: planted row x.nofile is flagged ... x.wrongdefault is flagged (6 planted rows)
  the scan reached the live docs (171 files, 34 HARD mentions)
  every HARD mark names a registry rule
  NC: a HARD mark naming no rule (spec-drift-guard) is flagged
  Passed: 22 / 22
Verdict: PASS
```

```
Command: bash tests/test-wave-converge.sh
Exit: 0
Output:
  PASS dry run: merge-dry-run event, no merged event (rc 0)
  PASS PR MERGED: merged event (rc 0)
  PASS hook called with the PR number first
  PASS PR CLOSED: no merged event
  PASS hook failure: blocked event, rc 3
  PASS unreadable gh: not merged
  PASS ROADMAP line unchanged after a dry run
  All wave-converge tests passed.
Verdict: PASS
```

```
Command: bats tests/test-queue.bats
Exit: 0
Output:
  1..27
  ok 24 W5 wait bad-slug and missing-slug -> exit 64
  ok 25 D1 no-delta: RUNNER_DONE with no commit and no PR -> gated no-delta
  ok 26 D2 pr-delta: a PR created during the run -> done without a HEAD move
  ok 27 D3 pr-delta: gh reports no new PR -> gated no-delta
  (27 ok, 0 not ok; D1 to D3 are the new delta cases)
Verdict: PASS
```

```
Command: bash tests/test-runaway-guards.sh && bash tests/test-notes-sanitization.sh && bash tests/test-cheap-guards.sh
Exit: 0
Output:
  test-runaway-guards:     === 48/48 passed, 0 failed ===
  test-notes-sanitization: === 52/52 passed, 0 failed ===
  test-cheap-guards:       === 23/23 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output:
  === HARD marks in live docs name a registry rule ===
  Passed: 22 / 22
  All hard-claim tests passed.
  === Results ===
  Passed: 924 / 924
  All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (host load average 157; see the reruns below)
Output:
  run-all: --changed against ab38a33d: 35 changed files -> 107 suites (103 named, the rest always-on)
  run-all: FAILED -> test-meta-docs-registry
  run-all: TIMED OUT at 300s -> test-board-mirror(60s) test-config-registry(164s) test-harvest-sweep(90s) test-install-clis(66s) test-install-compat(82s) test-install-modules(126s) test-lanes-data(692s)
  run-all: 107 suites run, 0 skipped for missing tooling
Verdict: one real failure, fixed, plus ten load timeouts rerun alone
```

The one failure was the registry-freshness pin: the two new test files moved a feature row's test counts. `bash lib/registry/feature-registry.sh generate docs/FEATURES.md` fixed it. Every other picked suite passed in that run. The timed-out suites and the failed one, rerun alone after the fix:

```
Command: for t in test-meta-docs-registry test-config-registry test-tier4-close test-board-mirror test-harvest-sweep test-install-clis test-install-compat test-install-modules test-ship-gate-impl-notes test-lanes-data test-wrap-merge; do bash tests/$t.sh; done
Exit: 0 for every suite
Output:
  test-meta-docs-registry rc=0
  test-config-registry rc=0
  test-tier4-close rc=0
  test-board-mirror rc=0 (45s)
  test-harvest-sweep rc=0 (45s)
  test-install-clis rc=0 (37s)
  test-install-compat rc=0 (35s)
  test-install-modules rc=0 (54s)
  test-ship-gate-impl-notes rc=0 (53s)
  test-lanes-data rc=0 (310s)
  test-wrap-merge rc=0 (159s)
Verdict: PASS
```

## Negative control

Converge: the state check forced true, so a dry run records `merged`.

```
Command: bash tests/test-wave-converge.sh
Exit: 0 (green before mutation)
Output:
  PASS dry run: merge-dry-run event, no merged event (rc 0)
  PASS PR MERGED: merged event (rc 0)
  PASS hook called with the PR number first
  PASS PR CLOSED: no merged event
  PASS hook failure: blocked event, rc 3
  PASS unreadable gh: not merged
  PASS ROADMAP line unchanged after a dry run
  ---
  All wave-converge tests passed.

Mutation: perl -i -pe 's/\[ "\$state" = MERGED \]/true/' lib/queue/orchestrate.sh
Changed: lib/queue/orchestrate.sh
Exit: 3 (under mutation, RED expected)
Output:
  FAIL dry run: rc=0 events='merged '
  PASS PR MERGED: merged event (rc 0)
  PASS hook called with the PR number first
  FAIL PR CLOSED: rc=0 events='merged '
  PASS hook failure: blocked event, rc 3
  FAIL unreadable gh: events='merged '
  PASS ROADMAP line unchanged after a dry run
  ---
  3 failed.

Restore: git checkout HEAD -- lib/queue/orchestrate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Queue: the delta check forced off, so a claim with no delta stays `done`.

```
Command: bash tests/test-runaway-guards.sh
Exit: 0 (green before mutation)
Output:
    PASS C4 NC: a malformed EXIT_SIGNAL never yields done
    PASS C4 NC: the verdict names the malformed signal
    PASS C5: no status file -> the pane marker still yields done
    PASS C6: the typed /goal line names the EXIT_SIGNAL contract
    PASS C6: the typed /goal line names the slug's status path
  
  === 48/48 passed, 0 failed ===

Mutation: perl -i -pe 's/! _run_delta "\$repo" "\$head_before" "\$started_iso"/false/' lib/queue/queue.sh
Changed: lib/queue/queue.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS C4 NC: a malformed EXIT_SIGNAL never yields done
    PASS C4 NC: the verdict names the malformed signal
    PASS C5: no status file -> the pane marker still yields done
    PASS C6: the typed /goal line names the EXIT_SIGNAL contract
    PASS C6: the typed /goal line names the slug's status path
  
  === 44/48 passed, 4 failed ===

Restore: git checkout HEAD -- lib/queue/queue.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Registry: the removed HARD label put back on spec-drift-guard in `docs/WORKFLOW.md`.

```
Command: bash tests/test-meta-hard-claims.sh
Exit: 0 (green before mutation)
Output:
  === HARD marks in live docs name a registry rule ===
    PASS the scan reached the live docs (171 files, 24 HARD mentions)
    PASS every HARD mark names a registry rule (a HARD with no code behind it must say warns or advisory)
    PASS NC: a HARD mark naming no rule (spec-drift-guard) is flagged
    PASS NC: a HARD mark naming ship-gate, and a legend pointing at the registry, pass
    PASS spec-drift-guard never exits 2 (it warns)
  
  === Results ===
  Passed: 22 / 22
  All hard-claim tests passed.

Mutation: perl -i -pe 's/spec-drift-guard   \(warns only\)/spec-drift-guard   [HARD]/' docs/WORKFLOW.md
Changed: docs/WORKFLOW.md
Exit: 1 (under mutation, RED expected)
Output:
    PASS the scan reached the live docs (171 files, 25 HARD mentions)
    FAIL every HARD mark names a registry rule (a HARD with no code behind it must say warns or advisory) (expected '', got 'docs/WORKFLOW.md:181:  Spec  ------>  spec exists, Status: DRAFT  ------>  spec-drift-guard   [HARD]')
      docs/WORKFLOW.md:181:  Spec  ------>  spec exists, Status: DRAFT  ------>  spec-drift-guard   [HARD]
    PASS NC: a HARD mark naming no rule (spec-drift-guard) is flagged
    PASS NC: a HARD mark naming ship-gate, and a legend pointing at the registry, pass
    PASS spec-drift-guard never exits 2 (it warns)
  
  === Results ===
  Passed: 21 / 22
  Failed: 1

Restore: git checkout HEAD -- docs/WORKFLOW.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- `gh pr list` is only stubbed; the real `createdAt` filter ran against no live repository.
- Converge's real merge path (`mega-merge.sh merge ... --execute` then `gh pr view` reporting MERGED) is covered with a `gh` stub, not a live PR.
- The registry proves a rule exists and a test asserts its block; it does not prove the test exercises the live hook wiring in `hooks/hooks.json`.
- `docs/architecture.md`, `docs/hooks.md`, `lib/gate/README.md`, `README.md`, `AGENTS.md` and the root `WORKFLOW.md` still carry stale wording; they are listed under "Needs from others" in the PR.

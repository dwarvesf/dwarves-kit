# Proof of done: hard claims need code, queue and converge completion need evidence

Acceptance: (1) `docs/hard-rules.tsv` lists the rules code really blocks on, each with a proving test, and `tests/test-meta-hard-claims.sh` fails a doc HARD mark that names no row and a row whose enforcer, rule, call site, test or needle is missing; (2) `_wave_converge` emits `merged` only when `gh pr view` reports the PR MERGED, else `merge-dry-run`; (3) `queue.sh` journals `done` only when HEAD, a local branch tip or an operator PR moved since the window opened, else `gated` with reason `no-delta`; (4) the drift rows named in the brief are fixed in their docs. Lane: full (the diff touches `lib/queue/`, `hooks/harvest.sh` and the gate docs). Files: `docs/hard-rules.tsv`, `tests/test-meta-hard-claims.sh`, `tests/test-wave-converge.sh`, `lib/queue/orchestrate.sh`, `lib/queue/queue.sh`, `lib/queue/watch-board.sh`, the queue suites and their fixture mux, plus the docs and comments of the drift rows.

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
  registry has rows (28)
  every registry row is real (enforcer, rule, call site, test, needle, gate)
  NC: planted row x.nofile is flagged ... x.keynotread is flagged (9 planted rows)
  the scan reached the live docs (171 files, 34 HARD mentions)
  every HARD mark names a registry rule
  NC: only the two unnamed marks are flagged; ship-gate and the legend pass
  Passed: 25 / 25
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
  1..29
  ok 25 D1 no-delta: RUNNER_DONE with no commit and no PR -> gated no-delta
  ok 26 D2 pr-delta: a PR created during the run -> done without a HEAD move
  ok 27 D3 pr-delta: a PR older than the window -> gated no-delta
  ok 28 D4 branch-delta: a new local branch with no HEAD move and no gh -> done
  ok 29 D5 no-delta-idempotence: the second run over the same tsv opens no second window
  (29 ok, 0 not ok; D1 to D5 are the new delta cases)
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
  Passed: 25 / 25
  All hard-claim tests passed.
  === Results ===
  Passed: 932 / 932
  All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (test-flick only: a timing check under host load; it passes alone, see below)
Output:
  run-all: --changed against b6794c4e: 40 changed files -> 111 suites (107 named, the rest always-on)
  test-flick   FAIL (rc=1) (109s)   !   FAIL: ps shows curl really was in flight (the check is not vacuous)
  run-all: FAILED -> test-flick
  run-all: 111 suites run, 0 skipped for missing tooling
Verdict: 110 of 111 suites passed; the one failure is load-sensitive and passes alone (next block)
```

```
Command: bash tests/test-flick.sh
Exit: 0
Output:
  ok: a failed call logs the error against the sent slug
  ok: a failed lookup sends nothing
  flick: 346 passed, 0 failed
Verdict: PASS
```

`test-flick` asserts that `ps` still sees a `curl` in flight; on a host at load average 19 the process had already ended. The suite reads nothing this branch changes. An earlier run of the same command, before the review fixes and under a host load average of 157, timed out ten suites (the runner's ceiling, not an assertion) and failed `test-meta-docs-registry`, because the two new test files moved a feature row's counts. `bash lib/registry/feature-registry.sh generate docs/FEATURES.md` fixed that and each timed-out suite then passed alone. A later full repeat, after the review fixes, passed all 108 picked suites.

## Review

Two read-only `kit:code-reviewer` lenses returned FIX THEN SHIP on the first build. Applied: the raw `queue run` skips a `gated` `no-delta` row (D5); a moved local branch tip counts as delta for a worktree run with no `gh` (D4); only the operator's PRs count, and the stub now runs the real jq filter (D2, D3); converge reads PR state from the repo toplevel; the reaper says `unverified`; the three anti-rationalization rows carry the real `off:understanding_gate` default; the registry gained a `wired` column and call-site literals, drops the `unaccounted-push` row (no test proved `_refs_block`), and the suite cross-checks each hook's gate column; the doc scan narrows its definition exemption; docs now qualify commit-format, anti-rationalization and the proof and lane arms of ship-gate as off by default. Accepted: a registry term is matched anywhere on the line, so a mark naming two rules passes; `lib/**/*.md` and `adapters/` are not scanned (none contain HARD).

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

Mutation: perl -i -pe 's/! _run_delta "\$repo" "\$head_before" "\$tips_before" "\$started_iso"/false/' lib/queue/queue.sh
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
    PASS NC: only the two unnamed marks are flagged; ship-gate and the legend pass
    PASS spec-drift-guard never exits 2 (it warns)
  
  === Results ===
  Passed: 25 / 25
  All hard-claim tests passed.

Mutation: perl -i -pe 's/spec-drift-guard   \(warns only\)/spec-drift-guard   [HARD]/' docs/WORKFLOW.md
Changed: docs/WORKFLOW.md
Exit: 1 (under mutation, RED expected)
Output:
    PASS the scan reached the live docs (171 files, 25 HARD mentions)
    FAIL every HARD mark names a registry rule (a HARD with no code behind it must say warns or advisory) (expected '', got 'docs/WORKFLOW.md:181:  Spec  ------>  spec exists, Status: DRAFT  ------>  spec-drift-guard   [HARD]')
      docs/WORKFLOW.md:181:  Spec  ------>  spec exists, Status: DRAFT  ------>  spec-drift-guard   [HARD]
    PASS NC: a HARD mark naming no rule (spec-drift-guard) is flagged
    PASS NC: only the two unnamed marks are flagged; ship-gate and the legend pass
    PASS spec-drift-guard never exits 2 (it warns)
  
  === Results ===
  Passed: 24 / 25
  Failed: 1

Restore: git checkout HEAD -- docs/WORKFLOW.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

No state migrates. `git revert` of the merge restores the old `done` rule, the old converge event and the old docs. Journal rows written meanwhile stay valid: a `gated` row with reason `no-delta` or `unverified` is an ordinary terminal row the old code also reads, and a `merge-dry-run` event is an extra status string the board view ignores. `docs/hard-rules.tsv` is read only by `tests/test-meta-hard-claims.sh`.

## Not proven

- `gh pr list` is only stubbed (the stub runs the real jq filter over a canned payload); no live repository was queried.
- Converge's real merge path (`mega-merge.sh merge ... --execute` then `gh pr view` reporting MERGED) is covered with a `gh` stub, not a live PR.
- The registry proves a rule exists, is wired where a lib rule needs wiring, and a test asserts its block; it does not prove the hook is registered in `hooks/hooks.json` or `settings.json`, and it omits blocks no test proves (doc-projection, the ship-rules load failure, the `_refs_block` push parse, citation-guard strict mode, other mega-merge refusals).
- `docs/architecture.md`, `lib/gate/README.md`, `README.md`, `AGENTS.md`, the root `WORKFLOW.md` and `docs/guides/` still carry stale wording; they are listed under "Needs from others" in the PR.

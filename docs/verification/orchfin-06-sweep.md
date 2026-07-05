# Proof of done: orchestrate.sh hardening sweep (ID-095/096/098)

Three independent, individually-too-small-for-their-own-PR fixes to
`lib/queue/orchestrate.sh`, batched as one tiny sweep (`orchestrator-finish` sub-goal 06).

## Acceptance criteria

| # | Criterion | Item | Result |
|---|---|---|---|
| 1 | `.orchestrate/*.stream.jsonl`/`*.session.log` older than the retention cap are pruned; a fresh file is left alone (NEGATIVE CONTROL) | ID-095a | PASS |
| 2 | A secret-shaped line in a real captured stream is redacted before the file is handed back to the caller | ID-095b | PASS |
| 3 | An off-allowlist `Model:` tier is rejected pre-flight; the mock `claude` is never invoked, no false-complete | ID-096 | PASS |
| 4 | A wave sub-goal that lands cleanly (shipped) has its tmux window killed; no orphaned pane | ID-098 | PASS |
| 5 | No regression: `test-orchestrate.sh`, `test-model-routing.sh`, `test-multiplexer.sh`, `test-orchestrate-wavefront.sh` still green | all | PASS |

## Implementation

- `lib/queue/orchestrate.sh` `_route()` (:478-511): `_ROUTE_MODEL_ALLOWLIST="opus sonnet haiku"`
  constant + a case-insensitive allowlist check. An off-allowlist `Model:` value now prints a
  clear rejection to stderr and returns 64 (ID-096). All three dispatch call sites (`_wave_run`
  spawn loop, `cmd_run` serial dispatch, the `--dry-run` preview) read `_route`'s exit status via
  `out=$(_route "$gf"); rc=$?` (a simple command-substitution assignment reflects the command's
  own exit code, unlike the `< <(...)` process substitution the code used before, which would
  have reflected `read`'s exit status instead) and, on `cmd_run`/`_wave_run`, reject the sub-goal
  before any session spawns , same treatment as a `gate` sub-goal (serial: `return 0` + STOP
  message; wave: `wave_failed=1` + `continue`, draining siblings, per the existing worktree-setup-
  failure precedent right above it).
- `lib/queue/orchestrate.sh` new section "Stream retention + redaction (ID-095)" (:698-745):
  `STREAM_RETENTION_DAYS` (default 14), `_redact_secrets_file()` (write-temp-then-`mv`, sed -E over
  common API-key/token shapes -> `[REDACTED]`), `_prune_streams()` (portable `find -mtime +N`,
  removes `.orchestrate/*.stream.jsonl`/`*.session.log` past the cap). `_prune_streams` is called
  at the start of `cmd_next` and at the start of a real (non-`--dry-run`) `cmd_run`.
  `_redact_secrets_file` is called on every captured slog before it is surfaced/returned, in both
  `_run_session_watchdog` (the SG-11 watchdog capture path) and `_run_one_session` (the
  stream-json + plain-with-capture paths).
- `lib/queue/orchestrate.sh` `_wave_run`'s reap loop happy-path branch (:~1290): on a shipped
  sub-goal, `[ -n "$donefile" ] && "$TMUX_CMD" kill-window -t "$mux:$id"` (ID-098) , mirrors
  `_pane_spawn`'s existing pre-clean-on-retry stance, and `_wave_abort`'s existing in-flight-kill
  stance, closing the one remaining gap (a clean landed pane was never killed).
- `tests/test-orchestrate-hardening.sh` (new): 9 assertions across the three items, including the
  ID-095 age-prune negative control, the ID-095 real-captured-stream redaction proof, the ID-096
  no-dispatch negative control, and the ID-098 kill-window proof (reusing the
  `tests/test-multiplexer.sh` tmux-mock pattern).

## Scope edges honored

- Stream FORMAT untouched (redaction rewrites content in place, never the jsonl structure).
- Model allowlist MEMBERSHIP untouched (opus/sonnet/haiku, matching `route-suggest.sh`'s
  `tier_of()`); only the pre-flight check is new.
- Tmux control-plane attach/capture/send-keys logic untouched; only one `kill-window` call added
  to the happy path.
- `--dry-run` stays non-mutating: `_prune_streams` is explicitly skipped under `dry=1`.

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| ID-095a age-cap NC | `tests/test-orchestrate-hardening.sh` §1 | over-age files pruned, fresh file survives | PASS x2 |
| ID-095b redaction NC | `tests/test-orchestrate-hardening.sh` §2 | `sk-TESTFAKE...` absent, `[REDACTED]` present in stored stream | PASS |
| ID-096 pre-flight NC | `tests/test-orchestrate-hardening.sh` §3 | mock claude never invoked; clear stderr message; box unflipped | PASS x3 |
| ID-098 kill-window | `tests/test-orchestrate-hardening.sh` §4 | `kill-window -t orch-id098:SG-01` recorded after a clean land | PASS x3 |
| suite: hardening (new) | `bash tests/test-orchestrate-hardening.sh` | all green | 9/9 passed |
| suite: orchestrate | `bash tests/test-orchestrate.sh` | all green | ALL PASS |
| suite: model-routing | `bash tests/test-model-routing.sh` | all green | 6/6 passed |
| suite: multiplexer | `bash tests/test-multiplexer.sh` | all green | ALL PASS |
| suite: wavefront | `bash tests/test-orchestrate-wavefront.sh` | all green | ALL PASS |
| syntax (macOS bash 3.2) | `/bin/bash -n lib/queue/orchestrate.sh` | clean | clean |

## Run detail (captured, macOS /bin/bash 3.2.57)

```
$ /bin/bash -n lib/queue/orchestrate.sh && echo SYNTAX_OK
SYNTAX_OK

$ /bin/bash tests/test-orchestrate-hardening.sh
[orchestrate] [retention] pruned 2 stream/session file(s) older than 1d from <TMP>/retention/.orchestrate
PASS ID-095 [NEGATIVE CONTROL]: files older than the retention cap are pruned (both .stream.jsonl and .session.log)
PASS ID-095: a fresh (within-retention) file is left alone by the sweep
PASS ID-095 [NEGATIVE CONTROL]: a secret-shaped line is redacted in the stored stream (raw token absent, [REDACTED] present)
PASS ID-096 [NEGATIVE CONTROL]: an off-allowlist Model: tier never reaches dispatch (mock claude was NOT invoked)
PASS ID-096: a clear pre-flight rejection message names the bad tier
PASS ID-096: SG-01's box stays unchecked (no false-complete on a rejected tier)
PASS ID-098 setup: wave landed SG-01 (box flipped, rc 0)
PASS ID-098 setup: tmux new-window spawned SG-01's pane
PASS ID-098 [Done=]: a cleanly-landed (shipped) sub-goal's window is killed on the happy path (no orphaned pane)

=== 9/9 passed, 0 failed ===

$ /bin/bash tests/test-orchestrate.sh
----
ALL PASS

$ /bin/bash tests/test-model-routing.sh
=== 6/6 passed, 0 failed ===

$ /bin/bash tests/test-multiplexer.sh
----
ALL PASS

$ /bin/bash tests/test-orchestrate-wavefront.sh
----
ALL PASS
```

## Reproduce

```bash
cd dwarves-kit/.claude/worktrees/orchfin-06   # or wherever this branch is checked out
/bin/bash -n lib/queue/orchestrate.sh
/bin/bash tests/test-orchestrate-hardening.sh
/bin/bash tests/test-orchestrate.sh
/bin/bash tests/test-model-routing.sh
/bin/bash tests/test-multiplexer.sh
/bin/bash tests/test-orchestrate-wavefront.sh
```

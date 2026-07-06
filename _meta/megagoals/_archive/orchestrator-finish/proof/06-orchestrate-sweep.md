# Proof of done: orchfin-06-orchestrate-sweep (ID-095 + ID-096 + ID-098)

## Acceptance criteria

| # | Criterion | Item | Met | Evidence |
|---|---|---|---|---|
| 1 | `.orchestrate/*.stream.jsonl`/`*.session.log` older than a retention cap are pruned; a fresh file survives (NEGATIVE CONTROL) | ID-095 | yes | Run-table: 2 backdated files (year 2000) pruned, 1 fresh file survives `_prune_streams` |
| 2 | A secret-shaped line in a REAL captured stream is redacted before the file is handed back | ID-095 | yes | Real serial dispatch, mock claude prints `sk-TESTFAKE...`, stored `.stream.jsonl` shows `[REDACTED]`, raw token absent |
| 3 | An off-allowlist `Model:` tier is rejected pre-flight (single-token AND multi-word); no dispatch happens | ID-096 | yes | Mock claude invocation log stays empty; clear stderr rejection; box stays unflipped; multi-word `opus sonnet` also rejected (substring-membership bug fixed by TIER-4 dissent) |
| 4 | A cleanly-landed wave sub-goal's tmux window is killed on the happy path | ID-098 | yes | `kill-window -t <session>:SG-01` recorded in the tmux-mock call log after a clean land |
| 5 | Green under macOS bash 3.2 (CI) | all | yes | New + existing suites all run under `/bin/bash` (3.2.57) |
| 6 | No regression to the existing serial/wave/mux/model-routing suites | all | yes | `test-orchestrate.sh`, `test-model-routing.sh`, `test-multiplexer.sh`, `test-orchestrate-wavefront.sh` all green |

## Implementation

`lib/queue/orchestrate.sh`:
- **ID-096** (`_route()`, :478-524): added `_ROUTE_MODEL_ALLOWLIST="opus sonnet haiku"` and a
  case-insensitive **exact-token enumeration** membership check (iterate the allowlist, compare
  `==`). NOT a `case " $list " in *" $v "*` substring test: that idiom is a membership bug (the
  TIER-4 dissent on PR #209 caught it) because two adjacent allowed words joined by one space are a
  substring of the joined list, so `Model: opus sonnet` slipped through and was passed verbatim to
  `--model "opus sonnet"` , the exact failure ID-096 exists to stop. Same class the `PANE_VIEWER`
  pre-flight already flags as a security P2 and fixes the same exact-token way. An off-allowlist
  `Model:` value (single-token OR multi-word) prints a clear rejection to
  stderr and returns 64 (SPEC-106's own "bad input" exit code, matching the sibling
  `WAVE_CAP`/`PANE_VIEWER` pre-flight rejections in `cmd_run`). All three call sites (`_wave_run`
  spawn loop, `cmd_run` serial dispatch, the `--dry-run` preview) were changed from
  `read ... < <(_route ...)` (which reflects `read`'s own exit status, not `_route`'s) to
  `out=$(_route ...); rc=$?` (a plain command-substitution assignment DOES reflect the command's
  exit code) so the caller can act on the rejection. Serial + wave both treat a rejection like a
  worktree-setup failure / `gate` sub-goal: no session spawns, a `blocked` event is emitted, the
  loop halts (serial) or drains siblings (wave) , never a silent skip and never a false-complete.
- **ID-095** (new section "Stream retention + redaction", :698-745): `STREAM_RETENTION_DAYS`
  (default 14), `_redact_secrets_file()` (write-temp-then-`mv`; `sed -E` over common API-key/token
  shapes -> `[REDACTED]`; never `sed -i`, whose `-i` args differ between GNU/BSD), `_prune_streams()`
  (portable `find -mtime +N`, no GNU-only flags). Wired: `_prune_streams` runs at the start of
  `cmd_next` and at the start of a real (non-`--dry-run`) `cmd_run`; `_redact_secrets_file` runs on
  every captured slog in both `_run_session_watchdog` (SG-11 capture path) and `_run_one_session`
  (stream-json + plain-with-capture paths) right before the file is surfaced/returned.
- **ID-098** (`_wave_run`'s reap loop happy-path branch): `[ -n "$donefile" ] && "$TMUX_CMD"
  kill-window -t "$mux:$id"` right after the `shipped` event , mirrors `_pane_spawn`'s existing
  pre-clean-on-retry stance and `_wave_abort`'s existing in-flight-kill stance; closes the one
  remaining gap a spec-validate finding had already flagged in `_pane_spawn`'s own header comment
  ("nothing kills a completed pane's window on the normal path").
- `tests/test-orchestrate-hardening.sh` (new, 12 assertions): reuses this repo's existing mock
  patterns (`tests/test-model-routing.sh`'s route-log claude mock, `tests/test-multiplexer.sh`'s
  tmux mock) rather than inventing new harness shapes. Includes the ID-096 multi-word substring-bug
  negative control added by the TIER-4 dissent.

## Scope confirmation (per contract)

- **In, done:** stream-writer retention (`.orchestrate/*.stream.jsonl`), `_route`'s `Model:`
  allowlist, the happy-path tmux cleanup , all inside `lib/queue/orchestrate.sh`.
- **Out, untouched:** the stream FORMAT (jsonl structure unchanged; redaction rewrites content in
  place only), the model allowlist's MEMBERSHIP (opus/sonnet/haiku, unchanged from
  `route-suggest.sh`'s existing `tier_of()` normalization), the tmux control plane's
  attach/capture/send-keys logic (only one new `kill-window` call).
- **Not done (pinned, intentionally):** no retention added to any directory other than
  `.orchestrate`; no general logging refactor; the three items were NOT split into separate PRs
  (the whole point of this sub-goal is the batch).

## Run detail (captured, macOS `/bin/bash` 3.2.57)

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
PASS ID-096 [NEGATIVE CONTROL, multi-word]: 'Model: opus sonnet' is REJECTED pre-flight (substring-membership bug fixed; mock claude NOT invoked)
PASS ID-096 [multi-word]: clear pre-flight rejection message for the multi-word value
PASS ID-096 [multi-word]: SG-01's box stays unchecked (no false-complete)
PASS ID-098 setup: wave landed SG-01 (box flipped, rc 0)
PASS ID-098 setup: tmux new-window spawned SG-01's pane
PASS ID-098 [Done=]: a cleanly-landed (shipped) sub-goal's window is killed on the happy path (no orphaned pane)

=== 12/12 passed, 0 failed ===

$ /bin/bash tests/test-orchestrate.sh   # unchanged suite
----
ALL PASS

$ /bin/bash tests/test-model-routing.sh   # SPEC-116's suite (serial + wave, 3 tiers + inherit NC)
=== 6/6 passed, 0 failed ===

$ /bin/bash tests/test-multiplexer.sh   # SPEC-119's suite (mux-on/off + injection NC)
----
ALL PASS

$ /bin/bash tests/test-orchestrate-wavefront.sh   # the full wave-scheduling suite
----
ALL PASS
```

## Regression sweep note (pre-existing flake, not caused by this diff)

Same host-load-sensitive `wave_run g`/`wave_run h2` FIFO-barrier flakes documented by sub-goal 05's
own proof (`03-wave-tokens.md`, `05-conductor-rid-check.md`): under concurrent test-suite load on
this host, the mock-barrier timing tests in `tests/test-orchestrate-wavefront.sh` occasionally
report a spurious FAIL. Confirmed via `git stash` on this exact branch: the SAME flake reproduces
against unmodified `origin/master`, independent of this sub-goal's diff. A clean, uncontended run
(the run captured above) is consistently `ALL PASS`.

## Reproduce

```bash
cd dwarves-kit
/bin/bash -n lib/queue/orchestrate.sh
/bin/bash tests/test-orchestrate-hardening.sh
/bin/bash tests/test-orchestrate.sh
/bin/bash tests/test-model-routing.sh
/bin/bash tests/test-multiplexer.sh
/bin/bash tests/test-orchestrate-wavefront.sh
```

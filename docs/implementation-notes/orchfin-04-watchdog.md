# Implementation notes: orchfin-04-watchdog (ID-097)

Delta from the sub-goal contract only; see
`_meta/megagoals/orchestrator-finish/goals/04-watchdog-tokens.md` for the full contract and
`docs/verification/orchfin-04-watchdog.md` for the proof.

## 2026-07-05 `$slog`'s format changes under capture, reusing the existing stream-json convention

**Context:** the token-extraction pipeline (`handoff_gen.py sum-usage`) hard-requires
`--output-format stream-json` JSONL input (assistant `usage` blocks per line). The watchdog path's
`$slog` was always plain `claude -p` text, which carries no per-turn usage data to extract.

**Decision:** `_run_session_watchdog` gains a `capture` flag. When capture is requested (mirroring
`_run_one_session`'s own `stream=1 || DETERMINISTIC_HANDOFF=1 || CAPTURE_TOKENS=1` gate), it writes
`$logdir/${id}.stream.jsonl` via `--output-format stream-json --verbose` instead of
`$logdir/${id}.session.log` via plain `-p`. When capture is NOT requested (the default posture,
and every pre-fix invocation), behavior is untouched.

**Why:** the sub-goal's scope note says "Not: reworking `$slog`'s format", but satisfying the
Outcome ("STILL captures the worker's tokens to `$slog`") is impossible without producing SOME
usage-bearing format, since plain text carries no usage data. Read narrowly as "don't invent a
NEW/third extraction convention", the fix stays inside that constraint: it reuses the EXACT
filename (`${id}.stream.jsonl`) and format (`--output-format stream-json --verbose`) the
non-watchdog capture path (`_run_one_session`'s elif branch) and the wave reap loop's recompute
(03/ID-094) already use. No new schema, no new file, no new ledger convention. Precedent for a raw
jsonl surface reaching a human under capture already exists in this file (`--stream`'s `tee` to the
operator's terminal).

**Alternatives considered:** keep `.session.log` plain-text and separately re-run claude a second
time in stream-json mode to extract tokens (rejected: doubles the actual LLM invocation, unaffordable
and semantically wrong -- it would be a second, different session); post-process the plain-text log
with a bespoke usage-line scraper (rejected: `claude -p` plain text has no reliable/documented usage
line to scrape; would be inventing a NEW, fragile extraction convention, which is the thing the
scope note is actually guarding against).

**Impact:** default (no-capture) watchdog runs are byte-identical to pre-fix: same filename, same
format, same final `cat`. Only the capture-requested case changes, and only to the extent needed to
make token extraction possible at all. Confirmed via `tests/test-orchestrate.sh`'s pre-existing
watchdog scenarios (12a stall-warn, 12b dead-session, 12d default-off) all still PASS unmodified.

## 2026-07-05 Result threaded back via a new global (`_WD_SLOG`), mirroring `_ROS_SLOG`

**Context:** `_run_session_watchdog` runs synchronously in the CALLER's shell (unlike the wave
path's forked-subshell `_run_one_session`, per 03's note), so a global set inside it IS visible to
`_run_one_session` right after the call returns.

**Decision:** added `_WD_SLOG` (parallel to the existing `_ROS_SLOG` pattern) rather than having
`_run_session_watchdog` echo the path to stdout (which would collide with `cat "$slog"` already
writing to stdout at the end of that same function) or accepting an output-var name as a parameter
(bash 3.2 `local -n` nameref support is absent).

**Why:** cheapest correct option given bash 3.2 has no clean function return-by-reference and stdout
is already spoken for by the existing `cat "$slog"` line.

**Impact:** zero changes needed to the serial path's `_record_tokens "$dir" "$id" "$slog"` call site
or the wave reap loop's recomputed-path call site (both already existed from 03/ID-094) -- once
`_run_one_session`'s watchdog branch sets `slog="$_WD_SLOG"` before its `_ROS_SLOG="$slog"` line,
every downstream consumer picks it up unchanged.

## No other deviations

The stall DETECTION loop (`while kill -0 ...`, the `stalled` event, the WARN-once logic) and
`WATCHDOG_STALL_SECS` are byte-for-byte unchanged, per scope.

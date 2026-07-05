# Implementation notes: orchfin-03-wave-tokens (ID-094)

Delta from the sub-goal contract only; see `_meta/megagoals/orchestrator-finish/goals/03-wave-tokens.md`
for the full contract and `docs/verification/orchfin-03-wave-tokens.md` for the proof.

## 2026-07-06 Shared extraction helper instead of duplicating the block

**Context:** the serial per-sub-goal loop already extracts TOKENS via a ~15-line inline block
(`_rid_for` + `sum-usage` + `gate-ledger.sh tokens`). The wave reap loop needed the same logic.

**Decision:** factored the block into a new `_record_tokens <dir> <id> <slog>` helper (placed next
to `_rid_for` in `lib/queue/orchestrate.sh`), and made the serial call site call it too (so both
paths share ONE extraction, never two copies that can drift).

**Why:** the sub-goal's contract says "writing to the same ledger stream the serial path uses" ,
sharing the function is the strongest way to guarantee that, and cheaper to review than two
near-identical blocks.

**Alternatives considered:** duplicate the block inline in the wave reap loop (rejected: doubles the
maintenance surface for zero benefit); call `_run_one_session`'s token-extraction inline instead of
factoring out (not applicable, extraction wasn't in `_run_one_session` to begin with).

**Impact:** serial path is a behavior-preserving refactor (same extraction, same gate, same ledger
write); confirmed via `tests/test-token-capture.sh` unchanged and still 9/9 PASS.

## 2026-07-06 Wave path recomputes the slog path instead of threading it through

**Context:** `_run_one_session`'s stream-json capture path sets a global `_ROS_SLOG` so the SERIAL
caller (same shell) can read `$slog` after the call returns. The wave path backgrounds
`_run_one_session` inside a forked subshell (`( cd "$wt" ... ) &`), so that global never crosses
back to the reap loop, exactly as the pre-existing comment above the spawn says ("the `_ROS_SLOG`
global is unused on the wave path ... losing it in the subshell is fine").

**Decision:** rather than threading the path back through a donefile or a new IPC channel, the reap
loop RECOMPUTES the deterministic path itself: `$megadir/.orchestrate/<id>.stream.jsonl` (the exact
same expression `_run_one_session` uses internally, since `dir` there is `$megadir` on the wave
call). Gated on `CAPTURE_TOKENS=1 || DETERMINISTIC_HANDOFF=1` (mirrors `_run_one_session`'s own
capture gate for that hardcoded `stream=0` call) purely to skip a pointless `stat` on the default
(no-capture) path; `_record_tokens` itself is a safe no-op on an absent/empty file regardless.

**Why:** avoids inventing new plumbing (no new field on the `_WAVE_*` index-aligned arrays, no
donefile changes, no signature change to `_run_one_session`) for a path that is already knowable by
formula. Smallest-blast-radius per the "minimum infra first" default.

**Alternatives considered:** add a `_WAVE_SLOGS` index-aligned array populated at spawn time
(rejected: more state to keep in sync across the plain-background AND the tmux-mux branches, for a
value derivable by formula); write the slog path to the donefile alongside the exit code (rejected:
the plain-background branch has no donefile at all, this would force one).

**Known limitation (documented, not fixed):** the MULTIPLEXER=1 (tmux pane) branch respawns via a
NEW `orchestrate.sh _pane-exec` process inside a tmux window; whether `CAPTURE_TOKENS`/
`DETERMINISTIC_HANDOFF` reach that process depends on tmux's environment inheritance at the time the
per-megagoal tmux session was created, which is a pre-existing MULTIPLEXER-path characteristic, not
something this sub-goal introduces or was asked to fix (out of scope: "the wave reap/collect path",
not the mux env-propagation semantics). The reap loop's token-extraction call itself is IDENTICAL
for muxed and non-muxed indices (same success branch, same recomputed path); a muxed run that DOES
inherit `CAPTURE_TOKENS` behaves identically to the tested non-mux path.

## 2026-07-06 Negative control via a test-only env-gated skip, not a git-history diff

**Context:** the sub-goal's Proof needs a negative control that shows the PRE-FIX code produced ZERO
wave token lines, to demonstrate the fix's causal effect (not just its post-fix presence).

**Decision:** added `NC_SKIP_WAVE_TOKENS` as a test-only escape hatch directly in the reap loop's
extraction guard (`&& [ "${NC_SKIP_WAVE_TOKENS:-0}" != 1 ]`), rather than checking out the pre-fix
commit in the test.

**Why:** a git-history-based negative control (checkout parent commit, run test against it) would
need to invoke a DIFFERENT copy of `orchestrate.sh` than the one sourced at the top of the test file,
and dodges bash-3.2/5 dual-version testing in a way that's easy to get subtly wrong (stale sourced
functions, mismatched helper library versions). An in-code, env-gated skip on the exact new call
site is a direct, auditable causal proof: same code, same mock, same child.jsonl, one flag flipped.

**Impact:** `NC_SKIP_WAVE_TOKENS` is unset (default 0) on every real invocation; it is not
documented as an operator-facing flag anywhere outside this note and the inline comment.

## No other deviations

Everything else in `tests/test-wave-token-capture.sh` and the `_wave_gate`/CAPTURE_TOKENS header
comment touch-ups matches the sub-goal contract verbatim.

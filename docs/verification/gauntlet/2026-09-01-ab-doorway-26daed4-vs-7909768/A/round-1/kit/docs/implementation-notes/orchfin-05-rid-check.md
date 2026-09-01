# Implementation notes: orchfin-05-rid-check (ID-099)

Delta from the sub-goal contract only; see
`_meta/megagoals/orchestrator-finish/goals/05-conductor-rid-check.md` for the full contract and
`docs/verification/orchfin-05-rid-check.md` for the proof.

## 2026-07-06 The fix is a single added call, not new logic

**Context:** the sub-goal's rescoped Outcome already did the diagnosis: the serial path
(`cmd_run`) calls `_emit_start` right after `_emit_event ... executing`; `_wave_run`'s spawn loop
calls only the `executing` event and never `_emit_start`. Confirmed by grep: `_emit_start` has
exactly one call site pre-fix (`cmd_run`, line ~1811).

**Decision:** add `_emit_start "$megadir" "$id"` immediately after the wave loop's existing
`_emit_event ... executing` line, mirroring the serial call site's position relative to its own
`executing` event exactly. No changes to `_emit_start`, `_rid_for`, or the serial path.

**Why:** the smallest-blast-radius fix that satisfies the Outcome ("every dispatch, serial AND
wave, emits a START/rid") is to call the function that already exists at the one spot missing it,
not to write a second implementation. This also means the serial path's advisory
missing-`**Branch:**` WARN behavior is inherited for free on the wave path, satisfying the sub-goal's
"Not: turning the advisory warn into a hard abort" pin without any extra code.

**Alternatives considered:** duplicating a wave-specific START-emission block inline (rejected: would
diverge from serial over time, exactly the drift risk `_rid_for`'s own docstring warns against for
`_record_tokens`, ID-094's precedent in the same file).

## 2026-07-06 Test-only escape hatch to prove causality, not just presence

**Context:** the contract's Proof line asks for "a negative control (a dispatch with no derivable rid
is caught, not silently untracked)" but also implies the WAVE_TOKEN-style causal proof pattern
established by ID-094 (`NC_SKIP_WAVE_TOKENS`): showing the SAME scenario without the fix produces
zero records, not just showing the fixed code produces records.

**Decision:** added `NC_SKIP_WAVE_START=1`, gating the new `_emit_start` call with
`[ "${NC_SKIP_WAVE_START:-0}" = 1 ] || _emit_start ...`. Unset/0 in every real invocation.

**Why:** matches the exact pattern and naming convention of ID-094's `NC_SKIP_WAVE_TOKENS` in the
same file, so a reader who already understands one understands the other. Test-only; never
documented as an operator flag, per the ID-094 precedent's own comment style.

## 2026-07-06 Third assertion added beyond the letter of the contract

**Context:** the contract's "How to close the loop" lists two assertions: (1) two START/rid records
land in a wave, (2) a no-derivable-rid dispatch is loudly flagged.

**Decision:** the new test (`tests/test-wave-rid-check.sh`) adds a third check in the
no-derivable-rid case: the wave dispatch still COMPLETES (its box flips, exit code 0), not just that
a warning is printed.

**Why:** "loudly flagged, not silently untracked" is ambiguous about whether the dispatch should
also still run. The sub-goal's own scope explicitly pins `_emit_start`'s advisory (warn+skip,
never abort) as unchanged, so proving the wave doesn't halt on a missing rid is the same claim as
"stays advisory", just made explicit and test-verified rather than left implicit. Reversible,
additive, no scope change; flagged here rather than silently added.

## Regression evidence: pre-existing wave-scheduling flake, not caused by this change

**Context:** `tests/test-orchestrate-wavefront.sh` intermittently fails `wave_run g` (and
occasionally `wave_run h2`) under host load; documented already in
`docs/verification/orchfin-03-wave-tokens.md` (ID-094) as a pre-existing FIFO-barrier timing flake.

**Decision:** confirmed unrelated by `git stash` on this exact branch/host (reverts this sub-goal's
diff back to `origin/master` content) and re-running the same suite: identical `wave_run g` failure
signature appears with zero diff applied. No fix attempted here; out of ID-099's scope (the
sub-goal's `## Scope edges` does not include the wave-scheduling reap loop's concurrency timing).

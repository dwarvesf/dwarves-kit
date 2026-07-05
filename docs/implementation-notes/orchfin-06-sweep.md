# Implementation notes: orchfin-06-sweep (ID-095/096/098)

Delta from the sub-goal contract (`_meta/megagoals/orchestrator-finish/goals/06-orchestrate-sweep.md`)
only; see it for the full contract.

## 2026-07-06 03:40 bash-3.2 same-`local`-statement gotcha caught by self-test

**Context:** `_prune_streams()` was first written as one `local` statement:
`local dir="$1" logdir="$dir/.orchestrate" n`.

**Decision:** split into two statements: `local dir="$1" n` then `local logdir="$dir/.orchestrate"`.

**Why:** under macOS's stock `/bin/bash` 3.2.57, a later name in the SAME `local` statement
cannot see an earlier name's value yet (`local a=1 b=$a` leaves `$a` unbound at the point `b` is
evaluated) , confirmed with a 2-line repro (`set -u; f(){ local dir="$1" logdir="$dir/.orchestrate"; ...}; f /tmp/x`
threw `dir: unbound variable`). Every OTHER new `local` line in this diff was already
dependency-free (checked via `git diff | grep local` after the fix), so this was the only instance.

**Impact:** caught by `tests/test-orchestrate-hardening.sh`'s first assertion before this branch
was ever pushed; no behavior shipped with the bug.

## 2026-07-06 03:55 redaction placement: file, not the live `--stream` tee

**Context:** ID-095 asks to close the "secret-bearing transcript sits on disk" risk.

**Decision:** `_redact_secrets_file()` runs on the captured slog file AFTER the write completes
(both `_run_session_watchdog` and `_run_one_session`), not as a filter on the live `--stream`
terminal tee.

**Why:** the `--stream` opt-in path already writes to the terminal via `tee` before the file write
finishes; filtering that live stream would need a process-substitution rewrite of the stream
FORMAT plumbing (`tee >(sed ...) "$slog"` or similar), which the sub-goal's own scope edges rule
out ("Out: the stream FORMAT"). Redacting the FILE closes the AT-REST exposure, which is the
specific risk ID-095 names ("SIT ON DISK"); the live-tee case is a strictly narrower, opt-in,
interactive-operator-only surface, not the default unattended path.

**Alternatives considered:** a `tee`-with-process-substitution live filter, rejected as
out-of-scope per the note above; leaving `--stream` entirely unaddressed was accepted as the
smaller, reversible gap (still narrower than the at-rest fix, and not the sub-goal's Done=
criterion).

## 2026-07-06 04:10 `_prune_streams` skipped under `--dry-run`

**Context:** the sub-goal contract calls for an "age/count sweep at next/close"; the natural
insertion point in `cmd_run` sits before the `--dry-run` preview branch.

**Decision:** guard the call with `[ "$dry" = 1 ] || _prune_streams "$dir"`.

**Why:** a `--dry-run` preview must stay non-mutating (read-only), matching every other guard in
`cmd_run`'s dry-run branch (it only prints, never writes). Deleting files during what an operator
expects to be a side-effect-free preview would be a surprise regression, not a fix.

## 2026-07-06 04:20 gate-ledger recording: lane classifier said `full`, contract expected `tiny`/`small`

**Context:** the sub-goal contract's own gate-recording line assumed `lane-classify.sh` would
return `tiny`/`small` for this task description. `bash lib/classify/lane-classify.sh classify "..."`
returned `full` instead (this sweep touches `lib/`, which the classifier weighs toward `full`).

**Decision:** recorded gates matching the WORK actually done for a 3-item papercut sweep, not the
full 14-phase full-lane ceremony: `grill`/`think`/`design`/`spec` recorded as `skipped` with named
reasons (`density-low`, "no architecture change", "contract IS the spec"), `test-plan`/`build`/
`review` recorded as `ran` with evidence.

**Why:** the contract's own line ("Kit-adopted repo? Record the gates ... still record build+review
via gate-ledger.sh") already anticipated a lighter record for a tiny/small lane; performing the full
ceremony on three independently-tiny, fully-pinned fixes would be process theater the contract
itself argues against. Logged as a deviation in the goal file's `## Notes` rather than silently
diverging.

## 2026-07-06 04:45 PR base: `master`, not the goal file's `fix/orchfin-05-rid-check`

**Context:** the goal file's `**PR base:**` header still names sub-goal 05's branch.

**Decision:** opened the PR against `master` per the dispatch prompt, which stated 05 is already
merged and the stack has collapsed.

**Why:** the dispatch prompt is the more current authority at execution time (a goal file written
before the mega started cannot know the real merge order). Reversible: retargeting a PR's base on
GitHub is a one-click op if this assumption is wrong.

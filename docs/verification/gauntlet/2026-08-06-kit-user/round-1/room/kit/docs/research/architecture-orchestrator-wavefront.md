# Mega-goal orchestrator architecture (for wavefront scheduling)

Scope: lib/queue/orchestrate.sh (serial loop, board/events) + lib/gate/dispatch-gate.sh
(disjointness gate). For a spec author adding concurrent wavefront execution.

## 1. Serial run loop (`cmd_run`, orchestrate.sh:335-489)
`while :; do` (L376) calls `_next "$roadmap"` (L378 -> `_subgoals|awk '$3==0{print;exit}'`
L101): first unchecked `- [ ] SG-NN` line in FILE ORDER, no dep-aware selection.
`_sg_deps_blocked` (L133) is used ONLY by the board (L168), never by the picker. `gate`
policy halts the loop (L382-387) instead of dispatching. Dispatch is synchronous: build
prompt to a temp file (`_build_prompt`, L412-413), then ONE of watchdog / stream-json /
plain `"$CLAUDE_CMD" -p ... < "$pfile"` (L417-439); `cmd_run` blocks on `rc=$?` before
looping again — exactly one in-flight `claude -p` at a time. This blocking is what
wavefront scheduling must break.

**"done" signal** (L448-455, grounded completion, no self-claim): after exit 0, re-`grep`
the ROADMAP for that id's checked bit — does NOT trust session stdout/exit code alone:
```bash
checked=$(_subgoals "$roadmap" | awk -F'\t' -v i="$id" '$1==i {print $3}')
[ "$checked" != 1 ] && { _emit_event ... blocked "box not flipped (no self-claim)"; return 1; }
```
A wavefront scheduler must replicate this re-read-from-disk per lane.

## 2. `depends SG-NN` parsing (board-view only today)
`_sg_deps_blocked` (L133-140): `grep -oE 'depends[^,]*'` on the raw line, then
`grep -oE 'SG-[0-9]+'` inside that match; a dep blocks iff `_subgoals` shows its checked
bit 0. Expected line shape (from `_subgoals` L86-98 / `_sg_title` L127-129):
`- [ ] SG-NN <title> , auto|gate , depends SG-01 SG-02` (comma-separated fields, `depends`
its own field). Non-`SG-` deps (e.g. `#81`) ignored ("out of board scope"). Consumed ONLY
in `_derive_board` L168 -> `parked [blocked: needs SG-xx]` vs `queued [ready]` in
BOARD.md. `_next`/`cmd_run` never call it — a wavefront scheduler is the first consumer
that needs it authoritative for dispatch eligibility, not just board prose.

## 3. Completion / event log (SG-10)
- Box-flip: written by the sub-goal SESSION editing ROADMAP.md; driver only reads it
  back (L449). No self-claim (comment L27-29).
- Event log: append-only TSV at `.orchestrate/events.log` (`_events_file` L108).
  `_emit_event dir id status [note]` (L110-114): one `printf ... >> "$ef"` per call, no
  flock anywhere. Statuses seen: `executing/stalled/blocked/shipped/handoff`.
  `_event_status` (L117-121) replays via `awk` "last event wins" (event-sourced, crash
  corrupts at most one line, comment L104-107).
- **No locking today.** Concurrent writers to events.log or ROADMAP.md rely only on
  `printf >>`'s incidental single-`write()` atomicity, not a designed guarantee — the gap
  a wavefront design must close (per-file lock, or per-lane log reconciled by the parent).
- `BOARD.md` (`_derive_board` L146-175) is fully regenerated each call (never patched),
  safe to call from multiple lanes.

## 4. `WATCHDOG_STALL_SECS` concurrency primitive (`_run_session_watchdog`, L312-333)
Only existing "background a session" code: `{ claude -p ... ; } &`, `spid=$!`, poll
`kill -0 "$spid"` (liveness) + `_mtime` on the log (stall detect) every
`WATCHDOG_POLL_SECS`, emit one `stalled` event + WARN (never kills), `wait "$spid"` for
rc. Backgrounds ONE session per loop iteration today. A wavefront scheduler generalizes
this exact `& / spid=$! / kill -0 / wait` shape to an array of pids, one per
parallel-eligible lane, polled per tick.

## 5. dispatch-gate.sh public interface
Sourceable or `bash lib/gate/dispatch-gate.sh <subcmd> ...` (L209-211 guard).

| Function | Signature | Returns |
|---|---|---|
| `gate_touches` | `touches <spec>` | normalized dir-prefixes from `## Touches`, 1/line |
| `gate_disjoint` | `disjoint <specA> <specB>` | 0 disjoint / 1 overlap / 2 undeclared (REJECT) |
| `gate_plan` | `plan <spec...>` | `PARALLEL <spec>` / `WAIT <spec> after <spec>` lines |
| `gate_drift` | `drift <base> <branch> <spec>` | 0 clean / 1 drift |

`gate_disjoint` (L84-109): undeclared `## Touches` -> exit 2; any non-`dir/**` glob
(marked `?` by `gate_normalize_glob`) forces conservative overlap; else pairwise
`prefix_overlap` (exact or ancestor-dir). `gate_plan` (L115-135) is a greedy admission
loop, already wavefront-ish: admits a spec if disjoint from every already-admitted spec,
else emits a wait-edge on the first conflict — but over specs' `## Touches` globs, not
ROADMAP `depends` edges, and only PRINTS a plan (no dispatch).

## 6. Conventions to match
- `set -uo pipefail` (orchestrate.sh L33, no `-e`, many `||` guards rely on continuing)
  vs `set -euo pipefail` (dispatch-gate.sh L26) — match whichever file you extend.
- `_`-prefixed helpers in orchestrate.sh vs `gate_`/`is_`/`handsoff_` in dispatch-gate.sh;
  each file its own namespace.
- Dense why-comment above every non-trivial function, citing the driving spec/decision
  (SPEC-087, ADR-0027, DEC-008, ID-029) — match this density.
- Config: `VAR="${VAR:-default}"` at top of file, no config file; paths resolved via
  `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` (`ORCH_DIR`/`GATE_DIR`/`KIT_ROOT`).
- Errors: no custom types; `echo ... >&2; return 64` (usage) or `[guardrail]`/`WARN`/
  `REJECT` stderr prefixes. Advisory failures WARN+continue; grounded-completion / gate /
  nonzero-session failures `return 1` and halt — the loop never self-retries.

## Prior-art flag (read before designing)
`docs/research/2026-05-22-concurrent-goal-dispatch.md` (`status: active`) explicitly
weighed and REJECTED an in-kit DAG/wave scheduler: "the moment a real DAG (topological
scheduling, wave execution) is required, you have crossed back into runtime territory
... that need is the tripwire to hand off to gsd-2, not to build a scheduler." The
decided model was a flat parallel-safe set + pairwise gate + wait-queue (what
`gate_plan` implements), not a general wavefront/DAG executor. Reconcile the new
wavefront ask against this decision explicitly rather than silently re-opening it.

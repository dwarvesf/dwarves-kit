# Spec: multiplexer panes (opt-in wavefront visibility)
Generated: 2026-07-03
Status: DRAFT

## Problem

`lib/queue/orchestrate.sh`'s wavefront path (`_wave_run`, ADR-0030) backgrounds each admitted wave
sub-goal's `claude -p` session as a plain bash job (`( cd "$wt" && _run_one_session ... ) &`).
When `WAVE_CAP>1` runs two or more sessions concurrently, their combined stdout/stderr interleave
on whatever fd the conductor inherited: the operator cannot watch one session in isolation, and
has no way to intervene in a specific in-flight session. ADR-0032 section 4 names this gap and
authorizes an opt-in terminal-multiplexer wiring (tmux/cmux: `new-window` to spawn, `capture-pane`
to receive, `send-keys` to control) that gives the operator the "watch + intervene across tabs"
experience, without requiring it for orchestration (pure headless dispatch already works via
Bash + `claude -p`, the delegate pattern).

## Solution

### Approaches considered

1. **Mirror pane** (tail a log file the existing background job already writes into a new tmux
   window). Simplest to build (no re-exec, no new subcommand), but a `tail -f` pane has no
   foreground process attached to send keys to -- `send-keys` would be wired but functionally
   inert, failing the "control / intervene" half of the Proof.
2. **Host the real session in the pane** (`tmux new-window` runs the actual `claude -p` dispatch,
   not a mirror). `capture-pane` reads its real live output; `send-keys` reaches a real attached
   process. Costs a completion-signalling mechanism (see below), since `tmux new-window` returns
   before the pane's command exits, so a bash `wait` cannot reap it.
3. **A cmux-driven pane** (open-fork 2's other option). cmux is the operator's daily-driver GUI
   app, scoped to a `CMUX_WORKSPACE_ID` workspace, with a browser-shaped skill surface
   (`cmux-browser`); it has no general "spawn an arbitrary shell command into a new pane, headless,
   scriptable from bash, mockable in CI" primitive the way tmux's CLI does.

### Chosen approach + why

**Approach 2 (real session hosted in a tmux pane), tmux as the driver (open-fork 2 resolved).**
tmux's CLI (`new-window` / `capture-pane` / `send-keys`) is scriptable, already installed
(minimum-infra), and mockable via a `TMUX_CMD` env seam identical in shape to the existing
`CLAUDE_CMD` seam -- so the on-path is headless-testable in CI with no real tmux server, and the
off-path has a trivial true negative control (a fake `TMUX_CMD` that errors if invoked, run under
the default `MULTIPLEXER=0`, must never fire). cmux is rejected as the driver for exactly the
reason ROADMAP open-fork 2 flags: it is the operator's interactive daily driver, not the
portable/headless-safe default that keeps the off path (and the on path's tests) intact. Mirror
piping (approach 1) is rejected because `send-keys` needs a real foreground process to mean
anything.

### Extensibility & boundaries

- Load-bearing dimension: number of concurrent wave sessions (`WAVE_CAP`). Each gets its own tmux
  window inside one shared per-megagoal tmux session (`_mux_session_name`); adding more wave
  capacity adds more windows, no new machinery.
- A future `PANE_DRIVER=cmux` variant (explicitly out of scope here, see Out of Scope) would be an
  additive branch alongside the tmux one, not a rework -- the spawn/capture/send-keys surface
  (`_pane_spawn` / `_pane_capture` / `_pane_send_keys`) is the seam a second driver would plug into.
- Unit boundaries: `_pane_spawn` (spawn), `_pane_capture` (receive), `_pane_send_keys` (control) are
  three single-purpose wrappers over the three tmux primitives named in the Proof; the `_pane-exec`
  hidden subcommand is the one re-entry point a pane's shell uses to reach `_run_one_session`
  (no duplicated dispatch logic).

### Architecture

```
_wave_run spawn loop, per admitted sub-goal:

  MULTIPLEXER=0 (default)                    MULTIPLEXER=1
  ------------------------                   ----------------------------------------------
  set -m                                     donefile=$(mktemp -u)
  ( cd "$wt" &&                              _pane_spawn megadir id wt pfile route_flags donefile
      _run_one_session ... ) &                 -> tmux new-window -d -t <mux> -n <id> -c "$wt" \
  pid=$!                                           "$ORCH_DIR/orchestrate.sh" _pane-exec \
  set +m                                              megadir id pfile route_flags donefile
  _WAVE_PIDS+=("$pid")                       _WAVE_PIDS+=("")           # no reapable pid
  _WAVE_DONEFILES+=("")                      _WAVE_DONEFILES+=("$donefile")

reap loop, per index:
  donefile empty?  -> kill -0 "$pid" / wait "$pid"        (byte-identical to today)
  donefile set?    -> poll [ -f "$donefile" ], read exit code from it, rm it

_pane-exec megadir id pfile route_flags donefile  (new hidden `main()` subcommand, real process
  entry -- BASH_SOURCE==$0 holds, so this is never reached via `source`):
    _run_one_session "$megadir" "$id" "$pfile" "$route_flags" 0
    echo $? > "$donefile"
```

The pane's window is named `<id>` inside a per-megagoal tmux session (`_mux_session_name`), so
`tmux capture-pane -p -t "<mux>:<id>"` / `tmux send-keys -t "<mux>:<id>" ...` address one wave
session unambiguously.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes: `MULTIPLEXER` (env, default `0`/off), `TMUX_CMD` (env, default `tmux`,
  mirrors `CLAUDE_CMD`'s test-mock seam), `TMUX_SESSION` (env, optional override of the derived
  per-megagoal tmux session name). Consumes the same `megadir`/`id`/`wt`/`pfile`/`route_flags`
  `_wave_run` already builds; adds nothing to the goal-file / ROADMAP contract.
- Outputs / produces: when enabled, one tmux window per spawned wave sub-goal, capturable via
  `tmux capture-pane`; a donefile per pane-spawned sub-goal (removed once reaped). No new
  persistent state (no new ledger, no new daemon); the tmux session itself is the only new
  artifact and it is exactly as long-lived as the operator's terminal multiplexer already is.
- Invariants: with `MULTIPLEXER=0` (or unset), `_wave_run` never calls `$TMUX_CMD` -- zero tmux
  process invocations, verified by a negative control. The reap loop's default (`donefile=""`)
  branch is textually the pre-existing `kill -0`/`wait` code, unedited.

### Data model changes

None.

### API changes

None (bash script; `main()` gains one hidden subcommand `_pane-exec`, not documented in the
`usage:` string -- it is an internal re-entry point, not an operator-facing command).

### Infrastructure changes

None (tmux is already installed per minimum-infra; no new daemon, no new listener, no new
always-on process -- the tmux session exists only while wave panes are open).

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: `_mux_session_name(megadir)`, derives a stable, sanitized tmux session name from
  the megadir path (or `$TMUX_SESSION` override); pure function, unit-testable.
- [ ] TASK-002: `_pane_spawn` / `_pane_capture` / `_pane_send_keys`, thin wrappers over
  `tmux new-window` / `capture-pane` / `send-keys`, using `$TMUX_CMD`; ensure-session-exists
  handled by `_pane_spawn` (`has-session` else `new-session -d`).
- [ ] TASK-003: `_pane-exec` hidden `main()` subcommand, calls `_run_one_session`, writes exit
  code to the donefile.

### Phase 2: Core
- [ ] TASK-004: wire `_pane_spawn` into `_wave_run`'s spawn loop behind `MULTIPLEXER=1`; add the
  index-aligned `_WAVE_DONEFILES` global array (empty-guarded like `_WAVE_PIDS`/`_WAVE_PFILES`).
- [ ] TASK-005: branch the reap loop per-index on `donefile` set/empty; donefile path polls
  `[ -f "$donefile" ]` + reads the exit code instead of `kill -0`/`wait`.
- [ ] TASK-006: `_wave_abort` additionally `tmux kill-window`s any pane-spawned index still
  in-flight (best-effort, `|| true`), so an operator Ctrl-C during a muxed wave doesn't leave a
  live pane running past the abort.

### Phase 3: Polish
- [ ] TASK-007: header docstring update (the `MULTIPLEXER` / `TMUX_CMD` / `TMUX_SESSION` env vars,
  one paragraph, matching the existing `WATCHDOG_STALL_SECS` / `CAPTURE_TOKENS` doc style).
- [ ] TASK-008: `tests/test-multiplexer.sh`, enabled-spawns-pane + capture-pane-visibility +
  off-path-unchanged negative control (see Test plan below); a fake `tmux` fixture script
  (`$TMP/tmux-mock`) that logs invocations and simulates `new-window`/`capture-pane`/`send-keys`
  without a real tmux server.
- [ ] TASK-009: pane-spawn sample + off-path-unchanged diff captured under
  `docs/proof-of-done/SPEC-119-multiplexer-panes.md`.

## After state

- [ ] `MULTIPLEXER=1` + `WAVE_CAP>1`: each admitted wave sub-goal's session is spawned via
  `tmux new-window` into its own pane; `tmux capture-pane` against that pane returns the session's
  live output. (Today: wave sessions share the conductor's own stdout/stderr, uncapturable
  per-session.)
- [ ] `MULTIPLEXER=0` (default, unset): `_wave_run` never invokes `$TMUX_CMD`; the reap loop takes
  the exact pre-existing `kill -0`/`wait` branch. Checkable by
  `bash tests/test-orchestrate-wavefront.sh` (unedited) staying green AND
  `bash tests/test-multiplexer.sh`'s negative control (a `tmux` that errors if called, run with
  `MULTIPLEXER` unset, never fires).
- [ ] `bash tests/test-multiplexer.sh` green.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path (enabled + capture-pane visibility) + the off-path negative control
- [ ] No regressions in existing functionality (`test-orchestrate.sh`, `test-orchestrate-wavefront.sh`,
  `test-tier4-close.sh`, `test-token-capture.sh`, `test-model-routing.sh` all still green, unedited)

## Verification

```bash
bash tests/test-multiplexer.sh              # the new coverage
bash tests/test-orchestrate-wavefront.sh     # regression: wave path unchanged when MULTIPLEXER=0
bash tests/test-orchestrate.sh               # regression: serial delegate path untouched
bash tests/test-tier4-close.sh               # regression: TIER-4 close untouched
bash tests/test-token-capture.sh             # regression: token capture untouched
bash tests/test-meta.sh                      # structural integrity
```

Pass = `test-multiplexer.sh` all green AND every regression suite above still green.

## Edge Cases

1. `MULTIPLEXER=1` but `WAVE_CAP=1` (forces the always-serial loop), or a mega-goal whose
   sub-goals declare no disjoint `## Touches` (so `_wave_gate` admits 0 concurrently and every
   sub-goal runs via the serial fallthrough): no wave ever runs, so `_pane_spawn` is never
   called -- a no-op, not an error.
2. `MULTIPLEXER=1` and the wave has zero admitted sub-goals (nothing ready): `_wave_run`'s existing
   empty-wave short-circuit (`spawned=0`) fires before any pane logic runs -- unchanged.
3. A pane-spawned session crashes before writing its donefile (e.g. `tmux` itself dies): the reap
   loop polls forever unless bounded. Mitigated by the existing wave-level operator abort
   (`_wave_abort` / Ctrl-C); no new timeout is added (out of scope -- would duplicate the SG-11
   watchdog's stall-detection role, which is a separate opt-in already).
4. Two sub-goals share the same `id` across two concurrent wave cycles (shouldn't happen --
   `_wave_gate` never re-admits a checked box) -- the tmux window name collision is the existing
   `_wave_worktree` idempotent-resume invariant's problem to prevent, not a new one this spec
   introduces.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `tmux` binary missing/not on PATH while `MULTIPLEXER=1` | `_pane_spawn`'s `tmux new-window` call fails (nonzero) | `_pane_spawn` returns nonzero; the spawn loop treats it like the existing worktree-setup failure (`blocked` event, `wave_failed=1`, siblings still drain) -- no new failure path, reuses the existing one |
| Pane process dies without writing donefile | reap loop never sees `-f "$donefile"` for that index | operator Ctrl-C (`_wave_abort`) reaps + `tmux kill-window`s it; no automatic timeout (edge case 3) |

## Out of Scope

- A `PANE_DRIVER=cmux` variant (open-fork 2 picks tmux only; a cmux driver is a separate additive
  effort per the implementation notes).
- Wiring the multiplexer into the serial (`cmd_run`, non-wave) delegate path -- ADR-0032 s4 and the
  goal file both scope this to wavefront wave sessions only.
- Any new terminal-control daemon, always-on listener, or DAG/scheduler beyond ADR-0030 wavefront.
- Model routing (SG-01), token-capture stream-to-file (SG-02), the TIER-4 mega-close (SG-03), docs
  wiring (SG-05) -- all separate sub-goals.

## Touches
- lib/queue/orchestrate.sh
- tests/test-multiplexer.sh
- docs/proof-of-done/SPEC-119-multiplexer-panes.md

## Decision Log
- DEC-001: pane driver = tmux, not cmux (open-fork 2). Rationale: scriptable CLI, mockable
  `TMUX_CMD` seam, headless/CI-safe. Alternatives rejected: cmux (GUI daily-driver, no headless
  spawn-arbitrary-command primitive).
- DEC-002: the pane hosts the real `claude -p` dispatch (via a `_pane-exec` re-entry into
  `orchestrate.sh`), not a tailed mirror of a log file. Rationale: `send-keys` needs a real
  attached foreground process; a mirror pane would make `send-keys` wiring inert.
- DEC-003: completion signalled via a donefile (poll `[ -f ]`, read exit code), not a pid `wait`.
  Rationale: `tmux new-window` returns before the pane's command exits, so its `$!` is not the
  pane's actual process; a donefile mirrors the existing watchdog path's poll-a-side-channel idiom.
- DEC-004: multiplexer wiring scoped to `_wave_run` only, not the serial `cmd_run` path. Rationale:
  the serial path already has exactly one in-flight session attached to the conductor's own
  terminal -- nothing to multiplex.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)

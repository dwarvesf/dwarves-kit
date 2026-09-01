# Implementation notes: SPEC-119 multiplexer panes

Delta from the spec only; decisions the spec didn't pin, deviations, tradeoffs.

## 2026-07-03 10:00 Reap mechanism for pane-spawned sessions

**Context:** `_wave_run`'s reap loop polls `kill -0 "$pid"` then `wait "$pid"` to get the exit
code. `tmux new-window` returns as soon as the tmux server acks window creation, so `$!` after
that call is the `tmux` CLI's own (short-lived) pid, not the pane's shell -- a bash `wait` on it
cannot observe the pane's actual lifetime or exit code.

**Decision:** the pane-exec wrapper (`_pane-exec` subcommand) writes its exit code to a donefile
after `_run_one_session` returns. The reap loop polls `[ -f "$donefile" ]` instead of `kill -0`
for any index spawned via the pane path (index-aligned `_WAVE_DONEFILES` array, empty string for
the non-mux path). Mirrors the existing `_mtime`-poll pattern the watchdog path already uses
(orchestrate.sh `_run_session_watchdog`), so it's not a new idiom in the file.

**Why:** no clean way to `wait` on a grandchild in a different process tree spawned by a
detached tmux server; a donefile is the same "poll for a side-channel completion signal"
shape the watchdog path already established.

## 2026-07-03 10:05 Real session runs inside the pane, not a tailed mirror

Considered: mirror the existing background dispatch's output into a `tail -f` pane (simpler:
no new subcommand, no re-exec). Rejected: the goal file's Proof and ADR-0032 s4 both say the
wave session is *spawned into* the pane (`tmux new-window` *to spawn*), and `send-keys` needs a
real foreground process attached to the pane's pty to have any effect (a `tail -f` pane has
nothing meaningful to send keys to). So the pane hosts the actual `claude -p` dispatch via a
`_pane-exec` re-entry into `orchestrate.sh` (reuses `_run_one_session`, no duplicated dispatch
logic) rather than mirroring a log file.

## 2026-07-03 10:10 Pane driver: tmux, not cmux (open-fork 2)

Per ROADMAP.md open-fork 2 + this sub-goal's dispatch prompt: cmux is a GUI daily-driver app
scoped to `CMUX_WORKSPACE_ID`, with a browser-oriented skill surface (`cmux-browser`), not a
general scriptable pane driver reachable headlessly/in CI. tmux has a real CLI
(`new-window`/`capture-pane`/`send-keys`) that is mockable via a `TMUX_CMD` env seam (same
pattern as `CLAUDE_CMD`) and behaves identically on macOS/Linux/CI. Picking tmux is what keeps
the on-path testable without a real terminal-multiplexer server in CI, and keeps the off-path
trivially true (no cmux-specific state to avoid touching). No `cmux` code path was added; if a
future need arises for a cmux driver, it is a separate, additive `PANE_DRIVER=cmux` branch, not
a rework of this one.

## 2026-07-03 10:15 Serial path (`cmd_run`, non-wave) is untouched

The goal file and ADR-0032 s4 scope the multiplexer to *wavefront wave sessions* only ("each
wavefront wave session is spawned into a pane"). The serial delegate path in `cmd_run` (used
when `WAVE_CAP=1`, i.e. today's default) has exactly one in-flight session at a time already
attached to the conductor's own terminal, so there is nothing to "watch across tabs" -- the
multiplexer only wires into `_wave_run`'s per-sub-goal spawn step. `MULTIPLEXER=1` with
`WAVE_CAP=1` is a no-op (no wave ever runs) rather than an error.

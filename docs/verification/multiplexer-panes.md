# Proof of done: multiplexer panes (SPEC-119, orchestrate-hardening 04)

An OPT-IN multiplexer (`MULTIPLEXER=1`, default `0`): when enabled, `orchestrate.sh` spawns each
wavefront wave session into its own tmux window (`tmux new-window`), so an operator can
`tmux capture-pane` its live output or `tmux send-keys` to intervene. OFF by default: the headless
wavefront path is byte-unchanged and `$TMUX_CMD` is never invoked. Executes ADR-0032 §4. Open-fork 2
(tmux vs cmux) resolved: host the real session in a `tmux new-window` pane (tmux is the
portable/headless-safe default; cmux noted as the operator's daily-driver alternative). The
off-path-unchanged property is the load-bearing one and carries an explicit negative control.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| A1 | `MULTIPLEXER=1` wave run completes (`_wave_run` rc 0) and flips every sub-goal box | PASS |
| A2 | Each wave session is spawned via `tmux new-window -n SG-NN` (a pane per sub-goal) | PASS |
| A3 | Visibility works: `tmux capture-pane` returns the wave session's live output | PASS |
| A4 | Intervention works: `tmux send-keys` reaches a running wave session's pane | PASS |
| N1 | OFF-DEFAULT NC: with `MULTIPLEXER` unset, `$TMUX_CMD` is NEVER invoked (no window, no send-keys) | PASS |
| N2 | OFF-EXPLICIT NC: `MULTIPLEXER=0` never invokes tmux | PASS |
| N3 | Off-path-unchanged: with the multiplexer off, the headless wavefront path completes and flips boxes even with a poisoned `$TMUX_CMD` (proves no coupling) | PASS |
| R | Regression: `test-orchestrate-wavefront.sh`, `test-tier4-close.sh`, `test-meta.sh`; `shellcheck -S error lib/orchestrate.sh` clean | PASS |

The off-path-unchanged NC is non-vacuous: the OFF cases run with a deliberately poisoned `$TMUX_CMD`,
so any accidental tmux call on the headless path would fail the wave; boxes still flip via the
pre-existing kill-0/wait background path, proving the multiplexer is additive, not on the critical path.

## Run table

```
$ bash tests/test-multiplexer.sh
PASS mux-on: _wave_run rc 0
PASS mux-on: SG-01 box flipped
PASS mux-on: SG-02 box flipped
PASS mux-on: tmux new-window spawned a pane for SG-01
PASS mux-on: tmux new-window spawned a pane for SG-02
PASS mux-on: capture-pane SG-01 returns its live output
PASS mux-on: capture-pane SG-02 returns its live output
PASS mux-on: send-keys reached SG-01's pane
PASS mux-off NC: _wave_run rc 0 (headless path unaffected by the poisoned tmux)
PASS mux-off NC: SG-01 box flipped via the plain background path
PASS mux-off NC: SG-02 box flipped via the plain background path
PASS mux-off NC [NEGATIVE CONTROL]: $TMUX_CMD never invoked (no tmux window, no send-keys) with MULTIPLEXER unset
PASS mux-off explicit (MULTIPLEXER=0) [NEGATIVE CONTROL]: tmux never invoked
ALL PASS
```

Regression (all rc 0): `test-orchestrate-wavefront.sh`, `test-tier4-close.sh`, `test-meta.sh`;
`shellcheck -S error lib/orchestrate.sh` clean.

## Reproduce

```
cd <dwarves-kit>
bash tests/test-multiplexer.sh          # ALL PASS (enabled spawn/capture/send-keys + off NCs)
bash tests/test-orchestrate-wavefront.sh # regression: wave path intact
```

The test mocks tmux via `TMUX_CMD` (no real tmux server needed, CI-safe) and `claude` via `CLAUDE_CMD`,
mirroring the existing orchestrate test seams.

## Coverage delta

- **Covered:** enabled pane spawn (A2) · capture-pane visibility (A3) · send-keys intervention (A4) ·
  off-default NC (N1) · off-explicit NC (N2) · off-path-unchanged under poisoned tmux (N3).
- **Uncovered (declared):** a live tmux server end-to-end (mock seam only, same discipline as the
  other orchestrate suites) · cmux driver path (open-fork 2 picked tmux; cmux is a documented future
  alternative, not wired) · multi-wave (>1 concurrent window) beyond the 2-session fixture.

# Proof of done: pane viewer push (SPEC-121, board ID-092)

The PUSH half of SPEC-119's pull-only multiplexer panes, DEFAULT ON (`PANE_VIEWER=auto`,
operator decision 2026-07-03): on wave spawn under `MULTIPLEXER=1`, ONE viewer tab/surface
(cmux/kitty/wezterm/ghostty/iterm/terminal, auto-detected) opens in the operator's terminal app
already attached to the wave's tmux session, fire-and-forget (a hung viewer can never stall the
wave). `none` = today's pull behavior exactly; headless (no TTY / nothing detected) degrades
SILENTLY so CI stays byte-identical -- the named negative control. Security follows the
SPEC-119 #143 pattern: exec-direct argv only, charset-gated session names, exact-token
`PANE_VIEWER` allowlist at pre-flight. Hardened by a 4-lens review round (security /
architecture / test-coverage / advisor): fire-and-forget exec, exact-token allowlist,
sanitized reuse-guard key, all-six-viewer argv pins, real-exec path coverage, CI wiring for
the previously-unwired orchestrate-family suites.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| A1 | Default is `auto` (push by default); unset `PANE_VIEWER` resolves to auto | PASS (T1) |
| A2 | Auto-detect order: cmux env first, then `$TERM_PROGRAM` (iTerm.app/ghostty/WezTerm/Apple_Terminal), then `$KITTY_WINDOW_ID`, else degrade | PASS (T2, 8 assertions) |
| A3 | ONE viewer surface per wave session per run (2-sub-goal wave -> exactly 1 open; repeat opens for the same session are no-ops) | PASS (T4, T5) |
| A4 | The surface runs `tmux attach -t <wave session>` via exec-direct argv (no `$SHELL -c` re-parse); every viewer's argv shape pinned, incl. the osascript argv-item property (session name a trailing argv item, never spliced into the AppleScript source) | PASS (T4, T10b x5) |
| A5 | Unknown `PANE_VIEWER` -> pre-flight rc 64 naming the allowed set; exact-token match (multi-token `"cmux kitty"` rejected) | PASS (T9 x3) |
| A6 | cmux argv pins `--focus false`, never `--focus true` (known cmux RPC wedge) | PASS (T10) |
| A7 | Fire-and-forget: the viewer exec is backgrounded + disowned; a hung/slow viewer cannot stall the spawn loop or the abort path | by construction (DEC-006; the exec runs in a disowned subshell) + T12/T13 observe the async degrade |
| N1 | `PANE_VIEWER=none` = pull exactly: wave completes, poisoned viewer never invoked | PASS (T6) |
| N2 | HEADLESS NC (named): default `auto`, detectable viewer env present, NO TTY -> byte-identical to today; poisoned viewer never invoked (the TTY gate proven end-to-end) | PASS (T3, T7) |
| N3 | `MULTIPLEXER` unset -> viewer logic unreachable even with an explicit viewer set | PASS (T8) |
| N4 | SECURITY NC: a metachar session name (hostile `TMUX_SESSION`) is refused by the `[A-Za-z0-9_-]` charset gate -- viewer never invoked, loud warn; guard list stays untainted (sanitized key) | PASS (T11) |
| N5 | A failing viewer (nonzero exec) warns + degrades to pull; wave rc 0, boxes still flip; real-exec missing-binary path (rc 127) degrades identically | PASS (T12, T13) |
| R | Regressions unedited + green: multiplexer, orchestrate, orchestrate-wavefront, tier4-close, token-capture, model-routing, spec-index, meta, hooks, e2e, lane-classify, lane-telemetry, mega-merge, ledger-durability, meta-agent, review-team-plants, role-classify, proof-visual-evidence; `shellcheck -S error lib/orchestrate.sh tests/test-pane-viewer.sh` clean | PASS |

The NCs are non-vacuous: every off/degrade case runs with a POISONED `$VIEWER_CMD` (any
invocation writes a sentinel and exits 99), so a coupling leak on the pull paths fails the
test rather than going unnoticed. The review round's mutation testing independently confirmed
the reuse guard, the `MULTIPLEXER=1` scoping, and the `--focus false` pin all fail their tests
when removed. T11's refusal path is paired with T10's same-shape positive control (the
identical `_viewer_open` call with a clean session name DOES invoke the recorder); T11's
pwned-file check is declared advisory (the argv-direct mock cannot re-parse the payload; the
load-bearing asserts are the empty recorder log + the loud warn).

## Run table

```
$ bash tests/test-pane-viewer.sh
PASS T1 default: PANE_VIEWER unset resolves to 'auto' (push is the default)
PASS T2 detect: cmux env beats TERM_PROGRAM
PASS T2 detect: TERM_PROGRAM=iTerm.app -> iterm
PASS T2 detect: TERM_PROGRAM=ghostty -> ghostty
PASS T2 detect: TERM_PROGRAM=WezTerm -> wezterm
PASS T2 detect: TERM_PROGRAM=Apple_Terminal -> terminal
PASS T2 detect: KITTY_WINDOW_ID after TERM_PROGRAM misses -> kitty
PASS T2 detect: nothing set -> empty (degrade)
PASS T2 resolve: auto + TTY + WezTerm -> wezterm
PASS T3 resolve: auto + NO TTY -> none even with a viewer env present (headless degrade)
PASS T3 resolve: unknown PANE_VIEWER value falls back to none (defense-in-depth)
PASS T4 wave: _wave_run rc 0
PASS T4 wave: viewer opened EXACTLY once for a 2-sub-goal wave (one surface per wave, not per worker)
PASS T4 wave: argv is the exec-direct wezterm attach to the wave's tmux session
PASS T5 reuse: three _viewer_open calls for one session -> one invocation
PASS T6 none [NEGATIVE CONTROL]: PANE_VIEWER=none completes the wave and never invokes a viewer (pull exactly)
PASS T7 headless [NEGATIVE CONTROL]: default auto + detectable viewer env but NO TTY degrades silently -- the TTY gate holds end-to-end, headless CI byte-identical to today
PASS T8 mux-off [NEGATIVE CONTROL]: viewer logic unreachable with MULTIPLEXER unset (plain pull path untouched)
PASS T9 allowlist: unknown PANE_VIEWER rejected at pre-flight (rc 64) naming the allowed set
PASS T9 allowlist: a valid PANE_VIEWER value passes pre-flight
PASS T9 allowlist: multi-token 'cmux kitty' is rejected (exact-token match, not substring)
PASS T10 cmux: argv pins --focus false and never --focus true (known cmux RPC wedge)
PASS T10 cmux: surface command attaches to the wave's tmux session
PASS T10b kitty: exec-direct argv shape
PASS T10b wezterm: exec-direct argv shape
PASS T10b ghostty: exec-direct argv shape
PASS T10b iterm: osascript gets the session name as a trailing argv item, never spliced into the source
PASS T10b terminal: osascript gets the session name as a trailing argv item, never spliced into the source
PASS T11 charset [SECURITY NC]: a metachar session name is refused -- viewer never invoked, no host command ran, wave untouched (rc 0)
PASS T11 charset: refusal is loud (warn names the gate)
PASS T12 resilience: a failing viewer (rc 7) degrades to pull; wave rc 0 and both boxes flipped
PASS T12 resilience: degrade warn emitted
PASS T13 real-exec: missing viewer binary (command -v miss, rc 127) degrades to pull; _viewer_open rc 0
----
ALL PASS
```

Regression (all rc 0, unedited): `test-multiplexer.sh`, `test-orchestrate.sh`,
`test-orchestrate-wavefront.sh`, `test-tier4-close.sh`, `test-token-capture.sh`,
`test-model-routing.sh`, `test-spec-index.sh`, `test-meta.sh`, `test-hooks.sh`,
`test-e2e.sh`, `test-lane-classify.sh`, `test-lane-telemetry.sh`, `test-mega-merge.sh`,
`test-ledger-durability.sh`, `test-meta-agent.sh`, `test-review-team-plants.sh`,
`test-role-classify.sh`, `test-proof-visual-evidence.sh`.
`shellcheck -S error lib/orchestrate.sh tests/test-pane-viewer.sh` clean.

## Reproduce

```
cd <dwarves-kit>
bash tests/test-pane-viewer.sh              # ALL PASS (33 assertions, T1-T13)
bash tests/test-multiplexer.sh              # regression: SPEC-119 pull half intact
bash tests/test-orchestrate-wavefront.sh    # regression: wave path intact
shellcheck -S error lib/orchestrate.sh
```

Viewers are mocked via the `VIEWER_CMD` seam (recorder / poison / failing scripts), tmux via
`TMUX_CMD`, claude via `CLAUDE_CMD` -- no GUI, no tmux server, CI-safe on ubuntu + macos.
This PR also wires the previously-unwired orchestrate-family suites into
`.github/workflows/test.yml` (wavefront, multiplexer, pane-viewer, token-capture,
model-routing, spec-index), closing the advisor P1 gap where the proof cited suites CI never
ran.

## Coverage delta

- **Covered:** default=auto (A1) - detect order incl. cmux-beats-TERM_PROGRAM (A2) -
  one-surface-per-wave + run-spanning reuse (A3) - exec-direct argv for all six viewers incl.
  the osascript argv-item property (A4) - exact-token allowlist pre-flight (A5) - cmux focus
  pin (A6) - the three pull NCs under poison (N1-N3) - TTY gate end-to-end (T7) - charset-gate
  security NC with untainted guard (N4) - viewer-failure + missing-binary resilience (N5) -
  `_viewer_resolve` unknown-value fallback (T3).
- **Uncovered (declared):** real GUI viewers end-to-end (seam-mocked, same discipline as the
  TMUX_CMD/CLAUDE_CMD suites) - the iTerm2 `tmux -CC` control-mode path (documented as the
  zero-code operator alternative in SPEC-121, deliberately not built) - a real cmux socket
  round-trip (the `--focus false` pin is argv-asserted, not app-observed) - a genuinely hung
  viewer stalling test (fire-and-forget is proven by construction + disown, not by a live
  hang fixture) - closed-tab re-open (spec edge case 5, intended no-op).

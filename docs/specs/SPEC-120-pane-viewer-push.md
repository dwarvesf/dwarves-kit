# Spec: pane viewer push (default-on viewer tabs for multiplexer waves)
Generated: 2026-07-03
Status: DRAFT
Lane: full

## Problem

SPEC-119's multiplexer (`MULTIPLEXER=1`) hosts each wave session in a tmux window, but the
model is PULL-only: the operator must know the session name and manually `tmux attach` from
some terminal. Nothing brings the wave to the operator. The push half is missing: when a wave
spawns, the operator's own terminal app should grow ONE tab/surface already attached to the
wave's tmux session, so watching a wave costs zero keystrokes. Operator decision 2026-07-03:
push is the DEFAULT (auto-detect), with silent degrade to today's pull behavior anywhere a
viewer cannot be found (headless CI stays byte-identical).

## Design

### Approaches considered

1. **One viewer surface per WORKER pane.** Maximal visibility, but a 4-sub-goal wave opens 4
   tabs per cycle -- noise the operator explicitly rejected. Rejected.
2. **One viewer surface per WAVE, attached to the wave's shared tmux session** (all worker
   windows reachable inside it with native tmux keys). One tab per run; tmux's own
   window-switching does the per-worker drill-down. **Chosen.**
3. **iTerm2 `tmux -CC` control mode** (zero-code alternative): an operator who runs
   `tmux -CC attach -t <session>` from iTerm2 gets every wave window as a NATIVE iTerm tab,
   no orchestrator wiring at all. Documented (below), not built -- it is an operator habit,
   not a seam, and it covers only iTerm.

### Chosen approach

A `_viewer_open <megadir>` hook in `_wave_run`'s `MULTIPLEXER=1` spawn branch: after the first
successful `_pane_spawn`, open ONE viewer surface running `tmux attach -t <session>`. Three
small functions, mirroring the SPEC-119 seam shape:

```
_viewer_detect            pure env sniff -> cmux|iterm|ghostty|wezterm|terminal|kitty|<empty>
_viewer_resolve           PANE_VIEWER mode -> effective viewer:
                            none          -> none (today's pull behavior exactly)
                            explicit name -> that viewer (operator intent; no TTY gate)
                            auto (DEFAULT)-> no TTY on stderr -> none (silent degrade)
                                             else _viewer_detect (nothing found -> none)
_viewer_open <megadir>    once per tmux session per run (reuse guard `_VIEWER_OPENED`, keyed
                          on a sanitized copy of the name); charset-gates the session name;
                          builds the viewer argv; execs it via the VIEWER_CMD seam
                          FIRE-AND-FORGET (backgrounded + disowned -- an osascript call can
                          block on a first-run macOS Automation permission dialog, and a
                          synchronous hang inside the spawn loop would stall the wave).
                          Best-effort: ALWAYS returns 0 -- a viewer failure warns and
                          degrades to pull, it never fails the wave.
```

**Auto-detect order** (first hit wins):
1. cmux env (`CMUX_WORKSPACE_ID` set -- the cmux workspace socket env);
2. `$TERM_PROGRAM`: `iTerm.app` -> iterm, `ghostty` -> ghostty, `WezTerm` -> wezterm,
   `Apple_Terminal` -> terminal;
3. `$KITTY_WINDOW_ID` set -> kitty;
4. nothing -> degrade to pull (none).

**Open commands** (all exec-direct argv; `<s>` = the tmux session name):

| Viewer | Command |
|---|---|
| cmux | `cmux new-workspace --name orch:<s> --command 'tmux attach -t <s>' --focus false` |
| kitty | `kitty @ launch --type=tab tmux attach -t <s>` |
| wezterm | `wezterm cli spawn -- tmux attach -t <s>` |
| ghostty | `open -na Ghostty --args -e tmux attach -t <s>` |
| iterm | `osascript` `on run argv` handler; session name passed as an osascript ARGV item, never spliced into the AppleScript source |
| terminal | same osascript argv shape against Terminal.app `do script` |

cmux note: `cmux new-surface` has no command argument (CLI-verified), so the cmux path uses
`new-workspace --command`; the surface is the workspace's terminal. `--focus false` is pinned:
`--focus true` into the controlling session's own pane is a known cmux RPC wedge (broken pipe
on both sockets, app restart to recover).

### Security (non-negotiable, the SPEC-119 #143 pattern)

- **Exec-direct argv only.** Every viewer invocation is a bash argv array executed directly
  (`"$@"`); nothing is joined into a string and re-parsed through `$SHELL -c` / `sh -c` /
  `eval`. The osascript paths pass the session name as an osascript argv item (`on run argv`),
  never string-spliced into the AppleScript source.
- **Session names stay sanitize-derived.** `_mux_session_name` output is `[A-Za-z0-9_-]` by
  construction; `_viewer_open` re-checks that charset and refuses (warn + pull) any name that
  violates it (defense-in-depth for an operator-set `TMUX_SESSION` carrying metachars), because
  two viewer sinks are string contexts downstream of us (cmux `--command` types into a shell;
  Terminal `do script` runs a shell line).
- **`PANE_VIEWER` is allowlist-validated at `cmd_run` pre-flight** (mirrors the `WAVE_CAP`
  rejection): an unknown value errors out naming the allowed set
  `auto|cmux|kitty|wezterm|ghostty|iterm|terminal|none`, never silently coerces. The check is
  EXACT-token enumeration (`case "$PANE_VIEWER" in auto|cmux|...`), not substring membership
  against the joined list -- a review round caught that `PANE_VIEWER="cmux kitty"` slipped
  through the membership idiom.

### Seams

- `PANE_VIEWER` (env, default `auto` -- PUSH is the default, operator decision 2026-07-03).
- `VIEWER_CMD` (env, default empty = exec the real viewer argv): when set, the whole viewer
  argv is handed to `$VIEWER_CMD` instead -- the TMUX_CMD-shaped mock seam, so CI needs no GUI
  and the off paths get a poisonable negative control.
- `_VIEWER_OPENED` (process-global): space-separated tmux session names a viewer was already
  opened for this run; the reuse guard. One attempt per session per run, success or not.

## After state

- [ ] `MULTIPLEXER=1` wave spawn with a detected/explicit viewer: exactly ONE viewer surface
  opens, attached to the wave's tmux session; a second sub-goal (and a second wave in the same
  run) does not open another.
- [ ] `PANE_VIEWER=none`: today's pull behavior exactly; the viewer seam is never invoked.
- [ ] Headless (default `auto`, no TTY, no viewer env): silently degrades to pull -- byte-identical
  to today; `$VIEWER_CMD` never invoked (named negative control).
- [ ] `MULTIPLEXER=0` (default): no viewer logic reachable at all (it lives inside the mux branch).
- [ ] Unknown `PANE_VIEWER` value: `cmd_run` pre-flight error naming the allowed set, nonzero exit.
- [ ] cmux argv contains `--focus false` and never `--focus true`.
- [ ] A viewer open failure warns and degrades; it NEVER marks the wave failed.

## Test plan

`tests/test-pane-viewer.sh` (sources orchestrate.sh; TMUX_CMD mock reused from
test-multiplexer.sh's fixture shape; viewer mocked via `VIEWER_CMD` recorder + poison scripts):

| # | Case | Kind |
|---|---|---|
| T1 | default: `PANE_VIEWER` unset resolves to `auto` | unit |
| T2 | `_viewer_detect` order: cmux env beats TERM_PROGRAM; each TERM_PROGRAM mapping; KITTY_WINDOW_ID; empty when nothing set | unit |
| T3 | auto + no TTY -> resolve = none (headless degrade) | unit |
| T4 | wave run, MULTIPLEXER=1, explicit viewer, 2 sub-goals -> recorder invoked EXACTLY once, argv = `tmux attach -t <session>` via the right viewer | integration |
| T5 | reuse: a second `_viewer_open` for the same session -> still one invocation | integration |
| T6 | `PANE_VIEWER=none` + poisoned VIEWER_CMD -> wave completes, poison never fires | negative control |
| T7 | headless auto (no viewer env, output captured) + poisoned VIEWER_CMD -> wave completes, poison never fires (headless CI byte-identical) | negative control (named) |
| T8 | MULTIPLEXER unset + poisoned VIEWER_CMD -> poison never fires (viewer unreachable outside mux branch) | negative control |
| T9 | `PANE_VIEWER=bogus` -> `run` pre-flight rc 64, error names the allowed set | pre-flight |
| T10 | cmux path: recorded argv has `--focus false`, never `--focus true` | security pin |
| T11 | metachar session name (hostile `TMUX_SESSION`) -> charset gate refuses, viewer never invoked, no host command runs | security NC |
| T12 | viewer open failure (VIEWER_CMD exits nonzero) -> wave still completes rc 0 | resilience |
| T10b | every viewer's built argv is dispatched + shape-pinned (kitty/wezterm/ghostty exact match; iterm/terminal osascript argv-item property: session name trailing, never spliced into the -e source) | security pin |
| T13 | real-exec path (VIEWER_CMD unset): missing viewer binary (command -v miss, rc 127) degrades to pull, `_viewer_open` rc 0 | resilience |

T7 deliberately exports a detectable viewer env (`TERM_PROGRAM=WezTerm`) so only the TTY gate
stands between auto and an exec -- it proves the gate end-to-end, not just "no env, no viewer".
T3 also pins `_viewer_resolve`'s unknown-value fallback to `none` (defense-in-depth behind the
pre-flight), and T9 pins the multi-token rejection (`"cmux kitty"` -> rc 64).

Regression: `test-multiplexer.sh`, `test-orchestrate-wavefront.sh`, `test-orchestrate.sh`,
`test-tier4-close.sh`, `test-token-capture.sh`, `test-meta.sh` all green, unedited.

## Verification

```bash
bash tests/test-pane-viewer.sh
bash tests/test-multiplexer.sh
bash tests/test-orchestrate-wavefront.sh
bash tests/test-orchestrate.sh
bash tests/test-tier4-close.sh
bash tests/test-token-capture.sh
bash tests/test-meta.sh
shellcheck -S error lib/orchestrate.sh
```

## Edge cases

1. `PANE_VIEWER=auto` inside cmux, whose embedded terminal also sets `TERM_PROGRAM`: cmux env
   is checked FIRST, so cmux wins (the ordering is load-bearing, T2 pins it).
2. Explicit viewer named but its binary is absent (e.g. `PANE_VIEWER=kitty` on a bare host):
   `_viewer_open` warns + degrades to pull; the wave is untouched (T12 shape).
3. Two waves in one run share the per-megagoal session name: the `_VIEWER_OPENED` reuse guard
   spans the run, so wave 2 opens nothing (T5).
4. `PANE_VIEWER=none` with `MULTIPLEXER=1`: panes still spawn (pull works), no surface opens.
5. The operator closes the pushed tab mid-run (or it dies): the reuse guard does not detect it,
   so later waves in the same run stay on pull with no re-open -- intended (`tmux attach -t
   <session>` by hand re-attaches at any time; auto-re-open would need viewer-side liveness
   polling, out of scope).

## Out of scope

- Building the iTerm2 `tmux -CC` control-mode integration (documented as the zero-code
  operator alternative in the Design block; it needs no orchestrator code).
- Viewer wiring for the serial (non-wave) path -- same DEC-004 scoping as SPEC-119.
- Closing/cleaning the viewer surface when the wave drains (the surface holds a plain
  `tmux attach`; tmux detach/exit ends it naturally).
- Per-worker surfaces, viewer preference files, or any new daemon.

## Touches
- lib/orchestrate.sh
- tests/test-pane-viewer.sh
- .github/workflows/test.yml
- docs/verification/pane-viewer-push.md
- docs/decisions/0032-megagoal-execution-hygiene.md (addendum: section-4 surface growth)
- README.md (orchestrate row: MULTIPLEXER + PANE_VIEWER)
- _meta/BACKLOG.md (ID-092..ID-099 rows + source footnote)

## Decision log
- DEC-001: one surface per WAVE session, not per worker (noise control; tmux window keys do
  the drill-down).
- DEC-002: default `auto` = push by default (operator decision 2026-07-03); silent degrade
  keeps headless byte-identical.
- DEC-003: viewer failure is NEVER wave failure (visibility affordance, not a dependency).
- DEC-004: cmux path via `new-workspace --command` because `new-surface` takes no command
  argument (verified against the installed cmux CLI); `--focus false` pinned (RPC wedge).
- DEC-005: TTY degrade applies to `auto` only; an explicit `PANE_VIEWER=<name>` is operator
  intent and always attempts the open.
- DEC-006 (review round, architecture P1): the viewer exec is fire-and-forget (backgrounded +
  disowned), because the osascript sinks can block on a first-run macOS Automation permission
  dialog and a synchronous hang inside `_wave_run`'s spawn loop would stall the whole wave.
- DEC-007 (review round, security P2): pre-flight allowlist is exact-token enumeration; the
  space-joined membership idiom accepted multi-token values like `"cmux kitty"`.

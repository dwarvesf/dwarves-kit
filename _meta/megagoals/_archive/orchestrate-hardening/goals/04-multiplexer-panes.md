# Sub-goal 04: multiplexer panes (opt-in wavefront visibility)

**Merge policy:** auto
**Time budget:** 3-4 hours.
**Proof:** run-table: with the multiplexer ENABLED, each wavefront wave session is spawned into a tmux/cmux pane (`tmux new-window` / `capture-pane` / `send-keys`) , watchable + interruptible · with it OFF (the default), the wavefront path is BYTE-UNCHANGED (pure headless `claude -p`, no panes) , the off-path-unchanged assertion is the load-bearing one · a `capture-pane` read returns the wave session's live output (visibility works) · negative control: the multiplexer OFF spawns NO tmux window / no `send-keys` (headless orchestration is not silently coupled to tmux). Capture a pane-spawn sample + the off-path-unchanged diff.
**Depends on:** 02.
Model: sonnet
Effort: medium
**Branch:** feat/oh-04-multiplexer
**PR base:** feat/oh-03-tier4-close

## Outcome

An OPT-IN multiplexer: when enabled, `orchestrate.sh` spawns each wavefront (ADR-0030) wave session into a tmux/cmux pane (`tmux new-window` to spawn, `capture-pane` to receive, `send-keys` to pass/control/intervene), giving the operator the "watch + intervene across tabs" experience over what is otherwise a headless, unwatchable parallel `claude -p` dispatch. OFF by default: pure orchestration (spawn / control / receive) already works headlessly via Bash + `claude -p` (the delegate pattern), so the multiplexer ADDS visibility + interactive intervention only , it is not required for orchestration. Minimum-infra: tmux (and cmux) are already installed; no new daemon. Open-fork 2 (tmux vs cmux as the pane driver) is a /spec pick.

## Quality bar

OFF-BY-DEFAULT and off-path-UNCHANGED is the load-bearing property: when the multiplexer is off, the headless wavefront path is byte-identical to today (the NC proves no silent coupling to tmux). The multiplexer wraps the EXISTING headless wave dispatch , it does not replace it. Minimum-infra (tmux/cmux already installed, no new daemon, no always-on listener). The pane driver (open-fork 2) is picked once in /spec; default to the choice that keeps the headless path intact when off.

## How to close the loop

`/spec` + `/spec-validate` first (pin the enable flag + the pane driver , open-fork 2 tmux vs cmux , and the spawn/capture/send-keys wiring over the existing wavefront dispatch). Then `bash tests/test-multiplexer.sh`: enabled spawns a pane per wave session and `capture-pane` reads its output, the OFF default leaves the wavefront path byte-unchanged (the NC: no tmux window when off), and the enabled-visibility assertion holds. Capture a pane-spawn sample + the off-path diff. Assumptions: ROADMAP 04 + open-fork 2.

**Done =** enabling the multiplexer spawns each wave session into a tmux/cmux pane (spawn + capture-pane + send-keys), the OFF default leaves the headless wavefront path byte-unchanged (no-tmux-when-off NC), visibility works (capture-pane reads live output), samples captured, tests green.

## Scope edges

**In:** the opt-in enable flag, the `tmux new-window` / `capture-pane` / `send-keys` wiring over the existing wavefront dispatch, the pane-per-wave-session spawn, tests + samples.
**Out:** the model routing (01); the token capture (02); the TIER-4 close (03); the docs (05).
**Not:** a new terminal-control daemon (minimum-infra , tmux/cmux already provide the control plane); coupling headless orchestration to tmux (OFF-by-default, off-path-unchanged NC); making the multiplexer required for orchestration (it adds visibility only); a DAG/scheduler beyond ADR-0030 wavefront.

## Where to look

`lib/orchestrate.sh` (the wavefront wave dispatch , where a pane spawn wraps the headless `claude -p`), ADR-0030 (dag-wavefront scheduling , the parallel waves this makes watchable), the research note section 6 (the multiplexer control plane: tmux/cmux not ghostty; spawn/capture/send-keys), the cmux-browser skill + `CMUX_WORKSPACE_ID` (the operator's cmux daily driver , open-fork 2), ADR-0032 section 4 (the opt-in multiplexer decision).

## PR body

Multiplexer panes (opt-in wavefront visibility): when enabled, `orchestrate.sh` spawns each wavefront wave session into a tmux/cmux pane (`tmux new-window` / `capture-pane` / `send-keys`) for watch + intervene; OFF by default, headless path byte-unchanged. Minimum-infra (tmux/cmux already installed). Executes ADR-0032 section 4. Stacked on #<03's PR>; review after it. Verify: `bash tests/test-multiplexer.sh` (enabled-spawns-pane + capture-pane-visibility + off-path-unchanged NC) + samples. Roadmap: ops-toolkit `_meta/megagoals/orchestrate-hardening/ROADMAP.md`.

## Notes

<empty>

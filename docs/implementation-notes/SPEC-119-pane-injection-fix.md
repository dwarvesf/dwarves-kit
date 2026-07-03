# SPEC-119 delta: `_pane_spawn` command-injection fix

Delta from SPEC-119 (multiplexer panes), found by the orchestrate-hardening TIER-4 close
security lens. Not a spec change; a security defect in the shipped implementation.

## What was wrong

`_pane_spawn` (`lib/orchestrate.sh`) built the pane command as a SINGLE joined string passed to
`tmux new-window`. Real tmux hands a lone command string to `$SHELL -c` , a second shell parse,
i.e. an `eval`. Each field was wrapped in escaped quotes (`\"$route_flags\"`), and `route_flags`
derives from the goal file's UNSANITIZED `Model:`/`Effort:` header (`_route`, no validation). So a
hostile/careless mega-goal PR with a `Model:` value like `opus"; touch X; echo "` closed the quote
wrapper, injected a host command, and ran it on the operator's box under `MULTIPLEXER=1`.
Reproduced live by the reviewer (a sentinel file was created) and re-reproduced in the test's D1
positive control.

## Fix

Pass the pane command as SEPARATE argv tokens after `--` (`tmux new-window ... -- prog a b c`).
tmux execs that argv directly, with no `$SHELL -c` re-parse. `route_flags` stays ONE argv token, so
`cmd_pane_exec` still receives its 5 positional args and `_run_one_session`'s existing unquoted
`$route_flags` word-splitting is unchanged (non-mux-path parity). Downstream is safe because
unquoted expansion word-splits but does not re-interpret metacharacters (the same reason the
non-mux dispatch was never vulnerable).

## Test delta

- The mock tmux `new-window` now models BOTH real behaviors: a multi-arg command (post-`--`) is
  exec'd directly (no re-parse); a single string is `eval`'d (the pre-fix sink). Without this, the
  NC could not distinguish the two forms.
- Section D: D1 positive control feeds the old joined-string form and asserts the payload DOES fire
  (proves the NC is non-vacuous); D2 drives the real fixed `_pane_spawn` with the same payload and
  asserts it stays inert. D2 is the load-bearing negative control.

## Scope note

Fix-forward on `master` after SG-04 (#142) merged, rather than amending it. The other three wave
surfaces (`--model` routing, token capture, TIER-4 close) were reviewed and are clean (non-mux
`$route_flags` is word-split not re-parsed; token capture takes the silent `> $slog` branch never
`tee`; the close prompt is fed on stdin never a command line).

# Implementation notes -- onboard-follow-through

Delta from the ask only.

- The "ignores a project .kit.toml" distill test needed an explicit `KIT_CONFIG_ROOT="$KIT_DIR"`
  that its predecessor lacked. Without it, an unset `KIT_CONFIG_ROOT` reads whatever kit is
  installed at `$HOME/.claude/dwarves-kit` on the machine running the suite, not this worktree's
  `kit.toml`; the old test happened to pass because the installed copy's default matched the old
  `false` fallback argument by coincidence, not because the resolver was pinned. Flipping the
  default exposed the gap. Fixed by pinning `KIT_CONFIG_ROOT` like the built-in-default assertions
  already do.
- `wrap.follow_through` was left untouched, per the ask; the new onboard question writes it to the
  operator `kit.toml` only when the operator answers (including an explicit `off`), never on a
  decline, since `bin/config` has no write verb and onboard's other knob writes already work this
  way (preview an exact line, confirm, then edit the file directly).

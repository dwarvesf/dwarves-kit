# Implementation notes: multi-vendor dispatch (ID-390)

Delta log for the `feat/multi-vendor-dispatch` branch. Decisions not obvious from the diff, and the
review-round fixes. The feature itself is described in `docs/verification/harness-adapter.md`.

## 2026-07-22 Review round (3 fresh-context lenses: security, architecture, test-coverage)

### CRITICAL: the opt-in gate was self-authorizable from inside the untrusted PR

Security reviewer, reproduced live. `kit_config_get` resolves the project `.kit.toml` BEFORE the
kit-root `kit.toml` (project wins), and `.kit.toml` is a git-tracked consumer-repo file (only the
kit-root `/kit.toml` is gitignored). So a hostile mega-goal PR could add `Harness: codex` to a goal
file AND `enabled_agent_clis = "codex"` to `.kit.toml` in the SAME PR and self-enable the vendor the
operator never opted into. This defeats the feature's entire security invariant.

**Decision:** the enablement list is read from the KIT-ROOT layer ONLY
(`_kit_toml_get "$(kit_config_root)" mega enabled_agent_clis`), never the project layer. Rationale:
kit-root config (`~/.claude/dwarves-kit/kit.toml`) is the operator's machine-level install, which no
repo PR can write; the project `.kit.toml` rides inside the branch being executed and is therefore
untrusted for a security gate. **Tradeoff, documented in the doc + kit.toml comment:** per-project
enablement via a committed `.kit.toml` is intentionally NOT supported for this knob, precisely
because a committed file is PR-writable. A team that wants codex enabled sets it in each operator's
kit install, not in the repo. This is the one knob where the normal "project overrides kit-root"
precedence is deliberately inverted.

### HIGH: `Effort:` was unvalidated -> argv/TOML injection on two paths

Effort has no allowlist (by design: no honest cross-vendor mapping) and had no character validation
either. Two concrete injections:
- codex: effort is spliced into `-c model_reasoning_effort="<effort>"`; `Effort: high", x="y` breaks
  the TOML string (not shell injection, but attacker-controlled TOML the vendor parser may honor).
- claude (pre-existing, adjacent): `route_flags="$route_flags --effort $reffort"` is deliberately
  word-split into `claude -p $route_flags`, so `Effort: x --mcp-config /tmp/e.json` injects extra
  argv tokens onto the real claude process. Same class SPEC-119 fixed for the tmux path.

**Decision:** validate `effort` against `^[A-Za-z0-9_-]+$` in `_route` (the ONE chokepoint both paths
pass through), reject with 64 otherwise. Covers every harness at once. `Model:` did NOT get a new
guard: claude models pass the exact-token tier allowlist (clean by construction) and non-claude
models become a single `harness_argv` array token (never word-split, no injection surface), so effort
was the only real vector. Restraint over a speculative model charset.

### HIGH: argv-mode prompt could be parsed as a flag (pi, opencode)

The prompt is a trailing positional for pi/opencode. If its first char is `-` (a benign `---`
markdown rule at the top of POINTER_PROMPT.md, or a hostile line), the CLI parses it as an option:
the "silent empty-prompt, exit 0" failure class.

**Decision + probe results:** verified on the installed binaries: pi REJECTS `--` (`Unknown option:
--`) so the standard end-of-options sentinel is not universally usable; but a leading NEWLINE guard
works for both (pi returned the reply; opencode reached its API-key check = arg-parse passed). So the
`argv)` delivery branch prepends `\n` to the prompt so it can never start with `-`. A leading blank
line is semantically inert to an LLM. `--` was rejected as the fix specifically because pi cannot
take it; the newline guard is the portable equivalent. Ceiling: relies on the CLI treating `arg[0] ==
'-'` as an option marker (both do); if a future vendor needs a different escape, branch per-vendor.

### HIGH/MED: `_run_one_session_vendor` swallowed `_route`'s exit code

`... < <(_route "$gf") || true` masked a routing failure and dispatched with empty model/effort. Only
non-fatal today because `_run_one_session` re-gates via `_harness_of` first, but a fail-open in a
fail-closed feature. **Decision:** capture and check `_route`'s rc explicitly (`return 64` on
failure), matching every other call site. Also made `_route`'s two failure branches print a uniform
stdout line so a future caller's `read` behaves the same regardless of which gate failed.

### MED: vendor path silently skipped the stall watchdog

`_run_one_session_vendor`'s degrade-WARN covered stream/handoff/token-capture but not
`WATCHDOG_STALL_SECS`. An operator running the SG-11 stall watchdog got no signal that vendor
sub-goals are exempt. **Decision:** add `WATCHDOG_STALL_SECS` to the WARN condition + the doc caveat.
The watchdog genuinely cannot wrap the vendor path (it needs the same stream-json capture the vendor
CLIs lack), so this stays a documented degrade, not a new capability.

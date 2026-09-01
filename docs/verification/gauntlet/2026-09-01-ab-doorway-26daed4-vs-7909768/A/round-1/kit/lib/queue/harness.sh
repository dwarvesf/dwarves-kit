#!/usr/bin/env bash
# harness.sh -- resolve a CLI-agent vendor to the argv that runs it HEADLESSLY.
#
# Why this exists: orchestrate.sh dispatches every sub-goal as `"$CLAUDE_CMD" -p ... < "$pfile"`.
# The `$CLAUDE_CMD` seam was built as a TEST MOCK point, not a vendor seam, so four Claude-shaped
# assumptions sit downstream of it: the `-p` headless flag, prompt-on-stdin, `--model`/`--effort`
# spellings, and `--dangerously-skip-permissions`. This file is the adapter that makes the vendor a
# DATA choice instead of four hardcoded assumptions, so a sub-goal can be dispatched to codex / pi /
# opencode and pay THAT vendor's quota instead of the Claude one.
#
# Deliberate divergence from the prior art (AI-Builder-Club `open-agent-teams`, which does the same
# job by puppeting each vendor's interactive TUI through tmux send-keys): every vendor here has a
# real non-interactive mode, so we drive THAT. Headless means the exit code is a real exit code, and
# it deletes the whole class of TUI fragility that approach must carry -- busy-pane string scraping
# ("esc to interrupt" vs "esc interrupt"), trust-dialog detection, and the double-Enter workaround
# for prompts that open a slash-autocomplete popup. None of that has an analogue here, by design.
#
# Scope: this file RESOLVES argv. It spawns nothing and validates no model names (the claude-tier
# allowlist stays in orchestrate.sh `_route`, see "Model" below). Nothing calls it into the
# dispatch path yet -- wiring `_run_one_session` to it is a separate change with its own proof.
#
# bash-3.2 throughout (no assoc arrays): the vendor table is a `case`, which is also just less code
# than a TSV plus a parser.

set -uo pipefail

# Per-vendor permission posture, each overridable like orchestrate.sh's CLAUDE_FLAGS. Every read
# site below uses `${VAR:-}` rather than `$VAR`: these defaults only run at SOURCE time, so a caller
# that sources with a temporary assignment prefix (`FOO=bar source harness.sh`) leaves the variable
# unset by the time the function is CALLED. Under the consumer's `set -u` that aborted `harness_argv`
# mid-emit and handed back a TRUNCATED argv -- silently missing the permission flag, which does not
# fail loudly, it just hangs the unattended session on a permission wall. Caught on this branch's
# first live run; the `:-` is what makes the truncation structurally impossible.
#
# CODEX_FLAGS is NOT the `--dangerously-bypass-approvals-and-sandbox` that the prior art uses.
# orchestrate.sh already gives each wave sub-goal its own git worktree, so `-s workspace-write`
# confines the agent to exactly the tree it is supposed to edit and still lets it work unattended.
# Taking the bypass flag here would discard an isolation guarantee we have already paid for.
CLAUDE_HARNESS_FLAGS="${CLAUDE_HARNESS_FLAGS:---dangerously-skip-permissions}"
CODEX_FLAGS="${CODEX_FLAGS:--s workspace-write}"
OPENCODE_FLAGS="${OPENCODE_FLAGS:---auto}"
PI_FLAGS="${PI_FLAGS:-}"   # pi has no permission system; it is always autonomous.

# Known vendor ids, one per line. `claude` is first because it is the default everywhere.
harness_list() { printf '%s\n' claude codex pi opencode; }

# Exit 0 iff <vendor> is known. The caller's pre-flight guard.
harness_known() {  # vendor
  local v
  for v in $(harness_list); do [ "$v" = "${1:-}" ] && return 0; done
  return 1
}

# How the prompt reaches the agent: `stdin` or `argv`. This is the field the prior art's harness
# table does NOT carry (it send-keys everything, so delivery is uniform and uniformly fragile), and
# it is the one the caller cannot guess -- getting it wrong means the agent runs with an EMPTY
# prompt and exits 0, which reads as a clean run that did nothing.
#
# claude: `-p` reads the prompt from stdin (the shape orchestrate.sh already uses).
# codex:  `codex exec --help` -- "If not provided as an argument (or if `-` is used), instructions
#         are read from stdin", so the existing `< "$pfile"` redirect carries over unchanged.
# pi / opencode: prompt is a trailing positional ([messages...] / `run [message..]`); neither
#         documents stdin, so we do not assume it.
harness_prompt_mode() {  # vendor
  case "${1:-}" in
    claude|codex) printf 'stdin\n' ;;
    pi|opencode)  printf 'argv\n' ;;
    *) echo "harness: unknown vendor '${1:-}' (known: $(harness_list | tr '\n' ' '))" >&2; return 64 ;;
  esac
}

# Emit the argv for a headless run, ONE TOKEN PER LINE, prompt NOT included (the caller appends it
# per `harness_prompt_mode`). One-token-per-line is the wire format because several tokens contain
# characters a space-split would destroy -- codex's effort is the TOML fragment
# `model_reasoning_effort="high"`, whose embedded quotes must survive as a single argv element.
#
# Model: passed through VERBATIM. The kit's `Model:` tiers (opus/sonnet/haiku/fable) are Claude
# names; there is no honest cross-vendor tier mapping (gpt-5 is not "opus"), so a non-claude
# sub-goal declares that vendor's own model id and orchestrate.sh's tier allowlist stays
# claude-only. Empty model or effort emits no flag at all, so the vendor's own default wins --
# matching orchestrate.sh's existing "absent field -> session inherits its tier" behavior.
#
# Effort vocabularies differ per vendor and are NOT normalized here; each takes its own words
# (claude low..max, codex low..xhigh, pi off..xhigh, opencode minimal|high|max). Normalizing would
# mean inventing equivalences no vendor documents.
harness_argv() {  # vendor [model] [effort]
  local vendor="${1:-}" model="${2:-}" effort="${3:-}" f
  harness_known "$vendor" || {
    echo "harness: unknown vendor '$vendor' (known: $(harness_list | tr '\n' ' '))" >&2; return 64; }

  case "$vendor" in
    claude)
      printf '%s\n' claude -p
      [ -n "$model" ]  && printf '%s\n' --model "$model"
      [ -n "$effort" ] && printf '%s\n' --effort "$effort"
      for f in ${CLAUDE_HARNESS_FLAGS:-}; do printf '%s\n' "$f"; done
      ;;
    codex)
      printf '%s\n' codex exec
      [ -n "$model" ]  && printf '%s\n' --model "$model"
      # Effort is a config override, not a flag: `-c model_reasoning_effort="<level>"`. The value
      # is parsed as TOML, so the inner double quotes are load-bearing (bare `high` fails the TOML
      # parse and falls back to the raw string, which is not the documented contract).
      [ -n "$effort" ] && printf '%s\n' -c "model_reasoning_effort=\"$effort\""
      for f in ${CODEX_FLAGS:-}; do printf '%s\n' "$f"; done
      ;;
    pi)
      printf '%s\n' pi --print
      [ -n "$model" ]  && printf '%s\n' --model "$model"
      [ -n "$effort" ] && printf '%s\n' --thinking "$effort"
      for f in ${PI_FLAGS:-}; do printf '%s\n' "$f"; done
      ;;
    opencode)
      printf '%s\n' opencode run
      [ -n "$model" ]  && printf '%s\n' --model "$model"
      [ -n "$effort" ] && printf '%s\n' --variant "$effort"
      for f in ${OPENCODE_FLAGS:-}; do printf '%s\n' "$f"; done
      ;;
  esac
  return 0
}

# Direct invocation prints the resolved argv (one per line) so an operator can eyeball what a
# vendor would actually run. Sourcing (the test path, and the future orchestrate.sh path) skips it.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    list)   harness_list ;;
    mode)   shift; harness_prompt_mode "$@" ;;
    argv)   shift; harness_argv "$@" ;;
    *) echo "usage: harness.sh list | mode <vendor> | argv <vendor> [model] [effort]" >&2; exit 64 ;;
  esac
fi

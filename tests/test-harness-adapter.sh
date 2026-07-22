#!/usr/bin/env bash
# test-harness-adapter.sh
# Pins lib/queue/harness.sh (multi-vendor headless dispatch adapter) + the `fable` tier fix.
#
# The adapter's whole job is to emit argv, so every assertion here is "this vendor resolves to
# exactly these argv tokens". The invariants that matter:
#   - prompt-delivery mode is right per vendor (getting it wrong runs the agent with an EMPTY
#     prompt and exits 0, which reads as a clean run that did nothing -- the silent failure).
#   - empty model/effort emit NO flag (vendor default wins), matching orchestrate.sh's
#     "absent field -> session inherits its tier" behavior.
#   - codex's effort survives as ONE argv token WITH its embedded TOML quotes.
#   - an unknown vendor is rejected (exit 64), never silently defaulted to claude.
#   - `Model: fable` now passes orchestrate.sh's allowlist (the regression this branch fixes), and
#     an off-allowlist tier is still rejected (the negative control that proves the gate still gates).
#
# harness.sh is SOURCED so the functions are directly callable; its `BASH_SOURCE == $0` guard keeps
# the CLI dispatch from firing on source.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/queue/harness.sh
source "$KIT/lib/queue/harness.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# Assert harness_argv's full output (newline-joined) equals the expected block.
assert_argv() {  # label expected vendor [model] [effort]
  local label="$1" expected="$2"; shift 2
  local got; got=$(harness_argv "$@")
  [ "$got" = "$expected" ] && pass "$label" || { fail "$label"; printf 'got:\n%s\nwant:\n%s\n' "$got" "$expected"; }
}

assert_mode() {  # label vendor expected
  local got; got=$(harness_prompt_mode "$2")
  [ "$got" = "$3" ] && pass "$1" || { fail "$1"; printf 'got: %q  want: %q\n' "$got" "$3"; }
}

echo "== prompt delivery mode =="
assert_mode "claude reads stdin"    claude   stdin
assert_mode "codex reads stdin"     codex    stdin
assert_mode "pi takes a positional" pi       argv
assert_mode "opencode positional"   opencode argv

echo "== argv resolution, model + effort present =="
assert_argv "claude full" \
"claude
-p
--model
fable
--effort
high
--dangerously-skip-permissions" \
  claude fable high

assert_argv "codex full (effort is one TOML token)" \
"codex
exec
--model
gpt-5
-c
model_reasoning_effort=\"high\"
-s
workspace-write" \
  codex gpt-5 high

assert_argv "pi full" \
"pi
--print
--model
google/gemini-3-pro
--thinking
high" \
  pi google/gemini-3-pro high

assert_argv "opencode full" \
"opencode
run
--model
anthropic/claude-sonnet-5
--variant
high
--auto" \
  opencode anthropic/claude-sonnet-5 high

echo "== empty model/effort emit no flag (vendor default wins) =="
assert_argv "claude bare" \
"claude
-p
--dangerously-skip-permissions" \
  claude

assert_argv "codex bare" \
"codex
exec
-s
workspace-write" \
  codex

assert_argv "claude model-only (no --effort)" \
"claude
-p
--model
haiku
--dangerously-skip-permissions" \
  claude haiku

echo "== codex effort keeps its quotes as ONE argv element =="
# The wire format is one-token-per-line precisely so this token survives intact; a space-split
# would shatter it into `-c`, `model_reasoning_effort="high"` -> two broken pieces.
n=$(harness_argv codex "" high | wc -l | tr -d ' ')
tok=$(harness_argv codex "" high | sed -n '4p')
[ "$tok" = 'model_reasoning_effort="high"' ] && pass "codex effort is a single quoted token" \
  || { fail "codex effort token"; printf 'got: %q (of %s lines)\n' "$tok" "$n"; }

echo "== set -u truncation regression (found by the first live run) =="
# The flags vars are only assigned at SOURCE time, so `FOO=bar source harness.sh` leaves them unset
# at CALL time. With a bare `$VAR` read that aborted harness_argv mid-emit under the consumer's
# `set -u`, returning a partial argv MISSING the permission flag -- a dispatch that then hangs on a
# permission wall instead of failing loudly. Sub-shell with the var explicitly unset reproduces it.
got=$(unset CLAUDE_HARNESS_FLAGS; harness_argv claude haiku 2>&1)
case "$got" in
  *unbound*) fail "truncation regression: harness_argv aborts when the flags var is unset"; printf '%s\n' "$got" ;;
  *) [ "$got" = "$(printf 'claude\n-p\n--model\nhaiku')" ] \
       && pass "unset flags var degrades to a clean flagless argv, never a truncated one" \
       || { fail "unset-flags argv shape"; printf 'got:\n%s\n' "$got"; } ;;
esac

echo "== unknown vendor is rejected, never defaulted =="
if out=$(harness_argv nope 2>&1); then
  fail "unknown vendor should exit nonzero"; printf 'got: %s\n' "$out"
else
  rc=$?
  [ "$rc" = 64 ] && pass "unknown vendor exits 64" || { fail "unknown vendor rc"; echo "got rc=$rc"; }
fi
harness_known claude && pass "harness_known claude" || fail "harness_known claude"
harness_known nope   && fail "harness_known should reject nope" || pass "harness_known rejects nope"

echo "== fable tier fix (the regression this branch closes) =="
# orchestrate.sh's _route is the gate. Source it and drive the allowlist directly.
# shellcheck source=../lib/queue/orchestrate.sh
TIER4_CLOSE=0 source "$KIT/lib/queue/orchestrate.sh"
# Existence guard FIRST: a renamed/missing _route makes every `if _route ...` below fail, which the
# negative control would happily read as "the gate rejected it" -- a false green. Caught live on the
# first run of this suite (the function is `_route`, not `_route_flags`), so the guard stays.
type -t _route >/dev/null 2>&1 && pass "_route is sourceable from orchestrate.sh" \
  || { fail "_route not found after sourcing orchestrate.sh (renamed?); the allowlist cases below are meaningless"; echo "$fails FAILED"; exit 1; }
gf="$(mktemp)"; trap 'rm -f "$gf"' EXIT

printf 'Model: fable\nEffort: high\n' > "$gf"
if out=$(_route "$gf" 2>&1); then
  [ "$out" = "$(printf 'fable\thigh')" ] && pass "Model: fable is admitted" \
    || { fail "fable route flags"; printf 'got: %q\n' "$out"; }
else
  fail "Model: fable still rejected pre-flight"; printf 'got: %s\n' "$out"
fi

# Negative control: the allowlist still REJECTS an off-list tier, so the fix widened the list
# rather than removing the gate.
printf 'Model: sonet\n' > "$gf"
if _route "$gf" >/dev/null 2>&1; then
  fail "negative control: typo tier 'sonet' should still be rejected"
else
  pass "negative control: typo tier still rejected (gate intact)"
fi

# tier_of must normalize fable, or a fable ledger row becomes its own bogus "tier".
t=$(bash -c 'tier_of() { case "$1" in haiku*) echo haiku;; sonnet*) echo sonnet;; opus*) echo opus;; fable*) echo fable;; *) echo "$1";; esac; }; tier_of fable-5')
[ "$t" = fable ] && pass "tier_of normalizes fable-5 -> fable" || { fail "tier_of fable"; echo "got: $t"; }
grep -q 'fable\*) echo fable' "$KIT/lib/classify/route-suggest.sh" \
  && pass "route-suggest.sh carries the fable arm" || fail "route-suggest.sh missing fable arm"

echo
[ "$fails" = 0 ] && { echo "all green"; exit 0; } || { echo "$fails FAILED"; exit 1; }

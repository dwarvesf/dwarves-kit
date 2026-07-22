#!/usr/bin/env bash
# test-harness-dispatch.sh
# Pins the ID-390 WIRING: the `Harness:` goal-file header actually routes a sub-goal to a non-claude
# CLI. tests/test-harness-adapter.sh pins the argv RESOLVER; this file pins that orchestrate.sh
# reaches it, delivers the prompt correctly, and leaves the claude path alone.
#
# The load-bearing assertions:
#   - absent `Harness:` -> claude -> the ORIGINAL $CLAUDE_CMD path (the backward-compat invariant;
#     the 178 pre-existing orchestrate assertions are the other half of that proof).
#   - an unknown harness hard-stops (64) instead of falling back to claude -- a silent fallback
#     would run the sub-goal on the wrong, wrong-priced vendor.
#   - the claude tier allowlist applies ONLY to claude: `Model: gpt-5` under `Harness: codex` is
#     admitted verbatim, while the same value with no harness is still rejected (negative control).
#   - the vendor path really EXECS the vendor, with the prompt delivered per the adapter's declared
#     mode. Proven with mock binaries on PATH that record their argv + stdin to disk.
#
# The mocks are what make this a real test rather than a string comparison: a wrong prompt-delivery
# mode does not error, it runs the agent with an empty prompt and exits 0, so only an artifact
# written by the invoked process can tell the two apart.
set -uo pipefail
export TIER4_CLOSE=0
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/queue/orchestrate.sh
source "$KIT/lib/queue/orchestrate.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A mega-goal dir with one sub-goal whose goal file carries the given header lines.
mk_goal() {  # headers... -> echoes the megadir
  local dir; dir=$(mktemp -d "$TMP/mega.XXXXXX")
  mkdir -p "$dir/goals"
  { for h in "$@"; do printf '%s\n' "$h"; done; printf '\nbody\n'; } > "$dir/goals/01-thing.md"
  printf '%s\n' "$dir"
}

# Mock vendor binaries on PATH. Each records its argv and its stdin, so the test can prove BOTH that
# the right binary ran and that the prompt arrived by the right channel.
MOCKBIN="$TMP/bin"; mkdir -p "$MOCKBIN"
for v in codex pi opencode; do
  cat > "$MOCKBIN/$v" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP/$v.argv"
cat > "$TMP/$v.stdin"
exit 0
EOF
  chmod +x "$MOCKBIN/$v"
done
export PATH="$MOCKBIN:$PATH"

echo "== _harness_of: header parse + default =="
d=$(mk_goal "Model: opus");                 got=$(_harness_of "$d/goals/01-thing.md")
[ "$got" = claude ] && pass "absent Harness: defaults to claude" || { fail "default harness"; echo "got: $got"; }
d=$(mk_goal "Harness: codex");              got=$(_harness_of "$d/goals/01-thing.md")
[ "$got" = codex ] && pass "Harness: codex parses" || { fail "codex parse"; echo "got: $got"; }
d=$(mk_goal "Harness:   OpenCode  ");       got=$(_harness_of "$d/goals/01-thing.md")
[ "$got" = opencode ] && pass "Harness: is case-insensitive + trimmed" || { fail "case/trim"; echo "got: $got"; }
got=$(_harness_of "/nonexistent/goal.md")
[ "$got" = claude ] && pass "missing goal file -> claude" || { fail "missing file"; echo "got: $got"; }

echo "== unknown harness hard-stops, never falls back to claude =="
d=$(mk_goal "Harness: bogusvendor")
if out=$(_harness_of "$d/goals/01-thing.md" 2>&1); then
  fail "unknown harness should return nonzero"; echo "got: $out"
else
  rc=$?
  [ "$rc" = 64 ] && pass "unknown harness returns 64" || { fail "unknown harness rc"; echo "rc=$rc"; }
  case "$out" in *claude*) pass "error names the known vendors" ;; *) fail "error should list known vendors"; echo "$out" ;; esac
fi

echo "== tier allowlist is claude-only =="
d=$(mk_goal "Harness: codex" "Model: gpt-5" "Effort: high")
if out=$(_route "$d/goals/01-thing.md" 2>&1); then
  [ "$out" = "$(printf 'gpt-5\thigh')" ] && pass "non-claude model passes through verbatim" \
    || { fail "codex model passthrough"; printf 'got: %q\n' "$out"; }
else
  fail "codex Model: gpt-5 was rejected by the claude allowlist"; echo "got: $out"
fi
# Negative control: the SAME value with no Harness: is still claude, so the gate must still reject.
d=$(mk_goal "Model: gpt-5")
if _route "$d/goals/01-thing.md" >/dev/null 2>&1; then
  fail "negative control: gpt-5 under claude should still be rejected"
else
  pass "negative control: claude allowlist still rejects gpt-5"
fi

echo "== the vendor path really execs the vendor =="
run_vendor() {  # megadir -> rc, via _run_one_session
  local d="$1" pf="$TMP/prompt.txt"
  printf 'PROMPT_BODY_MARKER\n' > "$pf"
  _run_one_session "$d" SG-01 "$pf" "" 0 >/dev/null 2>&1
}

# codex: stdin delivery.
rm -f "$TMP/codex.argv" "$TMP/codex.stdin"
d=$(mk_goal "Harness: codex" "Model: gpt-5" "Effort: high"); run_vendor "$d"; rc=$?
[ "$rc" = 0 ] && pass "codex sub-goal dispatches rc=0" || { fail "codex dispatch rc"; echo "rc=$rc"; }
[ -f "$TMP/codex.argv" ] && pass "the codex binary was actually invoked" || fail "codex never ran"
got=$(tr '\n' ' ' < "$TMP/codex.argv" 2>/dev/null)
[ "$got" = 'exec --model gpt-5 -c model_reasoning_effort="high" -s workspace-write ' ] \
  && pass "codex argv carries model + TOML effort + sandbox flag" || { fail "codex argv"; printf 'got: %q\n' "$got"; }
grep -q PROMPT_BODY_MARKER "$TMP/codex.stdin" 2>/dev/null \
  && pass "codex received the prompt on STDIN" || fail "codex prompt not on stdin"

# opencode: argv delivery. Same prompt, different channel -- this is the pair that would silently
# pass with an empty prompt if the mode were wrong.
rm -f "$TMP/opencode.argv" "$TMP/opencode.stdin"
d=$(mk_goal "Harness: opencode" "Model: anthropic/claude-sonnet-5"); run_vendor "$d"
grep -q PROMPT_BODY_MARKER "$TMP/opencode.argv" 2>/dev/null \
  && pass "opencode received the prompt as an ARGV positional" || { fail "opencode prompt not in argv"; cat "$TMP/opencode.argv" 2>/dev/null; }
[ -s "$TMP/opencode.stdin" ] && fail "opencode stdin should be empty (prompt goes via argv)" \
  || pass "opencode stdin left empty (no double-delivery)"

# pi: argv delivery + its own effort spelling.
rm -f "$TMP/pi.argv"
d=$(mk_goal "Harness: pi" "Model: google/gemini-3-pro" "Effort: high"); run_vendor "$d"
grep -q -- '--thinking' "$TMP/pi.argv" 2>/dev/null \
  && pass "pi effort maps to --thinking, not --effort" || { fail "pi effort flag"; cat "$TMP/pi.argv" 2>/dev/null; }

echo "== claude path is untouched (backward compat) =="
# $CLAUDE_CMD is the mock seam every pre-existing test drives. With no Harness: header the vendor
# branch must not be taken at all, so a $CLAUDE_CMD mock still receives the dispatch.
rm -f "$TMP/claudemock.argv"
cat > "$TMP/claudemock" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP/claudemock.argv"
cat > /dev/null
exit 0
EOF
chmod +x "$TMP/claudemock"
d=$(mk_goal "Model: fable" "Effort: high")
CLAUDE_CMD="$TMP/claudemock" CLAUDE_FLAGS="" run_vendor "$d"
[ -f "$TMP/claudemock.argv" ] && pass "no Harness: header still routes through \$CLAUDE_CMD" \
  || fail "claude path regressed: \$CLAUDE_CMD mock never invoked"

echo "== observability degrade WARNs rather than blocking dispatch =="
rm -f "$TMP/codex.argv"
d=$(mk_goal "Harness: codex")
pf="$TMP/prompt.txt"; printf 'PROMPT_BODY_MARKER\n' > "$pf"
warn=$(CAPTURE_TOKENS=1 _run_one_session "$d" SG-01 "$pf" "" 0 2>&1 >/dev/null)
case "$warn" in
  *WARN*stream-json*) pass "CAPTURE_TOKENS on a vendor path WARNs" ;;
  *) fail "expected a WARN about no stream-json equivalent"; printf 'got: %s\n' "$warn" ;;
esac
[ -f "$TMP/codex.argv" ] && pass "and still dispatches (advisory, not a wall)" \
  || fail "observability degrade blocked the dispatch"

echo
[ "$fails" = 0 ] && { echo "all green"; exit 0; } || { echo "$fails FAILED"; exit 1; }

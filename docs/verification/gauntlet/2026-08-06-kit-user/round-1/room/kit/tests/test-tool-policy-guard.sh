#!/usr/bin/env bash
# test-tool-policy-guard.sh -- ID-452 backfill item 6/6, SPEC-212.
#
# Behavioral contract of hooks/tool-policy-guard.sh (deny/ask/allow + fail-open)
# plus its NEW wiring claims (hooks.json, settings.json, advisor module). The
# target is executable, so temp policy fixtures drive real invocations with hook
# JSON on stdin, asserting exit codes and stderr. One assert per SPEC-212 Test
# plan row (rows 1-22; row 23 is the one-time recorded live negative control,
# see docs/verification/backfill-tool-policy-guard.md).
#
# Hygiene: every invocation sets KIT_TOOL_POLICY explicitly AND HOME to an empty
# mktemp home, so neither the machine's real default-path policy nor an
# implementation that ignores the env var can confound a result. The harness is
# assert-and-continue: a failed assert never short-circuits the run, so the live
# NC's survivor claims are exercised, not skipped.
#
# Run: bash tests/test-tool-policy-guard.sh   (exit 0 = all rows green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
G="$KIT_DIR/hooks/tool-policy-guard.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }

F="$(mktemp -d -t tool-policy-guard-test.XXXXXX)"
trap 'rm -rf "$F"' EXIT
mkdir -p "$F/home"
ERR="$F/stderr"

# run <policy-path> <stdin-string> -- invoke the hook hermetically; sets RC + $ERR.
run() {
  printf '%s' "$2" | HOME="$F/home" KIT_TOOL_POLICY="$1" bash "$G" >"$F/stdout" 2>"$ERR"
  RC=$?
}

# Fixtures. v1 = domains at top level; v2 = capabilities + providers.
printf '%s' '{"browser":{"prefer":"browser-harness-js","rules":[{"match":"mcp__plugin_playwright","action":"deny","note":"Use the harness first."}]}}' > "$F/deny.json"
printf '%s' '{"scrape":{"prefer":"lightpanda","rules":[{"match":"mcp__x_scraper","action":"ask","note":"Try the CLI rung."}]}}' > "$F/ask.json"
printf '%s' '{"browser":{"prefer":"browser-harness-js","rules":[{"match":"mcp__plugin_playwright","action":"allow"}]}}' > "$F/allow.json"
printf '%s' 'not json' > "$F/bad.json"
printf '%s' '[1,2,3]' > "$F/nondict.json"
printf '%s' '{"_doc":"exported by the dashboard","capabilities":{"computer_use":{"prefer":"macos-use L0 ladder","providers":[{"match":"mcp__computer-use","action":"deny","note":"Climb the ladder."}]}}}' > "$F/v2-deny.json"
printf '%s' '{"_disabled":{"prefer":"nothing","rules":[{"match":"mcp__plugin_playwright","action":"deny","note":"dormant"}]}}' > "$F/underscore.json"
printf '%s' '{"computer_use":"disabled"}' > "$F/nondict-domain.json"
printf '%s' '{"browser":{"prefer":"browser-harness-js","rules":[{"match":"mcp__plugin_playwright","action":"ask","note":"warn only"},{"match":"mcp__plugin_playwright","action":"deny","note":"never reached"}]}}' > "$F/ask-then-deny.json"
printf '%s' '{"browser":{"prefer":"browser-harness-js","rules":[{"match":"mcp__plugin_playwright","action":"allow"},{"match":"mcp__plugin_playwright","action":"deny","note":"never reached"}]}}' > "$F/allow-then-deny.json"

PW='{"tool_name":"mcp__plugin_playwright_playwright__browser_click"}'

echo "=== AC-1/AC-4: deny blocks (v1, non-default path, empty HOME) ==="

run "$F/deny.json" "$PW"
assert "row 1: v1 deny exits 2" "$([ "$RC" -eq 2 ]; echo $?)"

grep -qF 'mcp__plugin_playwright_playwright__browser_click' "$ERR" \
  && grep -qF 'DENIED by policy (browser)' "$ERR" \
  && grep -qF 'Preferred: browser-harness-js' "$ERR" \
  && grep -qF 'Use the harness first.' "$ERR"
assert "row 2: deny stderr names tool, domain, preferred rung, note" $?

echo ""
echo "=== AC-2: ask warns without blocking ==="

run "$F/ask.json" '{"tool_name":"mcp__x_scraper__fetch"}'
assert "row 3: ask exits 0" "$([ "$RC" -eq 0 ]; echo $?)"

grep -qF 'policy-controlled (scrape)' "$ERR" \
  && grep -qF 'Preferred rung: lightpanda' "$ERR" \
  && grep -qF 'Proceed only if the lighter rung is genuinely exhausted.' "$ERR"
assert "row 4: ask stderr carries domain, preferred rung, proceed-only sentence" $?

echo ""
echo "=== AC-3: fail-open silence (exit 0 + EMPTY stderr, every branch) ==="

run "$F/allow.json" "$PW"
assert "row 5: explicit allow passes silently" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/deny.json" '{"tool_name":"Read"}'
assert "row 6: unmatched tool passes silently" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/nonexistent.json" "$PW"
assert "row 7: missing policy file passes silently (row 1's negative twin)" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/bad.json" "$PW"
assert "row 8: syntactically malformed policy fails open silently" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/nondict.json" "$PW"
assert "row 9: valid-but-non-dict policy fails open silently (round-1 CRITICAL)" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/deny.json" 'not json'
assert "row 10: malformed stdin payload fails open silently" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/deny.json" '[1,2,3]'
assert "row 11: valid-but-non-dict payload fails open silently (round-1 CRITICAL)" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/deny.json" ''
assert "row 12: empty stdin fails open silently" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/deny.json" '{}'
assert "row 13: missing tool_name passes silently" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

echo ""
echo "=== AC-5: schema normalization ==="

run "$F/v2-deny.json" '{"tool_name":"mcp__computer-use__screenshot"}'
assert "row 14: v2 capabilities/providers deny exits 2 + names its domain" "$([ "$RC" -eq 2 ] && grep -qF 'DENIED by policy (computer_use)' "$ERR"; echo $?)"

run "$F/underscore.json" "$PW"
assert "row 15: underscore-prefixed domain is skipped (deny never fires)" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

run "$F/nondict-domain.json" '{"tool_name":"mcp__computer-use__screenshot"}'
assert "row 16: non-dict domain value is skipped, not crashed on" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

echo ""
echo "=== AC-6: first matching rule wins ==="

run "$F/ask-then-deny.json" "$PW"
assert "row 17: ask listed first shadows the deny (warns, never blocks)" "$([ "$RC" -eq 0 ] && grep -qF 'policy-controlled' "$ERR" && ! grep -qF 'DENIED' "$ERR"; echo $?)"

run "$F/allow-then-deny.json" "$PW"
assert "row 18: allow listed first shadows the deny (silent pass)" "$([ "$RC" -eq 0 ] && [ ! -s "$ERR" ]; echo $?)"

echo ""
echo "=== AC-7: the wiring (the NEW claims) ==="

[ "$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | contains("tool-policy-guard")) | .matcher' "$KIT_DIR/hooks/hooks.json")" = "*" ]
assert "row 19: hooks.json registers exactly one PreToolUse entry, matcher *" $?

[ "$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | contains("tool-policy-guard")) | .matcher' "$KIT_DIR/settings.json")" = "*" ]
assert "row 20: settings.json registers exactly one PreToolUse entry, matcher *" $?

grep -E '^[[:space:]]*advisor\)' "$KIT_DIR/install.sh" | grep -qF 'tool-policy-guard.sh'
assert "row 21: install.sh maps the hook into the advisor module (order-tolerant)" $?

echo ""
echo "=== Row 22: in-suite NEGATIVE CONTROL (scratch copy, never the tracked file) ==="

# Prove the deny assertions discriminate: neuter the block on a COPY and watch
# the exit flip while the message survives. The count guard and the ! cmp -s
# setup guard are the asserts row 23 predicts RED under the live mutation.
[ "$(grep -c 'sys.exit(2)' "$G")" -eq 1 ]
assert "row 22a: sys.exit(2) occurs exactly once (the NC mutates all of deny, nothing else)" $?

MUT="$F/mutant.sh"
sed 's/sys.exit(2)/sys.exit(0)/' "$G" > "$MUT"

! cmp -s "$G" "$MUT"
assert "row 22b: NC setup guard: the mutation actually changed the scratch copy" $?

printf '%s' "$PW" | HOME="$F/home" KIT_TOOL_POLICY="$F/deny.json" bash "$MUT" >"$F/stdout" 2>"$ERR"
MUT_RC=$?
assert "row 22c: on the mutant, the deny fixture no longer blocks (exit 0: row 1's pin would go RED)" "$([ "$MUT_RC" -eq 0 ]; echo $?)"

grep -qF 'DENIED by policy (browser)' "$ERR"
assert "row 22d: the mutant STILL prints the DENIED message (row 2 survives: block gone, message path intact)" $?

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All tool-policy-guard contract tests passed.${NC}"
  exit 0
fi

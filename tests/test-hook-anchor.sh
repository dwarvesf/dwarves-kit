#!/bin/bash
# test-hook-anchor.sh -- every dispatch-table hook entry routes through hooks/anchor-root.sh.
#
# Both hooks/hooks.json (plugin path) and the root settings.json (bash-install path) are
# checked, .hooks entries only (the root statusLine key is a separate mechanism, out of scope).
# The checker runs first against embedded fixtures, so a green result on the real files
# cannot be vacuous: it must flag a bypass, and it must flag a wrapped exempt entry.
#
# Run: bash tests/test-hook-anchor.sh   Exit 0 = pass, 1 = failures.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

# Exemptions: hook basenames that must NOT run anchored. Each needs a reason, and the same
# entry must appear in the spec's Decision Log (the two lists never drift apart).
#   secrets-guard.sh: canonicalizes a relative path operand against the tool's REAL cwd;
#                     anchoring to the repo root would silently change a denylist decision.
EXEMPT_RE='/hooks/secrets-guard\.sh( |$)'

# Anchored shape: the first program (optionally after `bash `) is .../hooks/anchor-root.sh,
# followed by the real hook path.
ANCHOR_RE='^(bash )?[^ ]*/hooks/anchor-root\.sh [^ ]+'

# anchor_violations <json-file>: print one line per offending command, nothing when clean.
anchor_violations() {
  jq -r --arg anchor "$ANCHOR_RE" --arg exempt "$EXEMPT_RE" '
    [.hooks // {} | to_entries[] | .value[]? | .hooks[]? | .command // empty] | .[]
    | if test($exempt) then (if test($anchor) then "exempt-but-wrapped: \(.)" else empty end)
      elif test($anchor) then empty
      else "unwrapped: \(.)" end
  ' "$1"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-anchor-lint.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "=== anchor lint: the checker itself ==="
cat > "$TMP/bypass.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh ${CLAUDE_PLUGIN_ROOT}/hooks/slop-cleaner.sh"},
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/session-state-save.sh"},
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/secrets-guard.sh"}
]}]}}
EOF
OUT="$(anchor_violations "$TMP/bypass.json")"
if [ "$OUT" = 'unwrapped: ${CLAUDE_PLUGIN_ROOT}/hooks/session-state-save.sh' ]; then
  ok "fixture: flags exactly the one unwrapped entry"
else
  bad "fixture: flags exactly the one unwrapped entry (got: ${OUT:-nothing})"
fi

cat > "$TMP/exempt-wrapped.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"bash $HOME/.claude/dwarves-kit/hooks/anchor-root.sh $HOME/.claude/dwarves-kit/hooks/secrets-guard.sh"}
]}]}}
EOF
OUT="$(anchor_violations "$TMP/exempt-wrapped.json")"
case "$OUT" in
  exempt-but-wrapped:*) ok "fixture: flags a wrapped exempt entry" ;;
  *) bad "fixture: flags a wrapped exempt entry (got: ${OUT:-nothing})" ;;
esac

echo "=== anchor lint: the real dispatch tables ==="
for f in "$KIT_DIR/hooks/hooks.json" "$KIT_DIR/settings.json"; do
  name="${f#"$KIT_DIR"/}"
  N="$(jq '[.hooks // {} | to_entries[] | .value[]? | .hooks[]? | .command // empty] | length' "$f")"
  if [ "${N:-0}" -gt 0 ]; then ok "$name: has hook entries to check ($N)"; else bad "$name: has hook entries to check"; fi
  OUT="$(anchor_violations "$f")"
  if [ -z "$OUT" ]; then
    ok "$name: every entry routes through anchor-root.sh except the named exemption"
  else
    bad "$name: every entry routes through anchor-root.sh except the named exemption"
    printf '        %s\n' "$OUT"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

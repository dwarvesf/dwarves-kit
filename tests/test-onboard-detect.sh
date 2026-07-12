#!/usr/bin/env bash
# test-onboard-detect.sh -- SPEC-199, harness-loop sub-goal 09.
#
# Proves lib/onboard-detect.sh classifies all four install modes from a fixture $CLAUDE_DIR, is
# read-only, and does not misread an unrelated third-party hook as a bash install.
#
#   AC1 plugin-cache-only fixture           -> plugin
#   AC2 settings.json-with-kit-hooks fixture -> bash
#   AC3 both signals                         -> both
#   AC4 neither                              -> none
#   AC5 explain prints the mode word + a non-empty one-line explanation for each mode
#   AC6 NEGATIVE CONTROL: a settings.json with only an unrelated third-party hook is NOT `bash`
#   AC7 read-only: a run leaves the fixture $CLAUDE_DIR tree byte-identical
#
# Run: bash tests/test-onboard-detect.sh   (exit 0 = all AC green)
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="$KIT_DIR/lib/onboard-detect.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert_eq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }
assert_ne() { TOTAL=$((TOTAL+1)); if [ "$2" != "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (got the forbidden '$3')"; FAIL=$((FAIL+1)); fi; }
assert_nonempty() { TOTAL=$((TOTAL+1)); if [ -n "$2" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (empty)"; FAIL=$((FAIL+1)); fi; }

ROOT="$(mktemp -d -t onboard-detect.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

# --- fixture builders -------------------------------------------------------
# A plugin-cache fixture: the exact path install.sh:328 globs for.
make_plugin_cache() {  # $1 = CLAUDE_DIR
  mkdir -p "$1/plugins/cache/dwarves-marketplace/kit/2.0.0/lib"
}
# A bash-install fixture: settings.json with a dwarves-kit hook command.
make_bash_hooks() {  # $1 = CLAUDE_DIR
  mkdir -p "$1"
  cat > "$1/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/dwarves-kit/hooks/safety-gate.sh" } ] }
    ]
  }
}
EOF
}
# A settings.json with ONLY an unrelated third-party hook (no dwarves-kit).
make_thirdparty_hooks() {  # $1 = CLAUDE_DIR
  mkdir -p "$1"
  cat > "$1/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/some-other-tool/hooks/guard.sh" } ] }
    ]
  }
}
EOF
}

run_mode()    { CLAUDE_DIR="$1" bash "$DETECT" mode; }
run_explain() { CLAUDE_DIR="$1" bash "$DETECT" explain; }

echo "=== AC1: plugin-cache-only -> plugin ==="
D="$ROOT/plugin"; make_plugin_cache "$D"
assert_eq "plugin cache present, no settings.json -> plugin" "$(run_mode "$D")" "plugin"

echo ""
echo "=== AC2: settings.json with kit hooks -> bash ==="
D="$ROOT/bash"; make_bash_hooks "$D"
assert_eq "kit hooks in settings.json, no plugin cache -> bash" "$(run_mode "$D")" "bash"

echo ""
echo "=== AC3: both signals -> both ==="
D="$ROOT/both"; make_plugin_cache "$D"; make_bash_hooks "$D"
assert_eq "plugin cache AND kit hooks -> both (double-hook hazard)" "$(run_mode "$D")" "both"

echo ""
echo "=== AC4: neither -> none ==="
D="$ROOT/none"; mkdir -p "$D"
assert_eq "empty CLAUDE_DIR -> none" "$(run_mode "$D")" "none"

echo ""
echo "=== AC5: explain prints the mode word + a non-empty explanation ==="
for m in plugin bash both none; do
  case "$m" in
    plugin) D="$ROOT/plugin" ;;
    bash)   D="$ROOT/bash" ;;
    both)   D="$ROOT/both" ;;
    none)   D="$ROOT/none" ;;
  esac
  OUT="$(run_explain "$D")"
  WORD="$(printf '%s' "$OUT" | cut -f1)"
  EXPL="$(printf '%s' "$OUT" | cut -f2-)"
  assert_eq "explain $m: first field is the mode word" "$WORD" "$m"
  assert_nonempty "explain $m: one-line explanation is non-empty" "$EXPL"
done

echo ""
echo "=== AC6: NEGATIVE CONTROL -- unrelated third-party hook is NOT read as bash ==="
D="$ROOT/thirdparty"; make_thirdparty_hooks "$D"
assert_ne "a non-dwarves-kit hook in settings.json is not misread as bash" "$(run_mode "$D")" "bash"
assert_eq "...it reads as none (no kit signal at all)" "$(run_mode "$D")" "none"

echo ""
echo "=== AC7: read-only -- a run leaves the fixture tree byte-identical ==="
D="$ROOT/both"
before="$(find "$D" -type f | sort | xargs shasum 2>/dev/null | shasum | cut -d' ' -f1)"
run_mode "$D" >/dev/null; run_explain "$D" >/dev/null
after="$(find "$D" -type f | sort | xargs shasum 2>/dev/null | shasum | cut -d' ' -f1)"
assert_eq "detector wrote nothing under CLAUDE_DIR (tree hash unchanged)" "$before" "$after"

echo ""
echo "=== AC8: DRIFT PIN -- install.sh still carries both detection signals the helper mirrors ==="
INSTALL_SH="$KIT_DIR/install.sh"
RC=0; grep -q 'plugins/cache/dwarves-marketplace/kit' "$INSTALL_SH" || RC=1
assert_eq "install.sh still carries the plugin-cache glob signal (onboard-detect mirrors it)" "$RC" "0"
RC=0; grep -q 'dwarves-kit/hooks/' "$INSTALL_SH" || RC=1
assert_eq "install.sh still carries the dwarves-kit/hooks/ signal (onboard-detect mirrors it)" "$RC" "0"

echo ""
echo "=== AC9: NO HARDCODED ROSTER -- commands/onboard.md generates the module list from the registry ==="
ONBOARD_MD="$KIT_DIR/commands/onboard.md"
RC=0; grep -q 'bin/config" list' "$ONBOARD_MD" && grep -q 'modules\.' "$ONBOARD_MD" || RC=1
assert_eq "onboard.md drives 'bin/config list' + modules.* (roster generated from the registry)" "$RC" "0"
# A hardcoded roster would enumerate the install-only module keys. These four are module-specific
# tokens with no reason to appear in prose; their presence is the hardcoded-roster smell.
ROSTER_SMELL=0
for m in quiz_gate weekend_batch worktree cosmetic; do
  grep -qw "$m" "$ONBOARD_MD" && ROSTER_SMELL=$((ROSTER_SMELL+1))
done
assert_eq "onboard.md hardcodes no install-only module roster (0 of {quiz_gate,weekend_batch,worktree,cosmetic})" "$ROSTER_SMELL" "0"

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All onboard-detect tests passed.${NC}"
  exit 0
fi

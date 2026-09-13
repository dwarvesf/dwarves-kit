#!/usr/bin/env bash
# test-command-triggers.sh
#
# Skill selection runs on the description line. A bare one-liner description already lost
# every design and bug prompt to superpowers:brainstorming and superpowers:systematic-
# debugging. This test keeps the trigger phrases and the length in place.
#
# Run: bash tests/test-command-triggers.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$KIT_DIR/commands"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

echo "=== command-triggers ==="

check_desc() {  # file phrase1 phrase2
  local file="$COMMANDS_DIR/$1" line
  line="$(grep '^description:' "$file")"
  grep -qF -- "$2" <<<"$line"; assert "$1: description carries '$2'" $?
  grep -qF -- "$3" <<<"$line"; assert "$1: description carries '$3'" $?
  [ "${#line}" -gt 200 ]; assert "$1: description is longer than 200 characters" $?
}

check_desc think.md "thiết kế X" "superpowers:brainstorming"
check_desc design.md "thiết kế giải pháp" "superpowers:brainstorming"
check_desc debug.md "bị lỗi" "superpowers:systematic-debugging"

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]

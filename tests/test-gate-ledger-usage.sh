#!/usr/bin/env bash
# test-gate-ledger-usage.sh -- a bare or unknown `gate-ledger.sh` verb exits 64 and its usage
# text carries the argument signatures of start, record, override and debt, not only the verb list.
#
# Run: bash tests/test-gate-ledger-usage.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0
check() {
  if eval "$2"; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi
}

for args in "" "no-such-verb"; do
  label="${args:-bare}"
  # shellcheck disable=SC2086
  ERR="$(bash "$GL" $args 2>&1 >/dev/null)"; RC=$?
  check "$label: exits 64" '[ "$RC" -eq 64 ]'
  check "$label: keeps the verb list" 'printf "%s\n" "$ERR" | grep -q "^usage: gate-ledger.sh {required|start|record|"'
  check "$label: start signature" 'printf "%s\n" "$ERR" | grep -qF "start [--amend] <rid> <chosen-lane> <classified-lane> <chosen-type>"'
  check "$label: record signature" 'printf "%s\n" "$ERR" | grep -qF "record <rid> <phase> <ran|skipped> [reason]"'
  check "$label: override signature" 'printf "%s\n" "$ERR" | grep -qF "override <rid> <phase> <reason>"'
  check "$label: debt signature" 'printf "%s\n" "$ERR" | grep -qF "debt <rid> significance=<low|high> worthiness=<low|high> verdict="'
done

echo ""
echo "gate-ledger usage: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]

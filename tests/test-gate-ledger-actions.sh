#!/usr/bin/env bash
# `gate-ledger.sh actions <rid> <prefix> [--count]` reads back the ACTION lines a run wrote, so a
# loop (greenlight retries) can resume from the ledger instead of counting in context.
#
# Run: bash tests/test-gate-ledger-actions.sh   (exit 0 = all green)
set -uo pipefail
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got [$2] want [$3]"; fi; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
gl() { env DWARVES_KIT_LOG_DIR="$TMP/logs" bash "$GL" "$@"; }

gl action r1 greenlight-retry sha=aaa111 n=1 >/dev/null
gl action r1 greenlight-retry sha=aaa111 n=2 >/dev/null
gl action r1 greenlight-retry sha=bbb222 n=1 >/dev/null
gl action r1 "something else sha=aaa111" >/dev/null
gl record r1 build ran >/dev/null

eq "actions --count: one head sha" "$(gl actions r1 'greenlight-retry sha=aaa111' --count)" "2"
eq "actions --count: another head sha" "$(gl actions r1 'greenlight-retry sha=bbb222' --count)" "1"
eq "actions --count: a short prefix does not match a longer sha" "$(gl actions r1 'greenlight-retry sha=aaa' --count)" "0"
eq "actions --count: bare prefix counts all retries" "$(gl actions r1 greenlight-retry --count)" "3"
eq "actions: prints the matching action text in order" "$(gl actions r1 'greenlight-retry sha=aaa111')" $'greenlight-retry sha=aaa111 n=1\ngreenlight-retry sha=aaa111 n=2'
eq "actions: ignores GATE lines" "$(gl actions r1 build --count)" "0"
eq "actions --count: unknown rid is 0" "$(gl actions nope greenlight-retry --count)" "0"
eq "actions: unknown rid prints nothing" "$(gl actions nope greenlight-retry)" ""
gl actions r1 >/dev/null 2>&1; eq "actions without a prefix exits 64" "$?" "64"
USAGE="$(gl 2>&1)"
printf '%s\n' "$USAGE" | grep -qF 'actions <rid> <prefix> [--count]' && pass "usage lists the actions verb" || fail "usage does not list actions"

echo ""
[ "$FAILED" -eq 0 ] && echo "gate-ledger actions: all passed" || echo "gate-ledger actions: $FAILED failed"
[ "$FAILED" -eq 0 ]

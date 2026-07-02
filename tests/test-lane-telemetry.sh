#!/usr/bin/env bash
# test-lane-telemetry.sh -- SPEC-099, kit-telemetry SG-04.
# Pins the `render` routing-diagram subcommand: a seeded corpus renders the
# task-type -> lane -> gate table + flow + counts; the filter narrows; an empty
# corpus degrades gracefully (no crash, no fake zeros).
#
# Run: bash tests/test-lane-telemetry.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LT="$KIT_DIR/lib/lane-telemetry.sh"
GL="$KIT_DIR/lib/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }
has() { printf '%s' "$2" | grep -qF -- "$1"; }

# seeded corpus: a fixed DWARVES_KIT_LOG_DIR with three runs of distinct lane/type
export DWARVES_KIT_LOG_DIR="$(mktemp -d)/logs"
seed() {  # rid lane type
  bash "$GL" start "$1" "$2" "$2" "$3" "$3" testrepo >/dev/null 2>&1
  bash "$GL" record "$1" think ran x >/dev/null 2>&1
  bash "$GL" record "$1" build ran x >/dev/null 2>&1
}
seed r-full-a full spec-feature
seed r-full-b full eval
seed r-norm   normal doc

echo "=== lane-telemetry render (SPEC-099) ==="

OUT="$(NO_COLOR=1 bash "$LT" render 2>&1)"
has "Lane routing" "$OUT"; ok "render prints the routing header" $?
has "3 runs" "$OUT"; ok "render counts all seeded runs" $?
has "spec-feature" "$OUT"; ok "render shows a task-type row" $?
has "-> " "$OUT"; ok "render shows the type -> lane mapping" $?
has "routing flow" "$OUT"; ok "render draws the ASCII flow section" $?
has "gate coverage" "$OUT"; ok "render shows per-phase gate coverage" $?
# gate coverage counts both full runs' think = 2 (seeded think in all 3, so >=1)
has "think" "$OUT"; ok "render lists a covered gate phase" $?

# --- filter narrows to matching lane ---
OUTF="$(NO_COLOR=1 bash "$LT" render full 2>&1)"
has "filter=full" "$OUTF"; ok "render <filter> notes the active filter" $?
has "2 runs" "$OUTF"; ok "filter=full keeps only the 2 full-lane runs" $?
if has "normal" "$OUTF"; then ok "filter excludes the normal-lane run [NC]" 1; else ok "filter excludes the normal-lane run [NC]" 0; fi

# --- filter with no match ---
OUTN="$(NO_COLOR=1 bash "$LT" render nosuchlane 2>&1)"
has "no runs match" "$OUTN"; ok "filter with no match degrades gracefully" $?

# --- graceful-empty NEGATIVE CONTROL: empty/fresh LOG_DIR ---
OUTE="$(DWARVES_KIT_LOG_DIR="$(mktemp -d)/empty" NO_COLOR=1 bash "$LT" render 2>&1)"
has "no runs recorded" "$OUTE"; ok "empty corpus renders an honest 'no runs recorded' [NC]" $?
if printf '%s' "$OUTE" | grep -qiE 'error|not found|unbound|syntax'; then ok "empty render does not crash [NC]" 1; else ok "empty render does not crash [NC]" 0; fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

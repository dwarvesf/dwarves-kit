#!/usr/bin/env bash
# test-gate-ledger-amend.sh -- `gate-ledger.sh start --amend` may raise a run's lane, but lowering it needs
# `--lower --reason "<text>"`, which also logs a `GATE | lane-lower | override` line. Ship-gate keeps
# reading the last START-AMEND. Also pins the `review-verdict` reader the ship-gate cross-check uses.
#
# Run: bash tests/test-gate-ledger-amend.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
export DWARVES_KIT_LOG_DIR; DWARVES_KIT_LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
PASS=0; FAIL=0
check() {
  if eval "$2"; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi
}
gl() { bash "$GL" "$@"; }
log() { cat "$DWARVES_KIT_LOG_DIR/runs/$1.log" 2>/dev/null; }
eff() { log "$1" | grep -E '\| START(-AMEND)? \|' | tail -1 | sed -nE 's/.*lane=([a-z-]+).*/\1/p'; }
fresh() { gl start "$1" "$2" "$2" feature feature r >/dev/null 2>&1; }   # rid lane

echo "raising a lane stays free"
fresh up1 tiny
gl start --amend up1 normal tiny feature feature r >/dev/null 2>&1; RC=$?
check "tiny -> normal: accepted" '[ "$RC" -eq 0 ] && [ "$(eff up1)" = normal ]'
gl start --amend up1 full tiny feature feature r >/dev/null 2>&1; RC=$?
check "normal -> full: accepted" '[ "$RC" -eq 0 ] && [ "$(eff up1)" = full ]'
check "a raise logs no lane-lower line" '! log up1 | grep -q "lane-lower"'
gl start --amend up1 full tiny feature feature r >/dev/null 2>&1; RC=$?
check "same lane again: accepted" '[ "$RC" -eq 0 ]'

echo "lowering is refused without --lower"
fresh lo1 full
ERR="$(gl start --amend lo1 tiny full feature feature r 2>&1 >/dev/null)"; RC=$?
check "full -> tiny: exit 65" '[ "$RC" -eq 65 ]'
check "the refusal names --lower and --reason" 'printf "%s" "$ERR" | grep -q -- "--lower" && printf "%s" "$ERR" | grep -q -- "--reason"'
check "the refusal writes nothing (effective lane stays full)" '[ "$(eff lo1)" = full ] && [ "$(log lo1 | grep -c START)" -eq 1 ]'
gl start --amend lo1 normal full feature feature r >/dev/null 2>&1; RC=$?
check "full -> normal: exit 65" '[ "$RC" -eq 65 ] && [ "$(eff lo1)" = full ]'
gl start --amend lo1 bug full feature feature r >/dev/null 2>&1; RC=$?
check "full -> bug: exit 65 (bug sits at normal's rank)" '[ "$RC" -eq 65 ] && [ "$(eff lo1)" = full ]'
fresh lo2 normal
gl start --amend lo2 tiny normal feature feature r >/dev/null 2>&1; RC=$?
check "normal -> tiny: exit 65" '[ "$RC" -eq 65 ] && [ "$(eff lo2)" = normal ]'
fresh lo3 tiny
gl start --amend lo3 normal tiny feature feature r >/dev/null 2>&1
gl start --amend lo3 tiny tiny feature feature r >/dev/null 2>&1; RC=$?
check "the last AMEND is the baseline: normal -> tiny refused even though the first START was tiny" '[ "$RC" -eq 65 ] && [ "$(eff lo3)" = normal ]'

echo "lowering with --lower --reason"
gl start --amend --lower lo1 tiny full feature feature r >/dev/null 2>&1; RC=$?
check "--lower without --reason: exit 64, nothing written" '[ "$RC" -eq 64 ] && [ "$(eff lo1)" = full ]'
gl start --amend --lower --reason "" lo1 tiny full feature feature r >/dev/null 2>&1; RC=$?
check "--lower with an empty reason: exit 64" '[ "$RC" -eq 64 ] && [ "$(eff lo1)" = full ]'
gl start --amend --lower --reason "spike turned out docs only" lo1 tiny full feature feature r >/dev/null 2>&1; RC=$?
check "full -> tiny with --lower --reason: accepted" '[ "$RC" -eq 0 ] && [ "$(eff lo1)" = tiny ]'
check "an override-style line records from, to and the reason" 'log lo1 | grep -qE "\| GATE \| lane-lower \| override \| full -> tiny: spike turned out docs only$"'
check "the START-AMEND follows the override line (ship-gate keeps reading the last START-AMEND)" '[ "$(log lo1 | tail -1 | cut -d"|" -f2 | tr -d " ")" = START-AMEND ]'
gl start --amend --reason "why not" --lower lo2 tiny normal feature feature r >/dev/null 2>&1; RC=$?
check "flags in either order" '[ "$RC" -eq 0 ] && [ "$(eff lo2)" = tiny ]'
fresh lo4 full
gl start --amend --lower --reason "lateral check" lo4 full full feature feature r >/dev/null 2>&1
check "--lower on a non-lowering amend logs no lane-lower line" '! log lo4 | grep -q lane-lower'
gl start --lower --reason x lo5 tiny tiny feature feature r >/dev/null 2>&1; RC=$?
check "--lower on a plain start: exit 64" '[ "$RC" -eq 64 ]'

echo "the special lanes and unknown lanes"
fresh sp1 bug
gl start --amend sp1 backfill bug feature feature r >/dev/null 2>&1; RC=$?
check "bug -> backfill: accepted (same rank)" '[ "$RC" -eq 0 ] && [ "$(eff sp1)" = backfill ]'
gl start --amend sp1 normal bug feature feature r >/dev/null 2>&1; RC=$?
check "backfill -> normal: accepted (same rank)" '[ "$RC" -eq 0 ] && [ "$(eff sp1)" = normal ]'
fresh sp2 tiny
gl start --amend sp2 bug tiny feature feature r >/dev/null 2>&1; RC=$?
check "tiny -> bug: accepted (a raise)" '[ "$RC" -eq 0 ] && [ "$(eff sp2)" = bug ]'
fresh sp3 full
gl start --amend sp3 customlane full feature feature r >/dev/null 2>&1
check "a lane with no rank is not guarded (old rule)" '[ "$(eff sp3)" = customlane ]'

echo "a ledger with no START line"
gl record nostart1 build ran ok >/dev/null 2>&1
gl start --amend nostart1 tiny tiny feature feature r >/dev/null 2>&1; RC=$?
check "amend with nothing to lower from: accepted" '[ "$RC" -eq 0 ] && [ "$(eff nostart1)" = tiny ]'

echo "review-verdict reads the last parseable review record"
gl record rv1 review ran "SHIP findings=0 rejected=0 actor=t" >/dev/null 2>&1
check "SHIP" '[ "$(gl review-verdict rv1)" = "SHIP" ]'
gl record rv1 review ran "FIX THEN SHIP findings=2 rejected=0 actor=t" >/dev/null 2>&1
check "the last record wins: FIX THEN SHIP" '[ "$(gl review-verdict rv1)" = "FIX THEN SHIP" ]'
gl record rv1 review ran "DO NOT SHIP findings=5 suppressed=0 rejected=0 actor=t" >/dev/null 2>&1
check "DO NOT SHIP" '[ "$(gl review-verdict rv1)" = "DO NOT SHIP" ]'
gl record rv1 review ran "ok" >/dev/null 2>&1
check "an unparseable later record does not clear the verdict" '[ "$(gl review-verdict rv1)" = "DO NOT SHIP" ]'
gl override rv1 review "reviewed by hand" >/dev/null 2>&1
check "an override is not a verdict" '[ "$(gl review-verdict rv1)" = "DO NOT SHIP" ]'
gl record rv2 battery ran "SHIP arms=3 caught=1" >/dev/null 2>&1
check "battery records count (battery normalizes to the review gate)" '[ "$(gl review-verdict rv2)" = "SHIP" ]'
gl record rv3 review ran "DO-NOT-SHIP findings=1" >/dev/null 2>&1
check "hyphenated spelling reads the same" '[ "$(gl review-verdict rv3)" = "DO NOT SHIP" ]'
gl record rv4 review ran "SHIPPED findings=0" >/dev/null 2>&1
check "SHIPPED is not SHIP" '[ -z "$(gl review-verdict rv4)" ]'
check "no ledger: prints nothing, exits 0" '[ -z "$(gl review-verdict no-such-run)" ] && gl review-verdict no-such-run >/dev/null 2>&1'

echo ""
echo "gate-ledger amend: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]

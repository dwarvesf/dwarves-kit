#!/usr/bin/env bash
# test-gate-ledger-override-via.sh -- every `GATE | <phase> | override` row names its writer in a
# trailing ` | via=<source>` field: hand (the override verb), plan (plan-record), batch
# (record-batch), inherit (inherit), lane-lower (start --amend --lower). The reason stays the
# fifth field, the duplicate-reason guard ignores the tag, and ran/skipped/rejected rows carry none.
#
# Run: bash tests/test-gate-ledger-override-via.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
CONFORM="$KIT_DIR/lib/stats/tests/lib/conform.sh"
# Pin the operator config layer so a real ~/.config/dwarves-kit never reaches the resolver.
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
export DWARVES_KIT_LOG_DIR; DWARVES_KIT_LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$DWARVES_KIT_LOG_DIR" 2>/dev/null' EXIT
PASS=0; FAIL=0
check() {
  if eval "$2"; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi
}
gl() { bash "$GL" "$@"; }
log() { cat "$DWARVES_KIT_LOG_DIR/runs/$1.log" 2>/dev/null; }
# The override row for a phase, whole line.
orow() { log "$1" | grep -F "| GATE | $2 | override |" | tail -1; }

echo "hand: the override verb"
gl override h1 spec "small spec, post-build review covers it" >/dev/null 2>&1; RC=$?
check "exit 0" '[ "$RC" -eq 0 ]'
check "row ends in | via=hand" '[[ "$(orow h1 spec)" == *"| override | small spec, post-build review covers it | via=hand" ]]'
check "reason is still field 5" '[ "$(orow h1 spec | awk -F" [|] " "{print \$5}")" = "small spec, post-build review covers it" ]'
check "row passes the ledger-event conform contract" '[[ "$(bash "$CONFORM" check "$(orow h1 spec)")" == "PASS GATE" ]]'
gl override h1 design "design lives in the spec" >/dev/null 2>&1
check "a second hand override tags itself too" '[[ "$(orow h1 design)" == *"| via=hand" ]]'

echo "hand: a typed via cannot forge another source"
gl override h2 spec "note | via=plan" >/dev/null 2>&1
check "one via field only, and it is hand" '[ "$(orow h2 spec | grep -o "via=[a-z-]*" | tr "\n" " ")" = "via=hand " ]'

echo "guard: the same reason on a different phase is still refused"
gl override h3 spec "pasted reason" >/dev/null 2>&1
gl override h3 design "pasted reason" >/dev/null 2>&1; RC=$?
check "exit 65" '[ "$RC" -eq 65 ]'
check "design row not written" '[ -z "$(orow h3 design)" ]'
gl override h3 spec "pasted reason" >/dev/null 2>&1; RC=$?
check "same phase, same reason: accepted (idempotent re-run)" '[ "$RC" -eq 0 ]'

echo "plan: plan-record --override"
gl plan-record p1 normal --skipped grill:"reason=home-turf: known area" --ran think --override spec:"wrote it in the PR" \
  --ran validate --ran design-record --skipped test-plan:"prose" --ran build --ran review --ran docs >/dev/null 2>&1; RC=$?
check "exit 0" '[ "$RC" -eq 0 ]'
check "row ends in | via=plan" '[[ "$(orow p1 spec)" == *"| override | wrote it in the PR | via=plan" ]]'
check "ran and skipped rows carry no via" '! log p1 | grep -E "\| GATE \| [a-z-]+ \| (ran|skipped) \|" | grep -q "via="'

echo "batch: record-batch"
gl record-batch b1 normal --evidence-default "ran elsewhere" grill=skipped:"reason=home-turf: known area" think=ran spec=override:"spec in the PR" \
  validate=ran design-record=ran test-plan=skipped:"prose" build=ran review=ran docs=ran ship=ran >/dev/null 2>&1; RC=$?
check "exit 0" '[ "$RC" -eq 0 ]'
check "row ends in | via=batch" '[[ "$(orow b1 spec)" == *"| override | spec in the PR | via=batch" ]]'

echo "inherit: inherit --from"
for ph in think design design-critique spec validate design-record test-plan; do gl record parent1 "$ph" ran fixture >/dev/null 2>&1; done
gl inherit c1 full --from parent1 >/dev/null 2>&1; RC=$?
check "exit 0" '[ "$RC" -eq 0 ]'
check "every inherited row ends in | via=inherit" '[ "$(log c1 | grep -c "| override | inherited from parent1: .* | via=inherit$")" -eq 7 ]'
gl inherit c1 full --from parent1 >/dev/null 2>&1; RC=$?
check "re-running skips the written rows (token match survives the suffix)" '[ "$RC" -eq 0 ] && [ "$(log c1 | grep -c "| GATE |")" -eq 7 ]'

echo "lane-lower: start --amend --lower"
gl start l1 full full feature feature r >/dev/null 2>&1
gl start --amend --lower --reason "scope shrank" l1 tiny full feature feature r >/dev/null 2>&1; RC=$?
check "exit 0" '[ "$RC" -eq 0 ]'
check "row ends in | via=lane-lower" '[[ "$(orow l1 lane-lower)" == *"| override | full -> tiny: scope shrank | via=lane-lower" ]]'

echo "readers: check() still decides on the override row"
gl override ck1 spec "ok reason" >/dev/null 2>&1
check "an override with a via field satisfies a required gate" '! bash "$GL" check normal ck1 2>&1 | grep -q "MISSING-GATE: spec"'

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]

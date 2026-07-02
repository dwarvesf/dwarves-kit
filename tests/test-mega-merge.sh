#!/usr/bin/env bash
# test-mega-merge.sh -- SPEC-100, kit-telemetry SG-05.
# Pins the CODE-LEVEL gate/held-final exclusion in lib/mega-merge.sh: a gate-tagged /
# held-final / draft PR is refused at the code level even when the prompt-level rule is
# absent, unreadable state fails closed, and a normal `auto` PR still merges.
#
# Fully offline: gate-ledger + PR-state are injected (MEGA_MERGE_GATE_LEDGER,
# MEGA_MERGE_PR_INFO_CMD), so no `gh` and no real gate ledger are touched.
#
# Run: bash tests/test-mega-merge.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MM="$KIT_DIR/lib/mega-merge.sh"
US=$'\037'

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }
has() { printf '%s' "$2" | grep -qF -- "$1"; }

TMP="$(mktemp -d)"
# injected gate-ledger stubs: one that passes, one that fails
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/gl-pass"; chmod +x "$TMP/gl-pass"
printf '#!/usr/bin/env bash\necho "MISSING-GATE: build" >&2\nexit 1\n' > "$TMP/gl-fail"; chmod +x "$TMP/gl-fail"
# injected PR-state: pr number selects the scenario
cat > "$TMP/prinfo" <<SH
#!/usr/bin/env bash
US=\$'\\037'
case "\$1" in
  1) printf 'false%senhancement%snormal feature PR\\n' "\$US" "\$US" ;;   # clear
  2) printf 'false%sdo-not-merge%sheld final PR\\n' "\$US" "\$US" ;;      # hold label
  3) printf 'true%s%sdraft wip\\n' "\$US" "\$US" ;;                       # draft
  4) printf 'false%s%s[HOLD] gated final\\n' "\$US" "\$US" ;;             # title marker
  5) exit 1 ;;                                                            # unreadable
  6) printf 'false%sci-red,gated-final%smixed labels\\n' "\$US" "\$US" ;; # hold among others
esac
SH
chmod +x "$TMP/prinfo"
export MEGA_MERGE_PR_INFO_CMD="$TMP/prinfo"

run() { MEGA_MERGE_GATE_LEDGER="$1" bash "$MM" merge "$2" somerid full 2>&1; }

echo "=== mega-merge exclusion (SPEC-100 AC1-AC6) ==="

# AC1 [positive control]: a clear, gate-passing PR still merges (dry-run reaches the merge cmd).
O1="$(run "$TMP/gl-pass" 1)"; R1=$?
has "gh pr merge 1" "$O1"; ok "AC1: normal auto PR (clear + gate pass) still merges (dry-run)" $?
ok "AC1: exit 0 for a mergeable PR" $([ "$R1" -eq 0 ] && echo 0 || echo 1)

# AC2 [NC]: a hold-labelled PR is refused even with a PASSING gate.
O2="$(run "$TMP/gl-pass" 2)"; R2=$?
has "BLOCKED" "$O2"; ok "AC2 [NC]: hold-label PR refused" $?
has "hold label" "$O2"; ok "AC2: refusal names the hold label" $?
ok "AC2: exit nonzero" $([ "$R2" -ne 0 ] && echo 0 || echo 1)

# AC3 [NC]: a draft PR is refused.
O3="$(run "$TMP/gl-pass" 3)"
has "is a draft" "$O3"; ok "AC3 [NC]: draft PR refused" $?

# AC4 [NC]: a bracketed-title-marker PR is refused.
O4="$(run "$TMP/gl-pass" 4)"
has "title carries a hold marker" "$O4"; ok "AC4 [NC]: title-marker PR refused" $?

# AC5 [NC, fail-closed]: unreadable PR state is refused with a reason (never merged on doubt).
O5="$(run "$TMP/gl-pass" 5)"; R5=$?
has "cannot read PR" "$O5"; ok "AC5 [NC]: unclassifiable PR refused (fail-closed)" $?
ok "AC5: exit nonzero" $([ "$R5" -ne 0 ] && echo 0 || echo 1)
if has "gh pr merge" "$O5"; then ok "AC5: never prints a merge command for an unreadable PR" 1; else ok "AC5: never prints a merge command for an unreadable PR" 0; fi

# AC6: a hold label among others still blocks (not just a solo label).
O6="$(run "$TMP/gl-pass" 6)"
has "gated-final" "$O6"; ok "AC6: hold label detected among multiple labels" $?

# AC7 [gate still enforced]: a CLEAR PR with a FAILING gate is still blocked (exclusion did
# not bypass the ship-gate). Exclusion is checked first, but a clear PR then hits the gate.
O7="$(run "$TMP/gl-fail" 1)"
has "ship-gate not satisfied" "$O7"; ok "AC7: clear PR + failing gate still blocked by the gate" $?

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# test-ledger-durability.sh -- SPEC-097, kit-telemetry SG-01.
# Validates that run telemetry survives a plugin reinstall (durable XDG path + additive
# migration) and that per-gate override reasons are enforced (blanket overrides rejected).
#
# Isolation: every case runs the real libs under a FAKE $HOME + $XDG_STATE_HOME with
# DWARVES_KIT_LOG_DIR unset, so the resolver picks the durable default and migration runs
# from a seeded fake legacy -- the real machine corpus is never touched.
#
# Run: bash tests/test-ledger-durability.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate-ledger.sh"
LT="$KIT_DIR/lib/lane-telemetry.sh"
LC="$KIT_DIR/lib/lane-classify.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

# a fresh isolated environment: $1=name of exported HOME var not needed; sets HOME/XDG
new_env() {
  HH="$(mktemp -d)"; XX="$(mktemp -d)/state"
  LEGACY="$HH/.claude/dwarves-kit/logs"
  DURABLE="$XX/dwarves-kit/logs"
  mkdir -p "$LEGACY/runs"
}
# run a lib with the fake env and DWARVES_KIT_LOG_DIR unset
run() { env -u DWARVES_KIT_LOG_DIR HOME="$HH" XDG_STATE_HOME="$XX" bash "$@"; }

echo "=== ledger-durability (SPEC-097 AC1-AC8) ==="

# --- AC1: durable default is XDG state, not ~/.claude/dwarves-kit ---
new_env
run "$GL" record durrun think ran "seed" >/dev/null 2>&1
[ -f "$DURABLE/runs/durrun.log" ]; assert "AC1: record writes under XDG durable path" $?
[ ! -f "$LEGACY/runs/durrun.log" ]; assert "AC1: record does NOT write under ~/.claude blast zone" $?

# --- AC2 + AC8: seeded legacy corpus migrates in additively ---
new_env
for f in kit-harden-01-eff-val kit-harden-08-megamirror plugin-native-operate-contract; do
  echo "2026 | START | lane=full classified=full type=spec-feature repo=dwarves-kit" > "$LEGACY/runs/$f.log"
done
echo "2026 | LANE-CHECK | x" > "$LEGACY/completeness.log"
run "$GL" record migrun build ran "trigger migrate" >/dev/null 2>&1
MIG_OK=0
for f in kit-harden-01-eff-val kit-harden-08-megamirror plugin-native-operate-contract; do
  [ -f "$DURABLE/runs/$f.log" ] || MIG_OK=1
done
assert "AC2/AC8: seeded kit-harden corpus present at durable path after migration" $MIG_OK
[ -d "$LEGACY" ]; assert "AC2: legacy dir left intact (migration is additive)" $?
[ -f "$DURABLE/completeness.log" ]; assert "AC8: completeness.log migrated too" $?

# --- AC3: survive-reinstall NEGATIVE CONTROL ---
# wipe the legacy dir (simulated plugin reinstall) -- data must remain readable at durable.
rm -rf "$HH/.claude/dwarves-kit"
REP="$(run "$LT" report 2>/dev/null)"; MIS="$(run "$LT" misfires 2>/dev/null)"
[ ! -d "$HH/.claude/dwarves-kit" ]; assert "AC3 [NC]: legacy dir is gone (reinstall simulated)" $?
printf '%s%s' "$REP" "$MIS" | grep -q "." ; assert "AC3 [NC]: lane-telemetry still reads records after the wipe" $?
[ -f "$DURABLE/runs/kit-harden-01-eff-val.log" ]; assert "AC3 [NC]: migrated corpus survives the wipe" $?

# --- AC4: migration idempotent + non-clobber ---
new_env
echo "OLD-CONTENT" > "$LEGACY/runs/clash.log"
run "$GL" record c1 think ran x >/dev/null 2>&1     # first access migrates + drops sentinel
echo "NEW-CONTENT" > "$DURABLE/runs/clash.log"       # durable copy diverges
run "$GL" record c2 think ran x >/dev/null 2>&1     # second access must NOT re-copy
grep -q "NEW-CONTENT" "$DURABLE/runs/clash.log"; assert "AC4: second migrate does not clobber a durable file" $?
[ -f "$DURABLE/.migrated" ]; assert "AC4: .migrated sentinel present" $?

# --- AC5: env override honored, and migration does NOT pull the seeded/real corpus ---
new_env
echo "2026 | START | x" > "$LEGACY/runs/should-not-migrate.log"
EXPLICIT="$(mktemp -d)/explicit"
env HOME="$HH" XDG_STATE_HOME="$XX" DWARVES_KIT_LOG_DIR="$EXPLICIT" bash "$GL" record e1 think ran x >/dev/null 2>&1
[ -f "$EXPLICIT/runs/e1.log" ]; assert "AC5: explicit DWARVES_KIT_LOG_DIR is honored" $?
[ ! -f "$EXPLICIT/runs/should-not-migrate.log" ]; assert "AC5: env-set path does NOT ingest legacy corpus" $?

# --- B1: lane-classify downgrade writer lands where lane-telemetry reads (no split-brain) ---
new_env
run "$LC" check normal "add auth and a data-model migration to the audit-security path" >/dev/null 2>&1 || true
grep -q "LANE-CHECK" "$DURABLE/completeness.log" 2>/dev/null; assert "B1: lane-classify downgrade writes to the durable completeness.log" $?
[ ! -f "$LEGACY/completeness.log" ]; assert "B1: downgrade does NOT write the legacy path (no split-brain vs the migrated reader)" $?

# --- AC6: blanket override rejected; distinct reason passes ---
export DWARVES_KIT_LOG_DIR="$(mktemp -d)/ov"
bash "$GL" override ov think "shared blanket reason" >/dev/null 2>&1; assert "AC6: first override accepted" $?
bash "$GL" override ov design "shared blanket reason" >/dev/null 2>&1
[ $? -eq 65 ]; assert "AC6: blanket override (same reason, other gate) rejected exit 65" $?
bash "$GL" override ov design "a distinct design reason" >/dev/null 2>&1; assert "AC6: distinct per-gate reason accepted" $?

# --- AC7: idempotent same-phase override allowed ---
bash "$GL" override ov think "shared blanket reason" >/dev/null 2>&1; assert "AC7: re-applying the same reason to the SAME gate is allowed" $?
unset DWARVES_KIT_LOG_DIR

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

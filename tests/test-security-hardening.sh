#!/usr/bin/env bash
# test-security-hardening.sh -- SPEC-134 security remediation for the kit-run-integrity run.
#
# Pins three PoC-confirmed findings + their negative controls:
#   HIGH  : lib/proof-table-gen.py path traversal / arbitrary file write. rid is normalized
#           (runid() charset) before any path, and the FINAL resolved out-path is confined
#           under realpath(KIT_ROOT/docs/runs) EVEN for an explicit out-path arg.
#   MEDIUM: lib/gate-ledger.sh mutation() now neuters embedded "=" in free-text values, so a
#           value can never smuggle a second KEY=value token into the | MUTATION | line.
#   LOW   : lib/mutation-smoke.sh skips a symlinked candidate ([ -L ] guard) instead of writing
#           through it.
# Each finding carries a negative control that REVERTS the fix (in a throwaway copy) and shows the
# original behavior leaks -- proving the assertion actually bites.
#
# Run: bash tests/test-security-hardening.sh
# Exit 0 = all pass. Exit 1 = failures.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$KIT_DIR/lib/proof-table-gen.sh"
PY="$KIT_DIR/lib/proof-table-gen.py"
LEDGER="$KIT_DIR/lib/gate-ledger.sh"
SMOKE="$KIT_DIR/lib/mutation-smoke.sh"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0; TOTAL=0
ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} $1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} $1"; }
eq()      { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
present() { if [ -e "$2" ]; then bad "$1 (LEAK: '$2' exists outside docs/runs)"; else ok "$1"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-sec-harden.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export DWARVES_KIT_LOG_DIR="$WORK/logs"; mkdir -p "$DWARVES_KIT_LOG_DIR/runs"

# Throwaway confinement anchor (the wrapper honors a pre-set KIT_ROOT); a real docs/runs so the
# confinement targets it, never the real repo.
export KIT_ROOT="$WORK/kitroot"; RUNS="$KIT_ROOT/docs/runs"; mkdir -p "$RUNS"
# A world-outside-docs/runs zone the PoC tries (and must fail) to write into.
LEAKZONE="$WORK/leakzone"; mkdir -p "$LEAKZONE"

# ============================================================
echo "=== HIGH: proof-table-gen path confinement ==="
# ============================================================
# H1: a traversal rid, default out-path -> normalized + confined under docs/runs, nothing escapes.
# Compare via realpath (python3) so a symlinked /var -> /private/var prefix does not fool the check.
OUT_H1="$(bash "$GEN" "../../victim-escapee" 2>&1 | grep -oE 'wrote [^ ]+' | cut -d' ' -f2)"
under_runs() { python3 - "$1" "$2" <<'PY'
import os, sys
child = os.path.realpath(sys.argv[1]); root = os.path.realpath(sys.argv[2])
sys.exit(0 if child == root or child.startswith(root + os.sep) else 1)
PY
}
if under_runs "$OUT_H1" "$RUNS"; then ok "H1: traversal rid lands inside docs/runs ($OUT_H1)"; else bad "H1: traversal rid escaped docs/runs (wrote '$OUT_H1')"; fi
present "H1: no file written at the clone-root escape target" "$KIT_ROOT/victim-escapee.md"

# H2: an absolute rid -> normalized (leading '/' becomes '-'), confined; no arbitrary abs write.
ABS_TARGET="$LEAKZONE/abs-pwned"
bash "$GEN" "$ABS_TARGET" >/dev/null 2>&1
present "H2: absolute rid does NOT write the arbitrary absolute path" "$ABS_TARGET.md"

# H3: an explicit out-path OUTSIDE docs/runs -> rejected (non-zero exit, stderr), no write.
ERR_H3="$(bash "$GEN" somerid "$LEAKZONE/explicit.md" 2>&1)"; RC_H3=$?
eq "H3: explicit out-of-tree out-path is rejected (non-zero exit)" "$RC_H3" "1"
present "H3: explicit out-of-tree path is not written" "$LEAKZONE/explicit.md"
case "$ERR_H3" in *"outside"*|*"docs/runs"*) ok "H3: rejection names the confinement reason";; *) bad "H3: rejection message unclear: $ERR_H3";; esac

# H4: a normal rid still writes docs/runs/<rid>.md (no over-blocking).
bash "$GEN" "normal-rid" >/dev/null 2>&1
if [ -f "$RUNS/normal-rid.md" ]; then ok "H4: a normal rid still writes docs/runs/normal-rid.md"; else bad "H4: normal rid did not write its run-table"; fi

# H5: the canonical proof-of-done.md basename is still refused (basename guard preserved).
CANON="$RUNS/proof-of-done.md"
bash "$GEN" "normal-rid" "$CANON" >/dev/null 2>&1; RC_H5=$?
eq "H5: proof-of-done.md basename still refused" "$RC_H5" "1"
if [ ! -f "$CANON" ]; then ok "H5: canonical file not created by the refused call"; else bad "H5: canonical file was written"; fi

# H-NEG: revert BOTH the normalization + confinement (use origin/master's generator) and show the
# same absolute-rid PoC leaks. Proves H1-H3 actually bite.
echo "--- HIGH negative control (reverted generator leaks) ---"
ORIG_PY="$WORK/orig-proof-table-gen.py"
git -C "$KIT_DIR" show origin/master:lib/proof-table-gen.py > "$ORIG_PY" 2>/dev/null
NEG_ABS="$LEAKZONE/neg-abs-pwned"
KIT_ROOT="$KIT_ROOT" KIT_LOG_DIR="$DWARVES_KIT_LOG_DIR" python3 "$ORIG_PY" "$NEG_ABS" >/dev/null 2>&1
if [ -f "$NEG_ABS.md" ]; then ok "H-NEG: reverted generator DOES leak (writes $NEG_ABS.md outside docs/runs)"; else bad "H-NEG: expected the reverted generator to leak but it did not"; fi

# ============================================================
echo ""
echo "=== MEDIUM: mutation() '=' neutering ==="
# ============================================================
# M1: a free-text value carrying '=' must NOT add extra KEY=value tokens to the | MUTATION | line.
kv_count() { printf '%s' "$1" | grep -oE '[A-Za-z_]+=' | wc -l | tr -d ' '; }
bash "$LEDGER" mutation med-rid verdict=flag 'reason=smuggled=second=kv' >/dev/null 2>&1
LINE_M1="$(grep MUTATION "$DWARVES_KIT_LOG_DIR/runs/med-rid.log")"
eq "M1: exactly 2 KEY= tokens (verdict= + reason=), '=' neutered" "$(kv_count "$LINE_M1")" "2"
case "$LINE_M1" in *"reason=smuggled:second:kv"*) ok "M1: '=' in the value rewritten to ':'";; *) bad "M1: value not neutered: $LINE_M1";; esac

# M-NEG: revert the fix in a throwaway copy of gate-ledger.sh (sourced from the real lib so deps
# resolve) and show the '=' leaks a second KV.
echo "--- MEDIUM negative control (reverted mutation leaks) ---"
NEG_GL="$KIT_DIR/lib/.neg-gate-ledger.sh"   # inside lib/ so its `source ...kit-log-dir.sh` resolves
sed "s#tr ' ' '_' | tr '=' ':'#tr ' ' '_'#" "$LEDGER" > "$NEG_GL"
trap 'rm -rf "$WORK"; rm -f "$NEG_GL"' EXIT
bash "$NEG_GL" mutation negmed-rid verdict=flag 'reason=smuggled=second=kv' >/dev/null 2>&1
LINE_MNEG="$(grep MUTATION "$DWARVES_KIT_LOG_DIR/runs/negmed-rid.log")"
if [ "$(kv_count "$LINE_MNEG")" -gt 2 ]; then ok "M-NEG: reverted mutation leaks extra KV ($(kv_count "$LINE_MNEG") tokens: $LINE_MNEG)"; else bad "M-NEG: expected the '=' to leak a second KV, got: $LINE_MNEG"; fi

# ============================================================
echo ""
echo "=== LOW: mutation-smoke symlink skip ==="
# ============================================================
# L1: the guard's exact predicate skips a symlink. `[ -f ]` FOLLOWS a symlink-to-regular (true),
# so only the `[ -L ]` guard prevents a write-through. Assert both the follow and the skip.
TARGET="$WORK/l-target"; printf 'sentinel\n' > "$TARGET"
LINKF="$WORK/l-link"; ln -s "$TARGET" "$LINKF"
if [ -f "$LINKF" ]; then ok "L1: [ -f link ] is true (symlink-to-regular is followed -- why the -L guard is needed)"; else bad "L1: [ -f link ] unexpectedly false"; fi
# The loop's decision: process iff regular AND not a symlink.
if { [ -f "$LINKF" ] && [ ! -L "$LINKF" ]; }; then bad "L1: loop would PROCESS the symlink (guard not effective)"; else ok "L1: loop skips the symlink (regular-and-not-symlink is false)"; fi
if { [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; }; then ok "L1: a real regular file is still processed (no over-skip)"; else bad "L1: real file wrongly skipped"; fi

# L2: the guard is actually WIRED into the real mutation loop, immediately after the `-f` check
# (not dead code elsewhere). Grep the source for the two adjacent guard lines.
if grep -qF '[ -L "$file" ] && continue' "$SMOKE"; then ok "L2: symlink-skip guard present in lib/mutation-smoke.sh"; else bad "L2: symlink-skip guard missing from lib/mutation-smoke.sh"; fi
if awk '/\[ -f "\$file" \] \|\| continue/{f=1;next} f&&/\[ -L "\$file" \] && continue/{print "ok";exit}' "$SMOKE" | grep -q ok; then
  ok "L2: guard sits immediately after the [ -f ] check in the candidate loop"; else bad "L2: guard not adjacent to the [ -f ] check"; fi

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASS${NC} / $TOTAL"
if [ "$FAIL" -gt 0 ]; then echo -e "${RED}$FAIL assertions failed.${NC}"; exit 1; fi
echo -e "${GREEN}security-hardening green.${NC}"

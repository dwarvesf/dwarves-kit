#!/usr/bin/env bash
# test-gate-ledger-check-cache.sh -- `gate-ledger.sh check` caches its verdict per ledger in
# $LOG_DIR/.gate-check.cache (key: ledger size+mtime+inode under a lane-data + gate-script
# fingerprint). Pins: warm output and exit code equal the cold computation for every lane and
# ledger shape; each invalidation input flips the result; a corrupt cache never changes the answer.
#
# Isolation: a shim copy of lib/ + kit.toml (so a case can edit gate-ledger.sh and kit.toml) under a
# fresh DWARVES_KIT_LOG_DIR; the real machine corpus and the repo files are never touched.
#
# Run: bash tests/test-gate-ledger-check-cache.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok() { if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

TD="$(mktemp -d)"
trap 'rm -rf "$TD"' EXIT
SH="$TD/shim"; mkdir -p "$SH"
cp -R "$KIT_DIR/lib" "$SH/lib"; cp "$KIT_DIR/kit.toml" "$SH/kit.toml"
GLS="$SH/lib/gate/gate-ledger.sh"
CW="$TD/cwd"; mkdir -p "$CW"          # not a git repo: no project .kit.toml
OPD="$TD/op"; mkdir -p "$OPD"
LOGD="$TD/logs"; mkdir -p "$LOGD/runs"
CACHE="$LOGD/.gate-check.cache"
OLD=202601010000                       # an mtime well past the 2 s write guard

# chk <check args...>: runs check, leaves exit code in RC and the stdout+stderr bytes in OUT.
chk() { OUT="$(cd "$CW" && env KIT_CONFIG_OPERATOR="$OPD" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GLS" check "$@" 2>&1)"; RC=$?; }
req() { (cd "$CW" && env KIT_CONFIG_OPERATOR="$OPD" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GLS" required "$1"); }
ageit() { touch -t "$OLD" "$@"; }
# An entry is written only when the ledger's ctime is 2 s old, and ctime cannot be set: wait it out.
settle() { sleep 2.1; }
START() { printf '2026-01-01T00:00:00Z | START | lane=%s classified=%s type=t ctype=t repo=r\n' "$1" "$1"; }
# mk <rid> <lane> <all-ran|all-override|missing-last|none|all-skipped>
mk() {
  local rid="$1" lane="$2" kind="$3" ph n=0 total
  total="$(req "$lane" | grep -c .)"
  { START "$lane"
    for ph in $(req "$lane"); do
      n=$((n+1))
      case "$kind" in
        all-ran) echo "2026-01-01T00:00:01Z | GATE | $ph | ran | e" ;;
        all-override) echo "2026-01-01T00:00:01Z | GATE | $ph | override | e" ;;
        all-skipped) echo "2026-01-01T00:00:01Z | GATE | $ph | skipped | e" ;;
        missing-last) [ "$n" -lt "$total" ] && echo "2026-01-01T00:00:01Z | GATE | $ph | ran | e" ;;
        none) ;;
      esac
    done
  } > "$LOGD/runs/$rid.log"
  ageit "$LOGD/runs/$rid.log"
}
mtime_of() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null; }
cache_lines() { [ -f "$CACHE" ] && tail -n +2 "$CACHE" | grep -c . || echo 0; }
no_tmp() { ! ls "$LOGD"/.gate-check.cache.* >/dev/null 2>&1; }

echo "=== gate-ledger check cache ==="

# ---------------------------------------------------------------------------
# P1: parity. Cold (no cache) == warm (cache hit) for every lane x ledger shape; the cold answer
# is the unchanged full computation, so warm == cold means the cache changed nothing.
# ---------------------------------------------------------------------------
PARITY_BAD=0; HIT_BAD=0; CASES=0
for lane in tiny normal full bug backfill; do
  for kind in all-ran all-override missing-last none all-skipped; do mk "p-$lane-$kind" "$lane" "$kind"; done
done
settle
for lane in tiny normal full bug backfill; do
  for kind in all-ran all-override missing-last none all-skipped; do
    rid="p-$lane-$kind"
    command rm -f "$CACHE"
    chk "$lane" "$rid"; COLD_RC=$RC; COLD_OUT="$OUT"
    n1="$(cache_lines)"
    ageit "$CACHE"; ONE="$(mtime_of "$CACHE")"
    chk "$lane" "$rid"; WARM_RC=$RC; WARM_OUT="$OUT"
    TWO="$(mtime_of "$CACHE")"
    CASES=$((CASES+1))
    { [ "$COLD_RC" = "$WARM_RC" ] && [ "$COLD_OUT" = "$WARM_OUT" ]; } || { PARITY_BAD=$((PARITY_BAD+1)); echo "    parity diff on $rid: cold rc=$COLD_RC warm rc=$WARM_RC"; }
    # a hit does not rewrite the cache file, so the aged mtime survives the warm run
    { [ "$n1" -eq 1 ] && [ "$ONE" = "$TWO" ]; } || { HIT_BAD=$((HIT_BAD+1)); echo "    no hit on $rid (entries after cold: $n1)"; }
  done
done
[ "$PARITY_BAD" -eq 0 ]; ok "P1 warm output + exit code equal cold across $CASES lane x ledger cases" $?
[ "$HIT_BAD" -eq 0 ]; ok "P1 every warm call is a cache hit (no rewrite)" $?

# the expected answers themselves, so parity is not two copies of the same wrong value
chk full p-full-all-ran; { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }; ok "P2 all gates ran: exit 0, silent" $?
chk full p-full-all-override; { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }; ok "P2 all gates overridden: exit 0, silent" $?
chk full p-full-all-skipped; { [ "$RC" -eq 1 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^MISSING-GATE: ')" -eq "$(req full | grep -c .)" ]; }; ok "P2 skipped gates still fail: one MISSING-GATE per required phase" $?
chk full p-full-missing-last; { [ "$RC" -eq 1 ] && [ "$OUT" = "MISSING-GATE: reflect (required for lane 'full'; no ran/override entry in the ledger)" ]; }; ok "P2 one missing gate: exact message, exit 1" $?
chk tiny p-tiny-none; { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }; ok "P2 tiny lane has no required gate: exit 0" $?
chk full no-such-ledger; { [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^MISSING-GATE: think'; }; ok "P2 absent ledger fails every gate" $?
n_before="$(cache_lines)"; chk full no-such-ledger; chk full no-such-ledger
[ "$(cache_lines)" -eq "$n_before" ]; ok "P2 an absent ledger is never cached" $?
chk mega p-full-all-ran; M1="$RC|$OUT"; chk mega p-full-all-ran
{ [ "$RC|$OUT" = "$M1" ] && [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "unknown lane 'mega'"; }; ok "P2 an unknown lane stays fail-closed, repeatedly" $?
! grep -q "^mega	" "$CACHE"; ok "P2 an unknown lane is never cached" $?
chk full; { [ "$RC" -eq 64 ] && printf '%s' "$OUT" | grep -q '^usage: check'; }; ok "P2 missing rid keeps the usage error (64)" $?

# ---------------------------------------------------------------------------
# N: negative controls. Each warms a verdict, changes ONE key input, and the result must flip.
# ---------------------------------------------------------------------------
# N1: append a ledger line
mk n1 full missing-last; settle
chk full n1; chk full n1; B="$RC"
printf '2026-01-01T00:00:09Z | GATE | reflect | ran | late\n' >> "$LOGD/runs/n1.log"; ageit "$LOGD/runs/n1.log"
chk full n1
{ [ "$B" -eq 1 ] && [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }; ok "N1 appending the missing gate flips fail -> pass" $?

# N2: edit [lane.normal] in the (shim) kit.toml
mk n2 normal all-ran; settle
chk normal n2; chk normal n2; B="$RC"
sed -E '/^\[lane\.normal\]/,/^\[/ s/^phases = \[/phases = ["reflect", /' "$SH/kit.toml" > "$SH/kit.toml.new" && command mv -f "$SH/kit.toml.new" "$SH/kit.toml"
chk normal n2
{ [ "$B" -eq 0 ] && [ "$RC" -eq 1 ] && [ "$OUT" = "MISSING-GATE: reflect (required for lane 'normal'; no ran/override entry in the ledger)" ]; }; ok "N2 editing [lane.normal] flips pass -> fail (new required phase)" $?
command cp -f "$KIT_DIR/kit.toml" "$SH/kit.toml"
chk normal n2; [ "$RC" -eq 0 ]; ok "N2 restoring kit.toml flips it back" $?

# N3: edit gate-ledger.sh itself
mk n3 full missing-last; settle
chk full n3; chk full n3; B_OUT="$OUT"
command cp -f "$GLS" "$TD/gate-ledger.saved"
sed -E "s/MISSING-GATE: \\\$phase \\(required for lane '\\\$lane'; no ran/GATE-GAP: \$phase (required for lane '\$lane'; no ran/" "$GLS" > "$GLS.new" && command mv -f "$GLS.new" "$GLS"
chmod +x "$GLS"
chk full n3
{ [ "$RC" -eq 1 ] && [ "$OUT" != "$B_OUT" ] && printf '%s' "$OUT" | grep -q '^GATE-GAP: reflect'; }; ok "N3 editing gate-ledger.sh changes the result (cached message not replayed)" $?
command cp -f "$TD/gate-ledger.saved" "$GLS"
chk full n3; [ "$OUT" = "$B_OUT" ]; ok "N3 restoring gate-ledger.sh restores the original result" $?

# N4: same size, same mtime, new inode
mk n4 full missing-last
printf '2026-01-01T00:00:09Z | GATE | reflect | skipped | xx\n' >> "$LOGD/runs/n4.log"; ageit "$LOGD/runs/n4.log"; settle
chk full n4; chk full n4; B="$RC"
L="$LOGD/runs/n4.log"
sed 's/| skipped | xx/| override | x/' "$L" > "$L.new"      # 7+2 chars -> 8+1 chars: same byte count
touch -r "$L" "$L.new"
SZ_A="$(wc -c < "$L" | tr -d ' ')"; SZ_B="$(wc -c < "$L.new" | tr -d ' ')"
INO_A="$(ls -i "$L" | awk '{print $1}')"
command mv -f "$L.new" "$L"
INO_B="$(ls -i "$L" | awk '{print $1}')"
{ [ "$SZ_A" = "$SZ_B" ] && [ "$INO_A" != "$INO_B" ]; }; ok "N4 precondition: same size, different inode" $?
chk full n4
{ [ "$B" -eq 1 ] && [ "$RC" -eq 0 ]; }; ok "N4 an inode swap at the same size and mtime flips fail -> pass" $?

# N5: a fresh ledger (ctime inside the 2 s guard) is not cached, so an in-place same-size rewrite shows
mk n5 full missing-last
printf '2026-01-01T00:00:09Z | GATE | reflect | skipped | xx\n' >> "$LOGD/runs/n5.log"
touch "$LOGD/runs/n5.log"
n_before="$(cache_lines)"
chk full n5; B="$RC"
[ "$(cache_lines)" -eq "$n_before" ]; ok "N5 a ledger changed under 2 s ago is not cached" $?
printf '%s\n' "$(sed 's/| skipped | xx/| override | x/' "$LOGD/runs/n5.log")" > "$LOGD/runs/n5.log"
touch "$LOGD/runs/n5.log"
chk full n5
{ [ "$B" -eq 1 ] && [ "$RC" -eq 0 ]; }; ok "N5 an in-place same-size rewrite inside the mtime second is seen" $?

# N6: --kit-lanes is its own key; an operator lane override makes the two answers differ
printf '[lane.normal]\nphases = ["spec"]\nlight = []\n' > "$OPD/kit.toml"
mk n6 normal all-ran
{ START normal; echo '2026-01-01T00:00:01Z | GATE | spec | ran | e'; } > "$LOGD/runs/n6.log"; ageit "$LOGD/runs/n6.log"; settle
chk normal n6; A1="$RC"; chk normal n6 --kit-lanes; B1="$RC"
chk normal n6; A2="$RC"; chk normal n6 --kit-lanes; B2="$RC"
{ [ "$A1" -eq 0 ] && [ "$B1" -eq 1 ] && [ "$A2" -eq "$A1" ] && [ "$B2" -eq "$B1" ]; }; ok "N6 --kit-lanes and the overlay answer differently, cold and warm" $?
command rm -f "$OPD/kit.toml"
chk normal n6; { [ "$RC" -eq 1 ]; }; ok "N6 removing the operator overlay invalidates the entry" $?

# N7: a same-size in-place rewrite that restores the old mtime (cp -p / touch -r): size, mtime and inode all
# match the cached entry, only ctime moved
mk n7 full missing-last
printf '2026-01-01T00:00:09Z | GATE | reflect | skipped | xx\n' >> "$LOGD/runs/n7.log"; ageit "$LOGD/runs/n7.log"; settle
chk full n7; chk full n7; B="$RC"
L="$LOGD/runs/n7.log"
command cp -p "$L" "$TD/n7.ref"
SZ_A="$(wc -c < "$L" | tr -d ' ')"; INO_A="$(ls -i "$L" | awk '{print $1}')"
sed 's/| skipped | xx/| override | x/' "$L" > "$TD/n7.new"
cat "$TD/n7.new" > "$L"; touch -r "$TD/n7.ref" "$L"
{ [ "$SZ_A" = "$(wc -c < "$L" | tr -d ' ')" ] && [ "$INO_A" = "$(ls -i "$L" | awk '{print $1}')" ] \
  && [ "$(mtime_of "$L")" = "$(mtime_of "$TD/n7.ref")" ]; }; ok "N7 precondition: same size, same inode, same mtime" $?
chk full n7
{ [ "$B" -eq 1 ] && [ "$RC" -eq 0 ]; }; ok "N7 a same-size rewrite with the mtime restored flips fail -> pass" $?

# N8: an unreadable ledger is never cached, and becomes readable again with master's answer
mk n8 full all-ran; settle
chk full n8; B="$RC"
chmod 000 "$LOGD/runs/n8.log"
if [ -r "$LOGD/runs/n8.log" ]; then
  ok "N8 skipped: this user can read a mode-000 file" 0
else
  settle
  n_before="$(cache_lines)"
  chk full n8; U_RC="$RC"
  { [ "$B" -eq 0 ] && [ "$U_RC" -eq 1 ] && printf '%s' "$OUT" | grep -q '^MISSING-GATE: think'; }; ok "N8 an unreadable ledger fails every gate, as master does" $?
  [ "$(cache_lines)" -eq "$n_before" ]; ok "N8 an unreadable ledger is not cached, even once its ctime is old" $?
  chmod 644 "$LOGD/runs/n8.log"
  chk full n8; R1="$RC"; settle; chk full n8; R2="$RC"
  { [ "$R1" -eq 0 ] && [ "$R2" -eq 0 ] && [ -z "$OUT" ]; }; ok "N8 after chmod 644 the answer is master's PASS, now and 2 s later" $?
fi

# N9: bytes moved between the operator and project layers (same concatenation) change the fingerprint
mk n9 full all-ran; settle
printf '# a\n# b\n' > "$OPD/kit.toml"; : > "$CW/.kit.toml"
chk full n9; FP_A="$(head -n 1 "$CACHE")"
printf '# a\n' > "$OPD/kit.toml"; printf '# b\n' > "$CW/.kit.toml"
chk full n9; FP_B="$(head -n 1 "$CACHE")"
[ "$(cat "$OPD/kit.toml" "$CW/.kit.toml")" = "$(printf '# a\n# b')" ] && [ "$FP_A" != "$FP_B" ]; ok "N9 moving a block between operator and project kit.toml invalidates the cache" $?
chk full n9; [ "$(head -n 1 "$CACHE")" = "$FP_B" ]; ok "N9 the same layers again keep the fingerprint" $?
command mv -f "$OPD/kit.toml" "$TD/op.moved"; command mv -f "$CW/.kit.toml" "$TD/proj.moved"

# ---------------------------------------------------------------------------
# C: corrupt cache. The answer never changes; nothing is left behind.
# ---------------------------------------------------------------------------
mk c1 full missing-last; settle
chk full c1; GOOD_RC="$RC"; GOOD_OUT="$OUT"
FP="$(head -n 1 "$CACHE")"
same() { [ "$RC" = "$GOOD_RC" ] && [ "$OUT" = "$GOOD_OUT" ]; }
printf 'garbage\n\001\002\n' > "$CACHE"; chk full c1; same; ok "C1 garbage cache: correct answer" $?
printf '%s\nfull\tc1\t0\t1\t2\t3\t4\tpass\n' "$FP" > "$CACHE"; chk full c1; same; ok "C2 entry with the wrong identity: correct answer" $?
KEY="$(cd "$CW" && env DWARVES_KIT_LOG_DIR="$LOGD" bash -c 'stat -f "%z	%m	%i	%c" "$1" 2>/dev/null || stat -c "%s	%Y	%i	%Z" "$1"' _ "$LOGD/runs/c1.log")"
printf '%s\nfull\tc1\t0\t%s\tmaybe\n' "$FP" "$KEY" > "$CACHE"; chk full c1; same; ok "C3 matching key, malformed result: correct answer" $?
printf '%s\nfull\tc1\t0\t%s\tfail:\n' "$FP" "$KEY" > "$CACHE"; chk full c1; same; ok "C4 matching key, empty phase list: correct answer" $?
printf '%s\nfull\tc1\t0\t%s\tfail:think;rm -rf x\n' "$FP" "$KEY" > "$CACHE"; chk full c1; same; ok "C5 matching key, junk in the phase list: correct answer" $?
head -c 7 "$CACHE" > "$CACHE.cut"; command mv -f "$CACHE.cut" "$CACHE"; chk full c1; same; ok "C6 truncated cache: correct answer" $?
: > "$CACHE"; chk full c1; same; ok "C7 empty cache: correct answer" $?
command rm -f "$CACHE"; mkdir "$CACHE"; chk full c1; same; ok "C8 cache path is a directory: correct answer" $?
command mv -f "$CACHE" "$TD/cache.dir.moved"   # the cache write may move its temp file into the directory
chk full c1; chk full c1; same; ok "C9 a good cache is written again after the fallbacks" $?
[ "$(cache_lines)" -ge 1 ]; ok "C9 the cache holds an entry again" $?
no_tmp; ok "C10 no temp file is left behind in the log dir" $?

echo ""
echo "Passed: $PASS / $((PASS+FAIL))"
[ "$FAIL" -eq 0 ] && echo "All gate-ledger check cache tests passed." || { echo "FAILED: $FAIL"; exit 1; }

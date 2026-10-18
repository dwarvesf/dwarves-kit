#!/usr/bin/env bash
# test-staging-one-writer.sh -- the staging buffer has ONE locked write path.
#
# Before: drain flocked `<staging>.lock`, promote took the board lock and rewrote the whole
# staging file from a stale read, and stats anomalies plus the bash hooks appended with no lock
# at all, so a block appended while a promote ran was lost.
#
# Proves:
#   AC1  concurrent `staging-format.py append` writers: every block lands whole, and the header
#        is written exactly once (decided inside the lock)
#   AC1b a held staging lock makes append, drain and promote all wait (deterministic)
#   AC2  `board promote` racing appenders loses no appended block and still relabels every
#        promoted one (the lost-append bug)
#   AC3  `reflect drain` expiry racing appenders loses no appended block
#   AC4  a block that changed after it was listed (expired by drain) is skipped by promote,
#        never minted onto the board
#   AC5  the stats anomalies append and both bash hooks go through the locked path (no raw
#        append to the buffer left in hooks/)
#   AC6  the hooks' staging write works end to end through the `append` verb
#   AC7  sf_append, the bash door the hooks call: locked python3 path, plain append without python3
#
# Run: bash tests/test-staging-one-writer.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SF="$KIT_DIR/lib/reflect/staging-format.py"
ADD_BACKLOG="$KIT_DIR/lib/board/bin/add-backlog"
DRAIN="$KIT_DIR/lib/reflect/drain.py"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3"; echo $?)"; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-staging-one-writer.XXXXXX")" || exit 1
TMPD="$(cd "$TMPD" && pwd)"
trap 'rm -rf "$TMPD"' EXIT
TODAY="$(date +%Y-%m-%d)"

block() {  # <title> [date]
  printf '## [staged] %s\n- Intent: reason for %s\n- Approach: do it\n- Tags: #u-mid #f-hi\n- Source: session %s\n\n' "$1" "$1" "${2:-$TODAY}"
}
count() { grep -c "$1" "$2" || true; }

# ============================================================
echo "== AC1: concurrent append writers: every block whole, header once =="
# ============================================================
S1="$TMPD/a1/backlog-staging.md"
for i in $(seq 1 12); do
  ( block "writer $i" | python3 "$SF" append "$S1" --header $'# Backlog staging\n\n' ) &
done
wait
chk "12 blocks landed" "$([ "$(count '^## \[staged\] writer ' "$S1")" -eq 12 ]; echo $?)"
chk "header written exactly once" "$([ "$(count '^# Backlog staging' "$S1")" -eq 1 ]; echo $?)"
chk "no block is torn (each has its Source line)" "$([ "$(count '^- Source: session ' "$S1")" -eq 12 ]; echo $?)"
python3 "$SF" append "$S1" </dev/null; chk "empty stdin is a clean no-op" "$?"
python3 "$SF" append 2>/dev/null; chk "usage error without a path (exit 64)" "$([ $? -eq 64 ]; echo $?)"

# ============================================================
echo "== AC1b: while one process holds the staging lock, append, drain and promote all wait =="
# ============================================================
# Deterministic counterpart to the race in AC2: a holder keeps the lock for 3 s, the three
# writers start inside the hold, and none may touch the buffer until it is released.
D="$TMPD/hold"; mkdir -p "$D"
OLD1="$(date -u -v-60d +%Y-%m-%d 2>/dev/null || date -u -d '-60 days' +%Y-%m-%d)"
{ printf '# Backlog staging\n\n'; block "held seed"; block "held old" "$OLD1"; } > "$D/backlog-staging.md"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n' > "$D/BACKLOG.md"
python3 - "$SF" "$D/backlog-staging.md" "$D/held" <<'HOLDER' &
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("sf", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
with m.staging_lock(sys.argv[2]):
    open(sys.argv[3], "w").close()
    time.sleep(3)
HOLDER
for _ in $(seq 1 50); do [ -e "$D/held" ] && break; sleep 0.2; done
before="$(shasum -a 256 "$D/backlog-staging.md" | cut -d' ' -f1)"
( block "held append" | python3 "$SF" append "$D/backlog-staging.md" ) &
( BACKLOG_STAGE_STAGING="$D/backlog-staging.md" python3 "$DRAIN" >/dev/null 2>&1 ) &
( BACKLOG_STAGE_BACKLOG="$D/BACKLOG.md" BACKLOG_STAGE_STAGING="$D/backlog-staging.md" python3 "$ADD_BACKLOG" 1 >/dev/null 2>&1 ) &
sleep 1.5
during="$(shasum -a 256 "$D/backlog-staging.md" | cut -d' ' -f1)"
chk "buffer untouched while the lock is held (append, drain and promote all waited)" "$([ "$before" = "$during" ]; echo $?)"
wait
chk "after release: the appended block landed" "$([ "$(count '^## \[staged\] held append' "$D/backlog-staging.md")" -eq 1 ]; echo $?)"
chk "after release: drain expired the old block" "$([ "$(count '^## \[expired\] held old' "$D/backlog-staging.md")" -eq 1 ]; echo $?)"
chk "after release: promote relabeled the seed block" "$([ "$(count '^## \[promoted ID-[0-9]*\] held seed' "$D/backlog-staging.md")" -eq 1 ]; echo $?)"
chk "after release: promote minted its row" "$([ "$(grep -cE '^\| ID-[0-9]+ \|' "$D/BACKLOG.md")" -eq 1 ]; echo $?)"

# ============================================================
echo "== AC2: promote racing appenders: no appended block lost =="
# ============================================================
lost_total=0; unmarked_total=0
for round in 1 2 3; do
  D="$TMPD/a2-$round"; mkdir -p "$D"
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n' > "$D/BACKLOG.md"
  { printf '# Backlog staging\n\n'; for i in $(seq 1 8); do block "seed $round $i"; done; } > "$D/backlog-staging.md"
  ( BACKLOG_STAGE_BACKLOG="$D/BACKLOG.md" BACKLOG_STAGE_STAGING="$D/backlog-staging.md" \
      python3 "$ADD_BACKLOG" all >"$D/promote.out" 2>&1 ) &
  pp=$!
  for i in $(seq 1 25); do
    block "appended $round $i" | python3 "$SF" append "$D/backlog-staging.md"
  done
  wait "$pp"
  # an appended block may land before promote's listing (then `all` promotes it too) or after
  # (it stays staged): either way it must still be in the file under its title
  appended="$(count "^## \[[^]]*\] appended $round " "$D/backlog-staging.md")"
  [ "$appended" -eq 25 ] || lost_total=$((lost_total + 25 - appended))
  # every promoted label has exactly one board row, and all 8 seeds were promoted
  promoted="$(count '^## \[promoted ID-' "$D/backlog-staging.md")"
  rows="$(grep -cE '^\| ID-[0-9]+ \|' "$D/BACKLOG.md")"
  seeds="$(count "^## \[promoted ID-[0-9]*\] seed $round " "$D/backlog-staging.md")"
  [ "$promoted" -eq "$rows" ] && [ "$seeds" -eq 8 ] || unmarked_total=$((unmarked_total + 1))
done
chk "no appended block lost across 3 racing rounds (lost: $lost_total)" "$([ "$lost_total" -eq 0 ]; echo $?)"
chk "promoted labels match board rows and all 8 seeds promoted (bad rounds: $unmarked_total)" "$([ "$unmarked_total" -eq 0 ]; echo $?)"

# ============================================================
echo "== AC3: drain expiry racing appenders: no appended block lost =="
# ============================================================
D="$TMPD/a3"; mkdir -p "$D"
OLD="$(date -u -v-60d +%Y-%m-%d 2>/dev/null || date -u -d '-60 days' +%Y-%m-%d)"
{ printf '# Backlog staging\n\n'; for i in $(seq 1 8); do block "old $i" "$OLD"; done; } > "$D/backlog-staging.md"
( BACKLOG_STAGE_STAGING="$D/backlog-staging.md" python3 "$DRAIN" >"$D/drain.out" 2>&1 ) &
dp=$!
for i in $(seq 1 25); do block "drain-race $i" | python3 "$SF" append "$D/backlog-staging.md"; done
wait "$dp"
chk "all 25 appended blocks survive the expiry pass" "$([ "$(count '^## \[staged\] drain-race ' "$D/backlog-staging.md")" -eq 25 ]; echo $?)"
chk "all 8 old blocks were expired" "$([ "$(count '^## \[expired\] old ' "$D/backlog-staging.md")" -eq 8 ]; echo $?)"

# ============================================================
echo "== AC4: a block that changed since it was listed is skipped, not minted =="
# ============================================================
D="$TMPD/a4"; mkdir -p "$D"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n' > "$D/BACKLOG.md"
{ printf '# Backlog staging\n\n'; block "first"; block "second"; } > "$D/backlog-staging.md"
# the operator lists, then another session expires "first" before promote runs
python3 - "$D/backlog-staging.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("## [staged] first", "## [expired] first", 1)
open(p, "w").write(t)
PY
out="$(BACKLOG_STAGE_BACKLOG="$D/BACKLOG.md" BACKLOG_STAGE_STAGING="$D/backlog-staging.md" python3 "$ADD_BACKLOG" 1 2>&1)"
chk_has "promote picks the live block that now holds index 1" "$out" "promoted ID-"
chk "exactly one row minted" "$([ "$(grep -cE '^\| ID-[0-9]+ \|' "$D/BACKLOG.md")" -eq 1 ]; echo $?)"
chk "the expired block was not promoted" "$(grep -q '^## \[expired\] first' "$D/backlog-staging.md"; echo $?)"
# library-level: a stale selection (raw text no longer present) is skipped
python3 - "$ADD_BACKLOG" "$D" <<'PY'
import importlib.machinery, importlib.util, os, sys
path, d = sys.argv[1], sys.argv[2]
os.environ["BACKLOG_STAGE_BACKLOG"] = os.path.join(d, "BACKLOG.md")
os.environ["BACKLOG_STAGE_STAGING"] = os.path.join(d, "backlog-staging.md")
loader = importlib.machinery.SourceFileLoader("add_backlog", path)
spec = importlib.util.spec_from_loader("add_backlog", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
stale = {"raw": "## [staged] vanished\n- Intent: gone\n", "title": "vanished", "fields": {}}
current = open(os.path.join(d, "backlog-staging.md")).read()
assert mod._retag(current, stale, "## [promoted ID-9]") is None
print("stale-ok")
PY
chk "a vanished block is reported as stale by the relabel helper" "$?"

# ============================================================
echo "== AC5: no raw append to the staging buffer is left in the hooks or anomalies =="
# ============================================================
raw="$(grep -nE '>>[[:space:]]*"?\$\{?(st|staging)\}?"?' "$KIT_DIR/hooks/backlog-stage.sh" "$KIT_DIR/hooks/intake-sweep.sh" || true)"
chk "hooks carry no raw >> on the staging variable" "$([ -z "$raw" ]; echo $?)"
chk_has "backlog-stage writes through sf_append" "$(cat "$KIT_DIR/hooks/backlog-stage.sh")" '| sf_append "$st"'
chk_has "intake-sweep writes through sf_append" "$(cat "$KIT_DIR/hooks/intake-sweep.sh")" '| sf_append "$staging"'
# No python writer opens the buffer for append itself. Three proposers outside this slice's file
# fence still do; they are named here so a NEW raw writer fails the test, and each one is
# dropped from the list when it moves to staging-format.py append_blocks.
KNOWN_RAW='lib/reflect/propose.py lib/session/audit/bin/session-audit lib/session/intel/bin/session-intel'
found="$(cd "$KIT_DIR" && grep -rlE 'open\((staging|STAGING)[^)]*"a"' lib hooks bin 2>/dev/null | sort | tr '\n' ' ')"
unexpected=""
for f in $found; do case " $KNOWN_RAW " in *" $f "*) ;; *) unexpected="$unexpected $f" ;; esac; done
chk "no new raw python append to the buffer outside the known three (found:${unexpected:- none new})" "$([ -z "$unexpected" ]; echo $?)"
chk_has "stats anomalies appends through append_blocks" "$(cat "$KIT_DIR/lib/stats/src/stats/anomalies.py")" "append_blocks("

# ============================================================
echo "== AC7: sf_append, the bash door: locked path with python3, plain append without =="
# ============================================================
D="$TMPD/a7"; mkdir -p "$D"
( source "$KIT_DIR/lib/reflect/staging-format.sh"
  block "bash one" | sf_append "$D/s.md" $'# H\n\n'; block "bash two" | sf_append "$D/s.md" $'# H\n\n' )
chk "sf_append (python3): both blocks, header once" "$([ "$(count '^## \[staged\] bash ' "$D/s.md")" -eq 2 ] && [ "$(count '^# H' "$D/s.md")" -eq 1 ]; echo $?)"
# no python3 on PATH: a PATH of bash/mkdir/cat/printf only
NOPY="$TMPD/nopy-bin"; mkdir -p "$NOPY"
for tool in mkdir cat printf; do ln -sf "$(command -v $tool)" "$NOPY/$tool" 2>/dev/null; done
( source "$KIT_DIR/lib/reflect/staging-format.sh"; PATH="$NOPY"
  block "plain one" | sf_append "$D/n.md" $'# H\n\n'; block "plain two" | sf_append "$D/n.md" $'# H\n\n' )
chk "sf_append (no python3): both blocks, header once" "$([ "$(count '^## \[staged\] plain ' "$D/n.md")" -eq 2 ] && [ "$(count '^# H' "$D/n.md")" -eq 1 ]; echo $?)"

# ============================================================
echo "== AC6: the hook write path end to end =="
# ============================================================
D="$TMPD/a6"; mkdir -p "$D"
HDR=$'# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions.\n\n'
( block "hook one" | python3 "$SF" append "$D/s.md" --header "$HDR"; block "hook two" | python3 "$SF" append "$D/s.md" --header "$HDR" )
chk "header once across two hook runs" "$([ "$(count 'Candidates auto-extracted' "$D/s.md")" -eq 1 ]; echo $?)"
chk "both hook blocks present" "$([ "$(count '^## \[staged\] hook ' "$D/s.md")" -eq 2 ]; echo $?)"
mkdir -p "$D/blocker"; : > "$D/blocker/file"
block "x" | python3 "$SF" append "$D/blocker/file/s.md" 2>/dev/null; chk "an unwritable path exits non-zero" "$([ $? -ne 0 ]; echo $?)"

echo ""
echo "== $TOTAL run, $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

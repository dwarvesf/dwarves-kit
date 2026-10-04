#!/usr/bin/env bash
# test-lane-telemetry.sh -- SPEC-099, kit-telemetry SG-04.
# Pins the `render` routing-diagram subcommand: a seeded corpus renders the
# task-type -> lane -> gate table + flow + counts; the filter narrows; an empty
# corpus degrades gracefully (no crash, no fake zeros).
#
# Run: bash tests/test-lane-telemetry.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LT="$KIT_DIR/lib/telemetry/lane-telemetry.sh"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
: "lib/gate/ledger-key.sh"   # the ledger-key lib is named on a code line so bin/test-affected picks this suite when it changes (its reference scan skips comments)

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }
has() { { trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$1"; }

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

# --- filter is a LITERAL substring, not a regex: metachars don't over-match or crash ---
OUTD="$(NO_COLOR=1 bash "$LT" render "." 2>&1)"
has "no runs match" "$OUTD"; ok "filter '.' is literal (no regex over-match)" $?
OUTB="$(NO_COLOR=1 bash "$LT" render "[" 2>&1)"
if { trap '' PIPE; printf '%s' "$OUTB" 2>/dev/null || :; } | grep -qiE 'awk|character class|syntax'; then ok "filter '[' does not crash awk [NC]" 1; else ok "filter '[' does not crash awk [NC]" 0; fi

# --- gate coverage counts DISTINCT runs, not raw lines (a re-recorded phase counts once) ---
DD="$(mktemp -d)/logs"
DWARVES_KIT_LOG_DIR="$DD" bash "$GL" start rr full full spec-feature spec-feature rp >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$DD" bash "$GL" record rr think ran x >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$DD" bash "$GL" record rr think ran "retry" >/dev/null 2>&1   # same phase, same run, twice
OUTC="$(DWARVES_KIT_LOG_DIR="$DD" NO_COLOR=1 bash "$LT" render 2>&1)"
has "1 run," "$OUTC"; ok "single run pluralizes as 'run' not 'runs'" $?
# coverage line for think must read 1 (distinct runs), not 2 (raw lines)
if printf '%s' "$OUTC" | grep -E 'think +[2-9]' >/dev/null; then ok "gate coverage dedupes a re-recorded phase (think=1, not 2)" 1; else ok "gate coverage dedupes a re-recorded phase (think=1, not 2)" 0; fi

# --- filter matches lane OR type substring (DEC-002, intentional): a type substring hits too ---
DT="$(mktemp -d)/logs"
DWARVES_KIT_LOG_DIR="$DT" bash "$GL" start t1 normal normal full-stack full-stack rp >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$DT" bash "$GL" record t1 think ran x >/dev/null 2>&1
OUTT="$(DWARVES_KIT_LOG_DIR="$DT" NO_COLOR=1 bash "$LT" render full 2>&1)"
has "full-stack" "$OUTT"; ok "filter matches a TYPE substring too (DEC-002 lane-OR-type), not only lane" $?

# --- SPEC-110: token efficiency section + usage=? honest null + render --mermaid annotation ---
TT="$(mktemp -d)/logs"
DWARVES_KIT_LOG_DIR="$TT" bash "$GL" start ta full full spec-feature spec-feature rp >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$TT" bash "$GL" tokens ta in=1000 out=200 cache_read=5000 cache_create=0 >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$TT" bash "$GL" start tb normal normal spec-feature spec-feature rp >/dev/null 2>&1   # NO tokens -> usage=?
OUTT="$(DWARVES_KIT_LOG_DIR="$TT" NO_COLOR=1 bash "$LT" report 2>&1)"
has "token efficiency" "$OUTT"; ok "SPEC-110: report has a token efficiency section" $?
{ trap '' PIPE; printf '%s' "$OUTT" 2>/dev/null || :; } | grep -qF "usage=?"; ok "SPEC-110: report shows usage=? for the uncaptured run (honest null, not zero)" $?
{ trap '' PIPE; printf '%s' "$OUTT" 2>/dev/null || :; } | grep -qE 'full[[:space:]]+1200'; ok "SPEC-110: report shows the captured lane's median tokens-to-done" $?
OUTM="$(DWARVES_KIT_LOG_DIR="$TT" NO_COLOR=1 bash "$LT" render --mermaid 2>&1)"
{ trap '' PIPE; printf '%s' "$OUTM" 2>/dev/null || :; } | grep -qF '```mermaid'; ok "SPEC-110: render --mermaid emits a mermaid block" $?
{ trap '' PIPE; printf '%s' "$OUTM" 2>/dev/null || :; } | grep -qE 'lane_full.*1200 tok'; ok "SPEC-110: mermaid annotates the lane node with median tokens" $?
{ trap '' PIPE; printf '%s' "$OUTM" 2>/dev/null || :; } | grep -qF 'usage=?'; ok "SPEC-110: mermaid shows usage=? for the uncaptured lane" $?
OUTA="$(DWARVES_KIT_LOG_DIR="$TT" NO_COLOR=1 bash "$LT" render 2>&1)"
{ { trap '' PIPE; printf '%s' "$OUTA" 2>/dev/null || :; } | grep -q "Lane routing" && ! { trap '' PIPE; printf '%s' "$OUTA" 2>/dev/null || :; } | grep -qF '```mermaid'; }; ok "SPEC-110 NC: ASCII render unchanged (no mermaid block without the flag)" $?

# --- graceful-empty NEGATIVE CONTROL: empty/fresh LOG_DIR ---
OUTE="$(DWARVES_KIT_LOG_DIR="$(mktemp -d)/empty" NO_COLOR=1 bash "$LT" render 2>&1)"
has "no runs recorded" "$OUTE"; ok "empty corpus renders an honest 'no runs recorded' [NC]" $?
if { trap '' PIPE; printf '%s' "$OUTE" 2>/dev/null || :; } | grep -qiE 'error|not found|unbound|syntax'; then ok "empty render does not crash [NC]" 1; else ok "empty render does not crash [NC]" 0; fi

# --- ID-398: failure-policy breakdown in `report` ---
PD="$(mktemp -d)/logs"
DWARVES_KIT_LOG_DIR="$PD" bash "$GL" start pr1 full full spec-feature spec-feature rp >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$PD" bash "$GL" outcome pr1 build start >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$PD" bash "$GL" outcome pr1 build end caught=true policy=escalate >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$PD" bash "$GL" start pr2 full full spec-feature spec-feature rp >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$PD" bash "$GL" outcome pr2 build start >/dev/null 2>&1
DWARVES_KIT_LOG_DIR="$PD" bash "$GL" outcome pr2 build end caught=false policy=continue >/dev/null 2>&1
OUTP="$(DWARVES_KIT_LOG_DIR="$PD" NO_COLOR=1 bash "$LT" report 2>&1)"
has "failure policy" "$OUTP"; ok "ID-398: report has a failure-policy section" $?
{ trap '' PIPE; printf '%s' "$OUTP" 2>/dev/null || :; } | grep -qE 'escalate[[:space:]]+1'; ok "ID-398: report counts an escalate outcome" $?
{ trap '' PIPE; printf '%s' "$OUTP" 2>/dev/null || :; } | grep -qE 'continue[[:space:]]+1'; ok "ID-398: report counts a continue outcome" $?

# --- ID-398 NEGATIVE CONTROL: no policy= anywhere -> section omitted entirely ---
OUTNP="$(NO_COLOR=1 bash "$LT" report 2>&1)"   # the seeded corpus at the top of this file has no policy= fields
if { trap '' PIPE; printf '%s' "$OUTNP" 2>/dev/null || :; } | grep -qF "failure policy"; then ok "ID-398 NC: no policy-carrying runs -> section omitted" 1; else ok "ID-398 NC: no policy-carrying runs -> section omitted" 0; fi

# --- misfires speed: one-awk _rows is byte-identical to the per-file loop it replaced ---
# The oracle below is the old _rows body (one awk process per ledger). The suite sources a copy
# of lane-telemetry.sh minus its trailing `main` call, so the real _rows runs against the oracle.
echo ""
echo "=== lane-telemetry misfires speed ==="
TD="$(mktemp -d)"
cp -R "$KIT_DIR/lib" "$TD/lib"
sed '$d' "$LT" > "$TD/lib/telemetry/lt-src.sh"
legacy_rows() {
  local f rid
  for f in "$RUNS_DIR"/*.log; do
    [ -e "$f" ] || continue
    rid="$(basename "$f" .log)"
    awk -v rid="$rid" '
      BEGIN { FS=" \\| " }
      NR==1 { first=$1 }
      { last=$1 }
      $2=="START" && !started {
        started=1
        n=split($3, kv, " ")
        for (i=1; i<=n; i++) { split(kv[i], p, "="); m[p[1]]=p[2] }
      }
      $2=="START-AMEND" {
        started=1
        n=split($3, kv, " ")
        for (i=1; i<=n; i++) { split(kv[i], p, "="); m[p[1]]=p[2] }
      }
      $2=="GATE" && $4=="ran"      { ran++ }
      $2=="GATE" && $4=="skipped"  { skip++ }
      $2=="GATE" && $4=="override" { ovr++ }
      $2=="GATE" && $3=="review" && $4=="ran" { review=$5; for (i=6; i<=NF; i++) review = review " | " $i }
      $2=="GATE" && $3=="ship"   && $4=="ran" { ship=1 }
      END {
        lane=(m["lane"]==""?"?":m["lane"]); cls=(m["classified"]==""?"?":m["classified"])
        type=(m["type"]==""?"?":m["type"]); repo=(m["repo"]==""?"?":m["repo"])
        ctype=(m["ctype"]==""?"?":m["ctype"])
        mis=(lane!="?" && cls!="?" && lane!=cls) ? 1 : 0
        tmis=(type!="?" && ctype!="?" && type!=ctype) ? 1 : 0
        if (review=="") review="-"
        gsub(/\t/, " ", review)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\n", \
          rid, repo, lane, cls, type, ctype, ran+0, skip+0, ovr+0, mis, tmis, ship+0, review, first, last
      }' "$f"
  done
}
rows_src() { ( DWARVES_KIT_LOG_DIR="$1" bash -c 'set -euo pipefail; source "$1"; "$2"' _ "$TD/lib/telemetry/lt-src.sh" "$2" ); }

FX="$TD/fx"; mkdir -p "$FX/runs"
L() { printf '2026-01-01T00:00:%s | %s\n' "$@"; }   # sec, rest-of-line
{ L 01Z "START | lane=normal classified=normal type=doc ctype=doc repo=r"
  L 02Z "GATE | think | ran | x"; L 03Z "GATE | ship | ran | done"; } > "$FX/runs/a-plain.log"
{ L 01Z "START | lane=full classified=normal type=a ctype=a repo=r"
  L 02Z "START | lane=tiny classified=tiny type=z ctype=z repo=zz"
  L 03Z "START-AMEND | lane=normal classified=normal type=a ctype=a repo=r"
  L 04Z "START-AMEND | lane=bug classified=normal type=b ctype=b repo=r"
  L 05Z "GATE | build | ran | x"; } > "$FX/runs/b-amend.log"
{ L 01Z "START | lane=full classified=normal type=doc ctype=eval repo=r2"
  L 02Z "GATE | review | ran | first | pass"; L 03Z "GATE | review | ran | good | with a$(printf '\t')tab"
  L 04Z "GATE | think | skipped | n/a"; L 05Z "GATE | spec | override | because"; } > "$FX/runs/c-misfire.log"
{ L 01Z "GATE | build | ran | x"; L 02Z "ACTION | something"; } > "$FX/runs/d-nostart.log"
: > "$FX/runs/e-empty.log"
{ L 01Z "START | lane=normal classified=normal type=doc ctype=doc repo=r"
  L 02Z "GATE | ship | ran | done"; } > "$FX/runs/f-shipped.log"
{ L 01Z "START | lane=normal classified=normal type=doc ctype=doc repo=r"
  L 02Z "GATE | spec | ran | s"; L 03Z "GATE | build | ran | b"; L 04Z "GATE | review | ran | r"
  L 05Z "GATE | ship | ran | done"; } > "$FX/runs/g-complete.log"
{ L 01Z "START | lane=tiny classified=tiny type=doc ctype=doc repo=r"
  L 02Z "GATE | ship | ran | done"
  L 03Z "START-AMEND | lane=normal classified=normal type=doc ctype=doc repo=r"; } > "$FX/runs/h-amended.log"
: > "$FX/runs/z-empty.log"                          # a trailing empty ledger must still emit its row
ln -s "$FX/runs/does-not-exist" "$FX/runs/y-dangling.log"   # a dangling symlink ledger is skipped, never fatal

legacy="$(RUNS_DIR="$FX/runs" legacy_rows)"
new="$(rows_src "$FX" _rows)"
[ "$new" = "$legacy" ]; ok "single-awk _rows is byte-identical to the per-file loop (fixture, incl. START-AMEND, tab scrub, empty ledger)" $?
[ "$(printf '%s\n' "$new" | grep -c .)" -eq 9 ]; ok "_rows emits one row per regular ledger, empty ones included, the dangling symlink skipped" $?
printf '%s\n' "$new" | tail -n 1 | grep -q '^z-empty'; ok "_rows: a trailing empty ledger is still emitted last" $?
NC=0; NO_COLOR=1 DWARVES_KIT_LOG_DIR="$FX" bash "$LT" misfires >/dev/null 2>&1 || NC=$?
[ "$NC" -eq 0 ]; ok "misfires exits 0 with a dangling symlink ledger present (rc=$NC)" $?
echo "$new" | grep -qF "$(printf 'b-amend\tr\tbug\tnormal\tb\tb\t')"; ok "_rows: last START-AMEND wins, the second plain START is ignored" $?
echo "$new" | grep -qF "$(printf 'good | with a tab')"; ok "_rows: review text joins with ' | ' and the tab is scrubbed" $?

EXP_MIS="$(NO_COLOR=1 DWARVES_KIT_LOG_DIR="$FX" bash "$LT" misfires 2>&1)"
for want in "routing misfires" "c-misfire: chosen=full classified=normal (type=doc repo=r2)" "b-amend: chosen=bug classified=normal (type=b repo=r)" "type misfires" "c-misfire: type=doc classified-type=eval (lane=full repo=r2)" "f-shipped (normal)" "h-amended (normal)"; do
  has "$want" "$EXP_MIS"; ok "misfires prints: $want" $?
done
has "g-complete" "$EXP_MIS" && ok "misfires must not flag a complete shipped run" 1 || ok "misfires must not flag a complete shipped run" 0
REAL_ROWS_CALLS="$(grep -c '_rows' <(sed -n '/^misfires()/,/^}/p' "$LT"))"
[ "$REAL_ROWS_CALLS" -eq 1 ]; ok "misfires() computes _rows once ($REAL_ROWS_CALLS call in its body)" $?

# --- shipped-incomplete verdict cache ---
# A shim kit copy: the real lib tree plus a gate-ledger.sh wrapper that counts every call.
SH="$TD/shim"; mkdir -p "$SH"
cp -R "$KIT_DIR/lib" "$SH/lib"; cp "$KIT_DIR/kit.toml" "$SH/kit.toml"
mv "$SH/lib/gate/gate-ledger.sh" "$SH/lib/gate/gate-ledger-real.sh"
cat > "$SH/lib/gate/gate-ledger.sh" <<'WRAP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CALLS_FILE:?}"
exec bash "$(dirname "${BASH_SOURCE[0]}")/gate-ledger-real.sh" "$@"
WRAP
SLT="$SH/lib/telemetry/lane-telemetry.sh"
CW="$TD/cwd"; mkdir -p "$CW"; OPD="$TD/op"; mkdir -p "$OPD"
CALLS="$TD/calls"; : > "$CALLS"
CL="$TD/cl"; cp -R "$FX" "$CL"
CACHE="$CL/.shipped-incomplete.cache"
mf() { ( cd "$CW" && NO_COLOR=1 CALLS_FILE="$CALLS" KIT_CONFIG_OPERATOR="$OPD" DWARVES_KIT_LOG_DIR="$CL" bash "$SLT" misfires 2>&1 ); }
ncalls() { grep -c . "$CALLS" || true; }

O1="$(mf)"; C1="$(ncalls)"
N=4   # shipped runs with a lane: a-plain, f-shipped, g-complete, h-amended
[ "$C1" -eq "$N" ]; ok "cold run checks each shipped run live ($N gate-ledger calls, got $C1)" $?
has "f-shipped (normal)" "$O1"; ok "cold run flags the incomplete shipped run" $?
[ -s "$CACHE" ]; ok "cold run writes the verdict cache" $?
O2="$(mf)"; C2="$(ncalls)"
[ "$C2" -eq "$C1" ]; ok "warm run makes no gate-ledger call (still $C2)" $?
[ "$O2" = "$O1" ]; ok "warm output is identical to cold output" $?

L 09Z "GATE | build | ran | late" >> "$CL/runs/f-shipped.log"
O3="$(mf)"; C3="$(ncalls)"
[ "$C3" -eq "$((C2+1))" ]; ok "a changed ledger re-checks only itself (+1 call, got $((C3-C2)))" $?
has "f-shipped" "$O3" && ok "re-check sees the new ledger content (still missing review)" 0 || ok "re-check sees the new ledger content (still missing review)" 1

touch -t 202601010000 "$CL/runs/g-complete.log"
mf >/dev/null; C4="$(ncalls)"
[ "$C4" -eq "$((C3+1))" ]; ok "an mtime-only change re-checks that ledger (+1 call, got $((C4-C3)))" $?

# corrupt body lines (header kept): garbage, a bad verdict, a truncated line -> live fallback
{ head -n 1 "$CACHE"; printf 'garbage\n'; printf 'f-shipped\t1\t2\tmaybe\n'; printf 'g-complete\t9\n'; } > "$CACHE.tmp"; mv "$CACHE.tmp" "$CACHE"
O5="$(mf)"; C5="$(ncalls)"
[ "$C5" -eq "$((C4+N))" ]; ok "corrupt cache lines fall back to the live check (+$N calls, got $((C5-C4)))" $?
has "f-shipped" "$O5"; ok "corrupt cache still yields the correct verdict" $?
printf 'not a header\n' > "$CACHE"
mf >/dev/null; C6="$(ncalls)"
[ "$C6" -eq "$((C5+N))" ]; ok "a cache with a bad header is ignored (+$N calls, got $((C6-C5)))" $?
mv "$CACHE" "$CL/gone.cache"
mf >/dev/null; C7="$(ncalls)"
[ "$C7" -eq "$((C6+N))" ]; ok "a missing cache falls back to the live check (+$N calls)" $?
if ls "$CL"/.shipped-incomplete.cache.* >/dev/null 2>&1; then ok "no temp file is left behind" 1; else ok "no temp file is left behind" 0; fi

mf >/dev/null; C8="$(ncalls)"
[ "$C8" -eq "$C7" ]; ok "cache rewritten after fallback: warm again, 0 calls" $?
printf '\n# lane rule change\n' >> "$SH/kit.toml"
mf >/dev/null; C9="$(ncalls)"
[ "$C9" -eq "$((C8+N))" ]; ok "a lane-data change invalidates every entry (+$N calls, got $((C9-C8)))" $?
printf '[lane.normal]\nphases = ["build"]\nlight = []\n' > "$OPD/kit.toml"
mf >/dev/null; C10="$(ncalls)"
[ "$C10" -eq "$((C9+N))" ]; ok "an operator lane override invalidates every entry (+$N calls, got $((C10-C9)))" $?

# --- review follow-ups: inode key, gate-script and project-config invalidation, temp cleanup ---
delta_run() { local b; b="$(ncalls)"; mf >/dev/null; echo $(( $(ncalls) - b )); }
: > "$OPD/kit.toml"; mf >/dev/null                 # drop the operator override, re-warm
[ "$(delta_run)" -eq 0 ]; ok "warm again after resetting the operator override" $?

sed 's/late/lete/' "$CL/runs/f-shipped.log" > "$TD/f.swap"
touch -r "$CL/runs/f-shipped.log" "$TD/f.swap"
mv -f "$TD/f.swap" "$CL/runs/f-shipped.log"        # same size, same mtime, new inode
D="$(delta_run)"; [ "$D" -eq 1 ]; ok "a ledger swapped for a same-size same-mtime file re-checks (inode in the key, +$D call)" $?

printf '\n# edited\n' >> "$SH/lib/gate/lane-data.sh"
D="$(delta_run)"; [ "$D" -eq "$N" ]; ok "editing a lib/gate script invalidates every entry (+$D calls)" $?

CP="$TD/proj"; mkdir -p "$CP"; printf '# project config\n' > "$CP/.kit.toml"
( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; cd "$CP" && git init -q . )
mfp() { ( cd "$CP" && NO_COLOR=1 CALLS_FILE="$CALLS" KIT_CONFIG_OPERATOR="$OPD" DWARVES_KIT_LOG_DIR="$CL" bash "$SLT" misfires 2>&1 ); }
delta_p() { local b; b="$(ncalls)"; mfp >/dev/null; echo $(( $(ncalls) - b )); }
delta_p >/dev/null                                  # cold for this cwd: untracked project file
[ "$(delta_p)" -eq 0 ]; ok "untracked project .kit.toml: warm run makes no calls" $?
( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; cd "$CP" && git add .kit.toml && git -c user.name=t -c user.email=t@t commit -qm cfg )
D="$(delta_p)"; [ "$D" -eq "$N" ]; ok "committing the same project .kit.toml (clean flag only) invalidates (+$D calls)" $?
printf '# edit\n' >> "$CP/.kit.toml"
D="$(delta_p)"; [ "$D" -eq "$N" ]; ok "a dirty tracked project .kit.toml invalidates (+$D calls)" $?

# SIGTERM while the cache temp file exists must not leave it behind (mv is stubbed to hang)
mkdir -p "$TD/bin"; printf '#!/bin/bash\nsleep 20\n' > "$TD/bin/mv"; chmod +x "$TD/bin/mv"
touch -t 202601020000 "$CL/runs/g-complete.log"    # force one live re-check so a temp file gets written
set -m
( cd "$CW" && PATH="$TD/bin:$PATH" NO_COLOR=1 CALLS_FILE="$CALLS" KIT_CONFIG_OPERATOR="$OPD" DWARVES_KIT_LOG_DIR="$CL" bash "$SLT" misfires >/dev/null 2>&1 ) &
BG=$!
set +m
i=0; while [ "$i" -lt 150 ] && ! ls "$CL"/.shipped-incomplete.cache.* >/dev/null 2>&1; do sleep 0.2; i=$((i+1)); done
kill -TERM -- "-$BG" 2>/dev/null || true
wait "$BG" 2>/dev/null || true
i=0; while [ "$i" -lt 25 ] && ls "$CL"/.shipped-incomplete.cache.* >/dev/null 2>&1; do sleep 0.2; i=$((i+1)); done   # the trap runs in a child that outlives the wait
if ls "$CL"/.shipped-incomplete.cache.* >/dev/null 2>&1; then ok "SIGTERM mid-write leaves no cache temp file" 1; else ok "SIGTERM mid-write leaves no cache temp file" 0; fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

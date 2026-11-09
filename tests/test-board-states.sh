#!/usr/bin/env bash
# The board row machine is declared once, in lib/board/states.tsv, and every reader derives
# from it (docs/briefs/DECISION-BRIEF-declared-state-machines.md).
#
# Why this suite exists: the vocabulary used to be hand-copied into six files across bash and
# Python with nothing checking they agreed. This suite pins the table's shape, proves every
# reader yields the same sets, proves a new row reaches the readers with no other edit, fails
# on a re-introduced copy, and pins the reopen notice `set` prints.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TSV="$KIT_DIR/lib/board/states.tsv"
BL="$KIT_DIR/lib/board/backlog.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

rows() { awk -F'\t' '!/^#/ && NF' "$TSV"; }

# ---- 1. table shape: 3 tab fields, a known class, every `next` target declared ----
bad="$(rows | awk -F'\t' '
  { st[NR]=$1; cls[NR]=$2; nx[NR]=$3; known[$1]=1; n=NR }
  END {
    for (i=1; i<=n; i++) {
      if (cls[i] !~ /^(active|hold|terminal)$/) print st[i] ": class " cls[i]
      if (cls[i] == "terminal" && nx[i] != "-") print st[i] ": terminal with a next"
      if (nx[i] == "") print st[i] ": empty next (use -)"
      if (nx[i] != "-") { k=split(nx[i], t, " "); for (j=1; j<=k; j++) if (!(t[j] in known)) print st[i] ": next " t[j] " undeclared" }
    }
  }')"
nf="$(rows | awk -F'\t' 'NF != 3' | wc -l | tr -d ' ')"
if [ -z "$bad" ] && [ "$nf" = 0 ]; then pass "states.tsv rows are well-formed"; else fail "states.tsv malformed: ${bad:-$nf rows without 3 fields}"; fi

# ---- 2. every reader yields the same sets ----
want_all="$(rows | cut -f1 | paste -sd ' ' -)"
want_active="$(rows | awk -F'\t' '$2=="active"{print $1}' | paste -sd ' ' -)"
want_term="$(rows | awk -F'\t' '$2=="terminal"{print $1}' | paste -sd ' ' -)"

got="$(bash "$BL" states | paste -sd ' ' -)"
[ "$got" = "$want_all" ] && pass "backlog.sh states = table" || fail "backlog.sh states: $got"
got="$(bash "$BL" states --class active | paste -sd ' ' -)"
[ "$got" = "$want_active" ] && pass "backlog.sh states --class active = table" || fail "backlog.sh --class active: $got"
got="$(bash -c 'source "$1" >/dev/null 2>&1; printf %s "$LEGAL_STATES"' _ "$KIT_DIR/lib/board/board-writeback.sh")"
[ "$got" = "$want_all" ] && pass "board-writeback LEGAL_STATES = table" || fail "board-writeback LEGAL_STATES: $got"

py="$(cd "$KIT_DIR/lib/sync" && python3 -c '
import importlib.util
from importlib.machinery import SourceFileLoader
import sync_core as s, sources.github as g, sources.hermes as h
# board-health has no .py suffix, so the loader is named by hand; load_module() is gone in Python 3.15.
_spec = importlib.util.spec_from_loader("bh", SourceFileLoader("bh", "sweep/board-health"))
bh = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(bh)
order = [x for x in s.BOARD_STATES if x in s.ACTIVE_STATUSES]
print(" ".join(s.BOARD_STATES))
print(" ".join(order))
print(" ".join(x for x in s.BOARD_STATES if x in s.TERMINAL_STATUSES))
print(g.ACTIVE == h.ACTIVE == s.ACTIVE_STATUSES and list(bh.ACTIVE) == order)
' 2>&1)"
expect="$(printf '%s\n%s\n%s\nTrue' "$want_all" "$want_active" "$want_term")"
[ "$py" = "$expect" ] && pass "sync_core, github, hermes, board-health = table" || fail "python readers disagree: $py"

# ---- 3. a new row reaches the readers with no other edit (the point of declaring it) ----
mkdir -p "$TMP/kit/lib"
cp -R "$KIT_DIR/lib/board" "$KIT_DIR/lib/gate" "$KIT_DIR/lib/sync" "$TMP/kit/lib/"
printf 'reviewing\tactive\tshipped\n' >> "$TMP/kit/lib/board/states.tsv"
got="$(bash "$TMP/kit/lib/board/backlog.sh" states --class active | tail -1)"
gotpy="$(cd "$TMP/kit/lib/sync" && python3 -c 'import sync_core as s; print("reviewing" in s.ACTIVE_STATUSES)')"
if [ "$got" = reviewing ] && [ "$gotpy" = True ]; then pass "an added row reaches bash and python readers"; else fail "added row not derived: bash=$got py=$gotpy"; fi

# ---- 4. a missing table is fatal, never an empty vocabulary ----
mv "$TMP/kit/lib/board/states.tsv" "$TMP/kit/lib/board/states.tsv.off"
if out="$(bash "$TMP/kit/lib/board/backlog.sh" states 2>&1)"; then
  fail "backlog.sh ran with no states.tsv: $out"
else
  case "$out" in *FATAL*states.tsv*) pass "missing states.tsv is fatal" ;; *) fail "missing table, wrong error: $out" ;; esac
fi

# ---- 5. no code file hardcodes the active set again ----
# A copy is any line naming every active state. Docs (*.md) and the table itself are exempt.
first_active="$(rows | awk -F'\t' '$2=="active"{print $1; exit}')"
copies="$(cd "$KIT_DIR" && grep -rnIw "$first_active" lib hooks bin 2>/dev/null \
  | grep -v '^lib/board/states.tsv:' | grep -v '\.md:' | grep -v '^lib/stats/' \
  | awk -v want="$want_active" '{ n=split(want, w, " "); ok=1; for (i=1; i<=n; i++) if ($0 !~ ("[^a-z]" w[i] "[^a-z]")) ok=0; if (ok) print }')"
[ -z "$copies" ] && pass "no hardcoded copy of the active set outside states.tsv" || fail "hardcoded vocabulary, derive it from states.tsv instead:
$copies"

# The scan above must catch a planted copy (negative control on the detector itself).
plant="$TMP/plant.sh"
printf 'X="%s"\n' "$want_active" > "$plant"
hit="$(awk -v want="$want_active" '{ n=split(want, w, " "); ok=1; for (i=1; i<=n; i++) if ($0 !~ ("[^a-z]" w[i] "[^a-z]")) ok=0; if (ok) print }' "$plant")"
[ -n "$hit" ] && pass "copy detector catches a planted copy" || fail "copy detector missed a planted copy"

# ---- 6. set: a move out of a terminal state prints the reopen notice; others stay quiet ----
B="$TMP/b.md"
printf '| ID | T | Status |\n|---|---|---|\n| ID-001 | a | shipped [PR 1] |\n| ID-002 | b | queued |\n' > "$B"
err="$(BACKLOG_FILE="$B" bash "$BL" set ID-001 queued "repair" 2>&1 >/dev/null)"
case "$err" in *"reopens from terminal 'shipped' to 'queued'"*) pass "terminal -> active prints the reopen notice" ;; *) fail "no reopen notice: $err" ;; esac
err="$(BACKLOG_FILE="$B" bash "$BL" set ID-002 claimed 2>&1 >/dev/null)"
[ -z "$err" ] && pass "active -> active is quiet" || fail "active move printed: $err"
BACKLOG_FILE="$B" bash "$BL" set ID-002 dropped "no" >/dev/null 2>&1
err="$(BACKLOG_FILE="$B" bash "$BL" set ID-002 dropped "still no" 2>&1 >/dev/null)"
[ -z "$err" ] && pass "terminal -> same terminal (note update) is quiet" || fail "same-state set printed: $err"
c="$(awk -F'|' '/^\| *ID-002 *\|/ { c=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", c); print c }' "$B")"
[ "$c" = "dropped [still no]" ] && pass "terminal note still supersedes (class-derived)" || fail "terminal note rule: $c"

# ---- 6b. a large board: setting its FIRST row must not die on SIGPIPE (review finding) ----
L="$TMP/large.md"
{ printf '| ID | T | Status |\n|---|---|---|\n'
  i=1; while [ "$i" -le 1500 ]; do printf '| ID-%04d | a row title long enough to fill the pipe buffer quickly %d | queued [note %d] |\n' "$i" "$i" "$i"; i=$((i + 1)); done
} > "$L"
out="$(BACKLOG_FILE="$L" bash "$BL" set ID-0001 claimed 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q '^| ID-0001 .*| claimed' "$L"; then pass "set on the first row of a 1500-row board writes (rc 0)"; else fail "large-board set rc=$rc: $out"; fi

# ---- 7. machine and states verbs: shape and refusals ----
out="$(bash "$BL" machine)"
[ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'state\tclass\tnext')" ] && [ "$(printf '%s\n' "$out" | tail -n +2)" = "$(rows)" ] \
  && pass "machine prints the header and the table" || fail "machine output: $out"
got="$(bash "$BL" states extra-arg | paste -sd ' ' -)"; rc=$?
[ "$rc" = 0 ] && [ "$got" = "$want_all" ] && pass "states with a stray argument keeps the old output and exit 0" || fail "states extra-arg rc=$rc: $got"
bash "$BL" states --class bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && pass "states --class bogus exits 64" || fail "states --class bogus rc=$rc"

# ---- 8. the row-to-card map is declared once (native-map.tsv); the mirror and the cleanup derive from it ----
NM="$KIT_DIR/lib/board/native-map.tsv"
nm_rows() { awk -F'\t' '!/^#/ && NF' "$NM"; }
known_states=" $want_all "
bad="$(nm_rows | awk -F'\t' -v known="$known_states" '
  NF != 2 { print $0 ": " NF " fields"; next }
  index(known, " " $1 " ") == 0 { print $1 ": not a state in states.tsv" }
  $2 !~ /^(triage|ready|blocked)$/ { print $1 ": native " $2 " is not CLI-reachable" }
  seen[$1]++ { print $1 ": declared twice" }')"
[ -z "$bad" ] && pass "native-map.tsv rows are well-formed and name declared states" || fail "native-map.tsv malformed: $bad"

mirror_map="$(for s in $want_all bogus; do printf '%s=%s\n' "$s" "$(bash -c 'source "$1"; _target_native "$2"' _ "$KIT_DIR/lib/board/board-mirror.sh" "$s")"; done)"
want_map="$(for s in $want_all bogus; do printf '%s=%s\n' "$s" "$(nm_rows | awk -F'\t' -v s="$s" '$1 == s { print $2 }')"; done)"
[ "$mirror_map" = "$want_map" ] && pass "board-mirror _target_native = native-map.tsv" || fail "mirror map differs:
$mirror_map"

cl="$(python3 - "$KIT_DIR" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("bmc", sys.argv[1] + "/lib/board/board-mirror-cleanup.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print("\n".join(f"{k}={v}" for k, v in m.ACTIVE_TARGET.items()))
PY
)"
[ "$cl" = "$(nm_rows | awk -F'\t' '{ print $1 "=" $2 }')" ] && pass "board-mirror-cleanup ACTIVE_TARGET = native-map.tsv" || fail "cleanup map differs: $cl"

mkdir -p "$TMP/kit2/lib"; cp -R "$KIT_DIR/lib/board" "$KIT_DIR/lib/mega" "$TMP/kit2/lib/"
printf 'reviewing\tready\n' >> "$TMP/kit2/lib/board/native-map.tsv"
got="$(bash -c 'source "$1"; _target_native reviewing' _ "$TMP/kit2/lib/board/board-mirror.sh")"
gotpy="$(python3 -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("bmc", sys.argv[1] + "/lib/board/board-mirror-cleanup.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.ACTIVE_TARGET.get("reviewing"))' "$TMP/kit2")"
[ "$got" = ready ] && [ "$gotpy" = ready ] && pass "an added map row reaches bash and python with no other edit" || fail "added map row not derived: bash=$got py=$gotpy"

nm_copies="$(cd "$KIT_DIR" && grep -rnIE 'queued.*triage' lib hooks bin 2>/dev/null | grep -v '\.md:' | grep -v '/tests/' | grep -v '\.tsv:' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)')"
[ -z "$nm_copies" ] && pass "no code file hardcodes the row-to-card map" || fail "hardcoded map, derive it from native-map.tsv instead:
$nm_copies"
printf 'M = {"queued": "triage"}\n' > "$TMP/plant.py"
[ -n "$(grep -E 'queued.*triage' "$TMP/plant.py")" ] && pass "map copy detector catches a planted copy" || fail "map copy detector missed a planted copy"

[ "$FAILED" -eq 0 ] && { echo "All board-states tests passed."; exit 0; }
echo "$FAILED board-states test(s) failed."; exit 1

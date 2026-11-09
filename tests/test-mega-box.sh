#!/usr/bin/env bash
# The mega ROADMAP box and id grammar is declared once, in lib/mega/box.tsv, and every reader derives
# from it (same shape as lib/board/states.tsv, tests/test-board-states.sh).
#
# Why this suite exists: about ten readers parsed `- [ ] SG-NN ...` / `- [x] NN-slug ...` with their own
# regexes. They disagreed on `[X]`, on `[~]` and `[-]`, and on SG-NN versus NN-slug ids, so `mega review`
# could not see an SG-NN roadmap and `megagoals` counted a different total than `mega status`.
# This suite pins the table's shape, proves bash and Python agree, proves each reader applies it, proves a
# new alias reaches the readers with no other edit, and fails on a re-introduced copy.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TSV="$KIT_DIR/lib/mega/box.tsv"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got '$2' want '$3'"; fi; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

rows() { awk -F'\t' '!/^#/ && NF' "$TSV"; }
BOX="$KIT_DIR/lib/mega/box.sh"

# ---- 1. table shape ----
bad="$(rows | awk -F'\t' '
  NF != 5 { print $0 ": " NF " fields"; next }
  $1 !~ /^(box|id)$/ { print $2 ": kind " $1 }
  $1 == "box" && $3 !~ /^\[[^]^\\]\]$/ { print $2 ": token " $3 }
  $1 == "box" && $4 !~ /^(active|hold|terminal)$/ { print $2 ": class " $4 }
  $1 == "box" { if ($5 != "-") { k = split($5, a, " "); for (j = 1; j <= k; j++) if (a[j] !~ /^\[[^]^\\]\]$/) print $2 ": alias " a[j] } }
  $1 == "id" && ($4 != "-" || $5 != "-") { print $2 ": id row with a class or alias" }
')"
[ -z "$bad" ] && pass "box.tsv rows are well-formed" || fail "box.tsv malformed: $bad"
dups="$(rows | awk -F'\t' '$1 == "box" { c[substr($3,2,1)]++; if ($5 != "-") { k = split($5, a, " "); for (j = 1; j <= k; j++) c[substr(a[j],2,1)]++ } } END { for (x in c) if (c[x] > 1) print x }')"
[ -z "$dups" ] && pass "no character belongs to two boxes" || fail "character in two boxes: $dups"

# ---- 2. the bash helper answers from the table ----
eq "box_chars open" "$(bash "$BOX" chars open)" " "
eq "box_chars done" "$(bash "$BOX" chars done)" "xX"
eq "box_chars parked puts the dash last" "$(bash "$BOX" chars parked)" "~-"
eq "box_class open done" "$(bash "$BOX" class open done)" "[ xX]"
eq "box_token done is the canonical writer form" "$(bash "$BOX" token done)" "[x]"
eq "box_name resolves an alias" "$(bash "$BOX" name X)" "done"
eq "box_name resolves the parked alias" "$(bash "$BOX" name -)" "parked"
eq "box_name of an undeclared character is empty" "$(bash "$BOX" name q)" ""
eq "box_id_re names one row" "$(bash "$BOX" id sg)" "(SG-[0-9]+)"
want_id="($(rows | awk -F'\t' '$1=="id"{print $3}' | paste -sd '|' -))"
eq "box_id_re ORs every id row" "$(bash "$BOX" id)" "$want_id"

# ---- 3. Python reads the same table ----
py="$(python3 - "$KIT_DIR" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("box", sys.argv[1] + "/lib/mega/box.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.chars("open"), "|", m.chars("done"), "|", m.chars("parked"), "|", m.box_class("open", "done"), "|", m.name_of("-"), "|", m.id_re())
PY
)"
sh="$(printf '%s | %s | %s | %s | %s | %s' "$(bash "$BOX" chars open)" "$(bash "$BOX" chars done)" "$(bash "$BOX" chars parked)" "$(bash "$BOX" class open done)" "$(bash "$BOX" name -)" "$(bash "$BOX" id)")"
eq "box.py = box.sh (chars, class, name, id)" "$py" "$(printf '%s' "$sh" | sed 's/| (/| (?:/')"

# ---- fixture: every box form and both id forms in one roadmap ----
RM="$TMP/m/fixture"; mkdir -p "$RM/goals"
cat > "$RM/ROADMAP.md" <<'EOF'
# Mega-goal: Box Fixture

## Sub-goals
- [ ] SG-01 open sg , auto , depends SG-02
- [x] SG-02 done sg , auto , PR #2 merged abc1234
- [X] SG-03 legacy upper , gate , PR #3 merged abc1234
- [~] SG-04 parked sg , auto
- [-] SG-05 dash parked sg , auto
- [ ] 06-slug-open (repo), prose, `auto`
- [x] 07-slug-done (repo), prose, PR #7 merged abc1234
- [~] 08-slug-parked (repo), rehomed
EOF
GH="$TMP/gh"; printf '#!/bin/bash\nexit 1\n' > "$GH"; chmod +x "$GH"
GT="$TMP/git"; printf '#!/bin/bash\nexit 1\n' > "$GT"; chmod +x "$GT"

# ---- 4. orchestrate: open and done are visible, parked never is, never auto-picked ----
subs="$(TIER4_CLOSE=0 bash -c 'source "$1/lib/queue/orchestrate.sh"; _subgoals "$2"' _ "$KIT_DIR" "$RM/ROADMAP.md" 2>&1 | tr '\t\n' ':;')"
eq "orchestrate _subgoals: SG ids only, parked invisible, [X] counts as done" "$subs" "SG-01:auto:0;SG-02:auto:1;SG-03:gate:1;"
nxt="$(TIER4_CLOSE=0 bash -c 'source "$1/lib/queue/orchestrate.sh"; _next "$2"' _ "$KIT_DIR" "$RM/ROADMAP.md" 2>&1 | tr '\t' ':')"
eq "orchestrate _next picks the open box" "$nxt" "SG-01:auto"
PK="$TMP/m/parkedonly"; mkdir -p "$PK"; printf -- '- [x] SG-01 a , auto , PR #1\n- [~] SG-02 b , auto\n- [-] SG-03 c , auto\n' > "$PK/ROADMAP.md"
nxt="$(TIER4_CLOSE=0 bash -c 'source "$1/lib/queue/orchestrate.sh"; _next "$2"' _ "$KIT_DIR" "$PK/ROADMAP.md" 2>&1)"
eq "orchestrate never auto-picks a parked box" "$nxt" ""
out="$(bash "$KIT_DIR/lib/queue/orchestrate.sh" flip "$PK" SG-02 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q '^- \[~\] SG-02' "$PK/ROADMAP.md"; then pass "flip refuses a parked box and leaves the file alone"; else fail "flip on a parked box rc=$rc: $out"; fi
cp "$RM/ROADMAP.md" "$TMP/flip.md"; mkdir -p "$TMP/flipdir"; cp "$RM/ROADMAP.md" "$TMP/flipdir/ROADMAP.md"
bash "$KIT_DIR/lib/queue/orchestrate.sh" flip "$TMP/flipdir" SG-01 >/dev/null 2>&1
eq "flip writes the canonical done token" "$(grep -c '^- \[x\] SG-01 ' "$TMP/flipdir/ROADMAP.md")" "1"
eq "flip leaves every other line alone" "$(diff "$TMP/flip.md" "$TMP/flipdir/ROADMAP.md" | grep -c '^[<>]')" "2"

# ---- 5. mega status: both id forms, [X] done, [~] and [-] informational ----
st="$(GH_BIN="$GH" GIT_BIN="$GT" bash "$KIT_DIR/lib/mega/mega.sh" status fixture --megagoals-root "$TMP/m" --code-root "$TMP" 2>&1 | awk 'NF >= 3 && $0 ~ /(SG-|0[0-9]-)/ { print $2 "=" $3 }' | paste -sd ' ' -)"
eq "mega status labels every grammar row" "$st" "SG-01=PENDING SG-02=CLAIM-UNVERIFIED SG-03=CLAIM-UNVERIFIED SG-04=INFO SG-05=INFO 06-slug-open=PENDING 07-slug-done=CLAIM-UNVERIFIED 08-slug-parked=INFO"

# ---- 6. megagoals: done counts [X]; parked is not done and is open-not-active ----
REPO="$TMP/repo"; mkdir -p "$REPO/_meta/megagoals/fixture"; cp "$RM/ROADMAP.md" "$REPO/_meta/megagoals/fixture/ROADMAP.md"
ml="$(bash "$KIT_DIR/lib/goal/megagoals.sh" list --repo "$REPO" 2>&1 | head -1 | awk '{print $2}')"
eq "megagoals counts done 3 of total 8 (parked is not done)" "$ml" "3/8"
mkdir -p "$REPO/_meta/megagoals/donepark"; printf '## Sub-goals\n- [x] SG-01 a , auto , PR #1\n- [~] SG-02 b , auto\n' > "$REPO/_meta/megagoals/donepark/ROADMAP.md"
ml="$(bash "$KIT_DIR/lib/goal/megagoals.sh" list --repo "$REPO" 2>&1 | grep -c '^donepark ')"
eq "megagoals hides a mega whose only open work is parked" "$ml" "0"
ml="$(bash "$KIT_DIR/lib/goal/megagoals.sh" list --repo "$REPO" --all 2>&1 | grep '^donepark ' | awk '{print $2}')"
eq "megagoals --all shows it as 1/2" "$ml" "1/2"

# ---- 7. board mirror: progress counts parked in the total; a parked-only mega is not active ----
mg="$(bash "$KIT_DIR/lib/board/board-mirror.sh" extract-megas "$REPO" r 2>&1)"
eq "mirror emits the active mega with progress 3/8" "$(printf '%s\n' "$mg" | awk -F'\t' '$3 == "r/fixture" { print $5 }')" "progress 3/8"
eq "mirror skips the mega with no open box" "$(printf '%s\n' "$mg" | grep -c 'donepark')" "0"

# ---- 8. mega review and report parse BOTH id forms ----
rv="$(python3 - "$KIT_DIR" "$RM/ROADMAP.md" <<'PY'
import importlib.util, sys
kit, r = sys.argv[1:3]
s = importlib.util.spec_from_file_location("mr", kit + "/lib/mega/mega-review.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(" ".join(f"{b}{i}" for b, i, _ in m.parse_roadmap(r)))
s = importlib.util.spec_from_file_location("mp", kit + "/lib/mega/mega-report.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(" ".join(f"{'x' if g['checked'] else '_'}{g['num']}" for g in m.parse_roadmap(r)))
PY
)"
eq "mega-review rows: both id forms, every box" "$(printf '%s\n' "$rv" | head -1)" " SG-01 xSG-02 XSG-03 ~SG-04 -SG-05  06-slug-open x07-slug-done ~08-slug-parked"
eq "mega-report rows: both id forms, open and done only" "$(printf '%s\n' "$rv" | tail -1)" "_01 x02 x03 _06 x07"

# ---- 9. board work: an open box of either id form is a mega row; parked and done are not ----
WR="$TMP/work"; mkdir -p "$WR/_meta/megagoals/fixture/goals"; cp "$RM/ROADMAP.md" "$WR/_meta/megagoals/fixture/ROADMAP.md"
printf -- '- [ ] 04b-suffixed (repo), prose\n- [ ] 2026-11-09 a dated note, not a sub-goal\n' >> "$WR/_meta/megagoals/fixture/ROADMAP.md"
git -C "$WR" init -q 2>/dev/null; printf '| ID | Item | Notes & source | Status |\n|----|------|----------------|--------|\n' > "$WR/_meta/BACKLOG.md"
items="$(ORCA_BIN=/nonexistent bash "$KIT_DIR/lib/board/work.sh" --json --repo-root "$WR" --backlog-file "$WR/_meta/BACKLOG.md" --code-root "$WR" 2>&1 | jq -r '[.items[] | select(.origin == "mega") | .item] | sort | join(" ")' 2>&1)"
eq "work.sh lists open boxes of both id forms only" "$items" "fixture/04b-suffixed fixture/06-slug-open fixture/SG-01"

# ---- 10. board-mirror-cleanup: a mega is active only with an open box ----
CR="$TMP/cleanup"; mkdir -p "$CR/_meta/megagoals/live" "$CR/_meta/megagoals/parkedonly"; git -C "$CR" init -q 2>/dev/null
cp "$RM/ROADMAP.md" "$CR/_meta/megagoals/live/ROADMAP.md"; cp "$PK/ROADMAP.md" "$CR/_meta/megagoals/parkedonly/ROADMAP.md"
printf '| ID | Item | Notes & source | Status |\n|----|------|----------------|--------|\n' > "$CR/_meta/BACKLOG.md"
printf 'r %s/_meta/BACKLOG.md on\n' "$CR" > "$TMP/reg.txt"
act="$(python3 - "$KIT_DIR" "$TMP/reg.txt" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("bmc", sys.argv[1] + "/lib/board/board-mirror-cleanup.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(" ".join(f"{k}={v}" for k, v in sorted(m.load_sources(sys.argv[2], "working")["r"]["megas"].items())))
PY
)"
eq "cleanup: active needs an open box, parked is not active" "$act" "live=True parkedonly=False"

# ---- 11. board.sh rollup gate and repohygiene use the same open/done sets ----
eq "board.sh --with-mega skips a mega with no open box" "$(GH_BIN="$GH" GIT_BIN="$GT" bash "$KIT_DIR/lib/board/board.sh" board --with-mega --backlog-file "$CR/_meta/BACKLOG.md" --mega-code-root "$TMP" 2>&1 | grep -c '^  parkedonly')" "0"
eq "board.sh --with-mega rolls up a mega with an open box" "$(GH_BIN="$GH" GIT_BIN="$GT" bash "$KIT_DIR/lib/board/board.sh" board --with-mega --backlog-file "$CR/_meta/BACKLOG.md" --mega-code-root "$TMP" 2>&1 | grep -c '^  live')" "1"
hy="$(bash -c '
  eval "$(sed -n "/^mg_docs()/,/^}/p; /^mg_boxes()/,/^}/p" "$1/lib/repohygiene/repohygiene.sh")"
  grep -n "mg_boxes \"\$slug\"" "$1/lib/repohygiene/repohygiene.sh" | sed "s/^[0-9]*://"' _ "$KIT_DIR")"
case "$hy" in *'~-'*|*"'xX'"*) fail "repohygiene still passes literal box chars: $hy" ;; *) pass "repohygiene passes box sets from the table" ;; esac

# ---- 12. an added alias reaches bash readers with no other edit ----
cp -R "$KIT_DIR/lib" "$TMP/kit-lib"; mkdir -p "$TMP/kit"; mv "$TMP/kit-lib" "$TMP/kit/lib"
awk -F'\t' -v OFS='\t' '$1=="box" && $2=="parked" { $5 = $5 " [/]" } { print }' "$TSV" > "$TMP/kit/lib/mega/box.tsv"
mkdir -p "$TMP/m/alias"; { cat "$RM/ROADMAP.md"; printf -- '- [/] 09-slashed (repo), parked by a new alias\n'; } > "$TMP/m/alias/ROADMAP.md"
got="$(GH_BIN="$GH" GIT_BIN="$GT" bash "$TMP/kit/lib/mega/mega.sh" status alias --megagoals-root "$TMP/m" --code-root "$TMP" 2>&1 | awk '$2 == "09-slashed" { print $3 }')"
eq "an added parked alias is INFO in mega status" "$got" "INFO"
gotn="$(bash "$TMP/kit/lib/mega/box.sh" name /)"
eq "box.sh resolves the added alias" "$gotn" "parked"
gotp="$(python3 - "$TMP/kit" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("box", sys.argv[1] + "/lib/mega/box.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.name_of("/"))
PY
)"
eq "box.py resolves the added alias" "$gotp" "parked"

# ---- 13. a missing table is fatal, never an empty grammar ----
mv "$TMP/kit/lib/mega/box.tsv" "$TMP/kit/lib/mega/box.tsv.off"
if out="$(bash "$TMP/kit/lib/mega/mega.sh" status alias --megagoals-root "$TMP/m" --code-root "$TMP" 2>&1)"; then
  fail "mega status ran with no box.tsv: $out"
else
  case "$out" in *FATAL*box.tsv*) pass "missing box.tsv is fatal" ;; *) fail "missing table, wrong error: $out" ;; esac
fi

# ---- 14. no reader spells the grammar again ----
# A copy is code that writes the checkbox bullet, a box character set, or the id forms itself. Comments, docs,
# tests, the table and its two readers are exempt. Other checkbox grammars (spec tasks, staging items, backlog
# rows) live outside these directories.
PAT='- \\?\[|- ['"'"'"]*\[|-\\ \\\[|'"'"'xX'"'"'|\[:space:\]~|\(x\| \)|SG-\[0-9\]|\[0-9\]\+-\[A-Za-z'
scan() { # <root>
  (cd "$1" && grep -rnIE -e "$PAT" lib/mega lib/queue lib/goal lib/board lib/repohygiene 2>/dev/null \
    | grep -v '\.md:' | grep -v '/tests/' | grep -v '\.tsv:' | grep -v '^lib/mega/box\.' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)')
}
copies="$(scan "$KIT_DIR")"
[ -z "$copies" ] && pass "no reader hardcodes the box grammar outside box.tsv" || fail "hardcoded box grammar, derive it from box.tsv instead:
$copies"
# The scan must catch a planted copy (negative control on the detector itself).
plant="$TMP/plant"; mkdir -p "$plant/lib/mega"
printf 'grep -E "^- \\[[ xX]\\] SG-[0-9]+" "$f"\n' > "$plant/lib/mega/reader.sh"
[ -n "$(scan "$plant")" ] && pass "copy detector catches a planted copy" || fail "copy detector missed a planted copy"

[ "$FAILED" -eq 0 ] && { echo "All mega-box tests passed."; exit 0; }
echo "$FAILED mega-box test(s) failed."; exit 1

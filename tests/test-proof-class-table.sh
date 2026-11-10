#!/usr/bin/env bash
# test-proof-class-table.sh -- the proof classes and their shared stateful words are declared once,
# in lib/gate/proof-classes.tsv, and both classifiers read it: proof-ledger.sh `classify` (the branch
# diff, ship time) and proof-gate.sh `class` (the task text, plan time).
#
# Why: the two used to carry their own hand-typed keyword lists, so the same work could classify
# differently at plan time and at ship time. Only shared words and the class names live in the table;
# each classifier keeps its own input rules and its own extra words.
#
# Run: bash tests/test-proof-class-table.sh   (exit 0 = all green)
set -uo pipefail
# Fence off the host operator kit.toml: a real operator file must not change what this suite asserts.
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TSV="$KIT_DIR/lib/gate/proof-classes.tsv"
LEDGER="$KIT_DIR/lib/gate/proof-ledger.sh"
GATE="$KIT_DIR/lib/gate/proof-gate.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
export DWARVES_KIT_LOG_DIR="$TMP/logs"

rows() { awk -F'\t' '!/^#/ && NF' "$TSV"; }

# ---- 1. table shape ----
# class rows: kind, name, rank (unique ints from 0). stateful rows: kind, ERE, a sample task text it matches.
bad="$(rows | awk -F'\t' '
  NF != 3 { print $0 ": " NF " fields"; next }
  $1 == "class" { if ($3 !~ /^[0-9]+$/) print $2 ": rank " $3 " is not an integer"; if (seen[$3]++) print $2 ": rank " $3 " declared twice"; names[$2] = 1; next }
  $1 == "stateful" { if ($3 == "") print $2 ": no sample"; next }
  { print $1 ": unknown kind" }
  END { split("inert behavioral stateful", want, " "); for (i = 1; i <= 3; i++) if (!(want[i] in names)) print want[i] ": class missing" }')"
[ -z "$bad" ] && pass "proof-classes.tsv rows are well-formed and declare the three classes" || fail "proof-classes.tsv malformed: $bad"

rank_of() { rows | awk -F'\t' -v n="$1" '$1=="class" && $2==n { print $3 }'; }
if [ "$(rank_of inert)" -lt "$(rank_of behavioral)" ] && [ "$(rank_of behavioral)" -lt "$(rank_of stateful)" ]; then
  pass "rank is inert < behavioral < stateful"
else
  fail "rank order: inert=$(rank_of inert) behavioral=$(rank_of behavioral) stateful=$(rank_of stateful)"
fi

badere=""
while IFS=$'\t' read -r _ pat _; do
  printf 'x' | grep -E -e "$pat" >/dev/null 2>&1; [ $? -le 1 ] || badere="$badere [$pat]"
done < <(rows | awk -F'\t' '$1=="stateful"')
[ -z "$badere" ] && pass "every stateful word is a valid ERE" || fail "invalid ERE:$badere"

# ---- 2. the classes subcommand reads the table, highest rank first ----
want_classes="$(rows | awk -F'\t' '$1=="class" { print $3 "\t" $2 }' | sort -rn | cut -f2 | paste -sd ' ' -)"
got="$(bash "$GATE" classes | paste -sd ' ' -)"
[ "$got" = "$want_classes" ] && pass "proof-gate.sh classes = table (highest rank first)" || fail "classes: '$got' want '$want_classes'"

# ---- 3. every shared word makes BOTH classifiers say stateful ----
# Ledger side: a throwaway repo; the branch adds one code file whose commit subject is the sample.
R="$TMP/repo"
git init -q -b main "$R" && git -C "$R" config user.email t@example.com && git -C "$R" config user.name t
git -C "$R" commit -q --allow-empty -m init
BASE="$(git -C "$R" rev-parse main)"
ledger_class() {   # <subject> -> class of a one-code-file branch with that subject
  git -C "$R" checkout -q main && git -C "$R" branch -q -D probe 2>/dev/null
  git -C "$R" checkout -q -b probe && mkdir -p "$R/src" && printf 'echo hi\n' > "$R/src/app.sh"
  git -C "$R" add src/app.sh && git -C "$R" commit -q -m "$1"
  bash "$LEDGER" classify "$R" "$BASE" 2>/dev/null
}
sample_bad=""
while IFS=$'\t' read -r _ pat sample; do
  l="$(ledger_class "feat: $sample")"; g="$(bash "$GATE" class "$sample" 2>/dev/null)"
  [ "$l" = stateful ] && [ "$g" = stateful ] || sample_bad="$sample_bad [$pat: ledger=$l gate=$g]"
done < <(rows | awk -F'\t' '$1=="stateful"')
[ -z "$sample_bad" ] && pass "every table word classifies stateful in both classifiers" || fail "words not honored:$sample_bad"

# A plain code change is still behavioral in the ledger and not stateful in the gate.
l="$(ledger_class 'feat: add a flag')"; g="$(bash "$GATE" class 'add a flag to the parser' 2>/dev/null)"
[ "$l" = behavioral ] && [ "$g" = behavioral ] && pass "an unrelated change stays behavioral in both" || fail "plain change: ledger=$l gate=$g"

# Each classifier keeps its OWN extra words (input-specific rules do not move into the table).
git -C "$R" checkout -q main && git -C "$R" branch -q -D probe 2>/dev/null; git -C "$R" checkout -q -b probe
mkdir -p "$R/app/db" && printf 'echo hi\n' > "$R/app/db/x.sh" && git -C "$R" add app && git -C "$R" commit -q -m 'feat: tweak'
[ "$(bash "$LEDGER" classify "$R" "$BASE" 2>/dev/null)" = stateful ] && pass "ledger keeps its own /db/ path word" || fail "ledger lost the /db/ path word"
[ "$(bash "$GATE" class 'triage the alert' 2>/dev/null)" = stateful ] && [ "$(bash "$GATE" class 'close the incident' 2>/dev/null)" = stateful ] \
  && pass "gate keeps its own triage and incident words" || fail "gate lost triage/incident"

# ---- 4. a new table row reaches both classifiers with no other edit ----
mkdir -p "$TMP/kit"
cp -R "$KIT_DIR/lib" "$TMP/kit/lib"
printf 'stateful\tzqxword\tzqxword rollover\n' >> "$TMP/kit/lib/gate/proof-classes.tsv"
l="$(git -C "$R" checkout -q main; git -C "$R" branch -q -D probe 2>/dev/null; git -C "$R" checkout -q -b probe; mkdir -p "$R/src"; printf 'x\n' > "$R/src/b.sh"; git -C "$R" add src/b.sh; git -C "$R" commit -q -m 'feat: zqxword rollover'; bash "$TMP/kit/lib/gate/proof-ledger.sh" classify "$R" "$BASE" 2>/dev/null)"
g="$(bash "$TMP/kit/lib/gate/proof-gate.sh" class 'zqxword rollover' 2>/dev/null)"
l0="$(bash "$LEDGER" classify "$R" "$BASE" 2>/dev/null)"
[ "$l" = stateful ] && [ "$g" = stateful ] && [ "$l0" = behavioral ] \
  && pass "an added word reaches both classifiers (and not the unedited copy)" || fail "added word: ledger=$l gate=$g unedited-ledger=$l0"

# ---- 5. a missing table is fatal, never an empty vocabulary ----
mv "$TMP/kit/lib/gate/proof-classes.tsv" "$TMP/kit/lib/gate/proof-classes.tsv.off"
for s in proof-ledger.sh proof-gate.sh; do
  if out="$(bash "$TMP/kit/lib/gate/$s" classes 2>&1 || bash "$TMP/kit/lib/gate/$s" classify "$R" "$BASE" 2>&1)"; then
    case "$out" in *FATAL*proof-classes*) pass "$s: missing table is fatal" ;; *) fail "$s ran with no table: $out" ;; esac
  else
    case "$out" in *FATAL*proof-classes*) pass "$s: missing table is fatal" ;; *) fail "$s: missing table, wrong error: $out" ;; esac
  fi
done

# ---- 6. no classifier hardcodes the shared vocabulary again ----
# A copy is a non-comment code line in lib/gate/*.sh (the helper is exempt) that carries four or more
# table words verbatim (one word alone is ordinary code, e.g. `deployable`), or names all three
# classes on one line.
scan() {   # <file...> -> offending lines
  local f words="$TMP/words"
  rows | awk -F'\t' '$1=="stateful" { print $2 }' > "$words"
  for f in "$@"; do
    grep -vE '^[[:space:]]*#' "$f" | awk -v F="$(basename "$f")" '
      NR == FNR { w[++n] = $0; next }
      /stateful/ && /behavioral/ && /inert/ { print F ": all three class names on one line: " $0 }
      { hits = 0; for (i = 1; i <= n; i++) if (index($0, w[i])) hits++
        if (hits >= 4) print F ": " hits " table words typed inline: " $0 }' "$words" -
  done
}
files=()
for f in "$KIT_DIR"/lib/gate/*.sh; do [ "$(basename "$f")" = proof-classes.sh ] || files+=("$f"); done
copies="$(scan "${files[@]}")"
[ -z "$copies" ] && pass "no classifier in lib/gate types the shared words or the class list inline" || fail "hardcoded vocabulary, read proof-classes.tsv instead:
$copies"

# The scan must catch a planted copy of each kind (negative control on the detector itself).
plant="$TMP/planted.sh"
five="$(rows | awk -F'\t' '$1=="stateful" && n < 5 { printf "%s%s", sep, $2; sep="|"; n++ }')"
printf 'if grep -qE "%s" <<<"$x"; then echo hit; fi\n' "$five" > "$plant"
[ -n "$(scan "$plant")" ] && pass "copy detector catches a planted shared word list" || fail "copy detector missed a planted shared word list"
printf 'case "$c" in stateful|behavioral|inert) ok;; esac\n' > "$plant"
[ -n "$(scan "$plant")" ] && pass "copy detector catches a planted class list" || fail "copy detector missed a planted class list"
printf '# a comment may name stateful behavioral inert and %s\n' "$five" > "$plant"
[ -z "$(scan "$plant")" ] && pass "copy detector ignores comments" || fail "copy detector flagged a comment"

echo
[ "$FAILED" = 0 ] && echo "ALL PASS" || echo "$FAILED FAILED"
exit "$FAILED"

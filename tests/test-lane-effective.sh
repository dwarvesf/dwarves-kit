#!/usr/bin/env bash
# test-lane-effective.sh -- one effective-lane resolver (lane-data.sh lane_effective) and a validated plain
# `gate-ledger.sh start`. Order: last START-AMEND, else first START, else the spec `Lane:` header, else (with
# --default) the classifier default. A stray START lane (fix, light, standard) in an old ledger is read as absent.
#
# Run: bash tests/test-lane-effective.sh   (exit 0 = all green)

set -uo pipefail
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
export DWARVES_KIT_LOG_DIR; DWARVES_KIT_LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
PASS=0; FAIL=0
check() {
  if eval "$2"; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi
}
gl() { bash "$GL" "$@"; }
RUNS="$DWARVES_KIT_LOG_DIR/runs"; mkdir -p "$RUNS"
log() { cat "$RUNS/$1.log" 2>/dev/null; }
# write a legacy ledger by hand (old data is never produced by the validated writer)
legacy() { # rid then ledger lines
  local rid="$1"; shift; printf '%s\n' "$@" > "$RUNS/$rid.log"
}
S1='2026-01-01T00:00:00Z | START | lane=%s classified=normal type=feature repo=r'
A1='2026-01-01T00:01:00Z | START-AMEND | lane=%s classified=normal type=feature repo=r'
st() { printf "$S1" "$1"; }
am() { printf "$A1" "$1"; }
SPECF="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"; printf '# Spec: x\nStatus: DRAFT\nLane: full\n' > "$SPECF"
SPECN="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"; printf '# Spec: x\nStatus: DRAFT\n' > "$SPECN"

echo "plain start validates the lane"
for bad in fix light standard tiny2 mega; do
  ERR="$(gl start "v-$bad" "$bad" normal feature feature r 2>&1 >/dev/null)"; RC=$?
  check "start lane '$bad': exit 64" '[ "$RC" -eq 64 ]'
  check "start lane '$bad': names the valid lanes" 'printf "%s" "$ERR" | grep -q "tiny normal full bug backfill"'
  check "start lane '$bad': writes nothing" '[ ! -s "$RUNS/v-$bad.log" ]'
done
for good in tiny normal full bug backfill; do
  gl start "ok-$good" "$good" "$good" feature feature r >/dev/null 2>&1; RC=$?
  check "start lane '$good': accepted" '[ "$RC" -eq 0 ] && log "ok-$good" | grep -q "| START | lane=$good "'
done
ERR="$(gl start --amend v-am fix normal feature feature r 2>&1 >/dev/null)"; RC=$?
check "start --amend to an unknown lane: still exit 64" '[ "$RC" -eq 64 ] && printf "%s" "$ERR" | grep -q "tiny normal full bug backfill"'
check "gate-ledger.sh holds no literal copy of the lane list outside lane-data.sh" '! grep -n "tiny normal full bug backfill" "$KIT_DIR/lib/gate/gate-ledger.sh" | grep -v "^[0-9]*:[[:space:]]*#"'

echo "an overlay lane in lanes.d is declared"
LD="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")"; printf ' 1. study  required\n' > "$LD/study.plan"
gl start ov-no study study lesson lesson r >/dev/null 2>&1; RC=$?
check "start lane 'study' without a drop-in: exit 64" '[ "$RC" -eq 64 ]'
DWARVES_KIT_LANES_D="$LD" gl start ov-yes study study lesson lesson r >/dev/null 2>&1; RC=$?
check "start lane 'study' with a drop-in: accepted" '[ "$RC" -eq 0 ] && log ov-yes | grep -q "| START | lane=study "'
ERR="$(DWARVES_KIT_LANES_D="$LD" gl start --amend ov-yes study study lesson lesson r 2>&1 >/dev/null)"; RC=$?
check "start --amend to an overlay lane is still refused (exit 64)" '[ "$RC" -eq 64 ]'
check "the overlay START resolves as the effective lane" '[ "$(DWARVES_KIT_LANES_D="$LD" gl lane ov-yes | cut -f1)" = study ]'
check "without the drop-in the same START reads as absent" '! gl lane ov-yes >/dev/null 2>&1'

echo "the resolver order"
legacy r-amend  "$(st normal)" "$(am full)" "$(am tiny)"
legacy r-first  "$(st normal)" "$(st full)"
legacy r-only   "$(st bug)"
legacy r-stray  "$(st fix)"
legacy r-stray2 "$(st light)" "$(st full)"
legacy r-bad-am "$(st normal)" "$(am standard)"
legacy r-none   "2026-01-01T00:00:00Z | GATE | spec | ran | x"
rl() { gl lane "$@" 2>/dev/null; }
check "last START-AMEND wins" '[ "$(rl r-amend | cut -f1)" = tiny ] && [ "$(rl r-amend | cut -f2)" = amend ]'
check "no amend: the FIRST START wins" '[ "$(rl r-first | cut -f1)" = normal ] && [ "$(rl r-first | cut -f2)" = start ]'
check "a START beats the spec header" '[ "$(rl r-first --spec "$SPECF" | cut -f1)" = normal ]'
check "an amend beats the spec header" '[ "$(rl r-amend --spec "$SPECF" | cut -f1)" = tiny ]'
check "a stray START lane is read as absent, the header answers" '[ "$(rl r-stray --spec "$SPECF" | cut -f1)" = full ] && [ "$(rl r-stray --spec "$SPECF" | cut -f2)" = spec ]'
check "a stray first START with a later valid START still reads as absent" '[ "$(rl r-stray2 --spec "$SPECF" | cut -f1)" = full ]'
check "a stray START with no header resolves to nothing (exit 1)" 'rl r-stray >/dev/null; [ "$?" -ne 0 ]; [ -z "$(rl r-stray)" ]'
check "an unknown amend is skipped, the first START answers" '[ "$(rl r-bad-am | cut -f1)" = normal ] && [ "$(rl r-bad-am | cut -f2)" = start ]'
check "no START: the spec header answers" '[ "$(rl r-none --spec "$SPECF" | cut -f1)" = full ]'
check "no ledger at all: the spec header answers" '[ "$(rl r-missing --spec "$SPECF" | cut -f1)" = full ]'
check "the third column carries the raw spec header" '[ "$(rl r-first --spec "$SPECF" | cut -f3)" = full ]'
check "nothing anywhere: exit 1, no output" 'OUT="$(rl r-none --spec "$SPECN")"; [ -z "$OUT" ]; ! gl lane r-none --spec "$SPECN" >/dev/null 2>&1'
check "--default adds the classifier default last" '[ "$(rl r-none --default | cut -f1)" = normal ] && [ "$(rl r-none --default | cut -f2)" = default ]'
check "--default never outranks a real source" '[ "$(rl r-first --default | cut -f2)" = start ]'
check "an unknown spec header comes back raw so check() can fail closed" 'printf "# Spec\nLane: fullish\n" > "$SPECN"; [ "$(rl r-none --spec "$SPECN" | cut -f1)" = fullish ]'
printf '# Spec: x\nStatus: DRAFT\n' > "$SPECN"

echo "the check lane is the stricter of header and ledger lane"
legacy c-hf-sn  "$(st normal)"
legacy c-hn-sf  "$(st full)"
legacy c-hf-lo  "$(st full)"
gl start --amend --lower --reason "test lowering" c-hf-lo normal full feature feature r >/dev/null 2>&1
legacy c-hf-am  "$(st normal)" "$(am normal)"
legacy c-hb-sn  "$(st normal)"
legacy c-tie    "$(st bug)" "$(am normal)"
legacy c-ov     "$(st study)"
legacy c-forged "$(st full)" "2026-01-01T00:00:30Z | GATE | lane-lower | override | full -> tiny: x | via=lane-lower" "$(am normal)"
ck() { gl lane "$1" --spec "$2" | cut -f4; }
SPECN2="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"; printf '# Spec\nLane: normal\n' > "$SPECN2"
SPECB="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"; printf '# Spec\nLane: bug\n' > "$SPECB"
check "header full + plain START normal resolves full" '[ "$(ck c-hf-sn "$SPECF")" = full ]'
check "...while the ledger lane (descent, display) stays normal" '[ "$(rl c-hf-sn --spec "$SPECF" | cut -f1)" = normal ]'
check "header full + START-AMEND --lower normal resolves normal" '[ "$(ck c-hf-lo "$SPECF")" = normal ]'
check "header normal + START full resolves full" '[ "$(ck c-hn-sf "$SPECN2")" = full ]'
check "header full + a hand-written bare amend normal resolves full" '[ "$(ck c-hf-am "$SPECF")" = full ]'
check "a lane-lower line aimed at another lane does not sanction the amend" '[ "$(ck c-forged "$SPECF")" = full ]'
check "tie in rank, plain START: the header answers (bug over normal)" '[ "$(ck c-hb-sn "$SPECB")" = bug ]'
check "tie in rank, amend: the ledger lane answers" '[ "$(ck c-tie "$SPECB")" = normal ]'
check "an overlay ledger lane never lowers a kit-lane header" '[ "$(DWARVES_KIT_LANES_D="$LD" ck c-ov "$SPECF")" = full ]'
check "an overlay ledger lane with no header stays itself" '[ "$(DWARVES_KIT_LANES_D="$LD" ck c-ov "$SPECN")" = study ]'
check "no header: the check lane is the ledger lane" '[ "$(ck c-hf-sn "$SPECN")" = normal ]'
check "an empty header column prints a dash" '[ "$(gl lane c-hf-sn --spec "$SPECN" | cut -f3)" = - ]'

echo "the amend guard reads the same resolver"
legacy g-stray "$(st fix)"
gl start --amend g-stray tiny normal feature feature r >/dev/null 2>&1; RC=$?
check "amend from a stray START lane is not compared (accepted)" '[ "$RC" -eq 0 ]'
legacy g-full "$(st full)"
gl start --amend g-full normal full feature feature r >/dev/null 2>&1; RC=$?
check "amend lowering full still needs --lower (exit 65)" '[ "$RC" -eq 65 ]'

echo "ship-gate honours the resolver"
GT="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
GTERR="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
git init -q -b master "$GT"; git -C "$GT" config user.email t@t; git -C "$GT" config user.name t
mkdir -p "$GT/docs/specs" "$GT/docs/verification" "$GT/docs/implementation-notes"; echo marker > "$GT/docs/verification/README.md"
git -C "$GT" add -A; git -C "$GT" commit -qm init
export KIT_CONFIG_OPERATOR="$KIT_DIR/tests/fixtures/gates-on"
gate() { ( cd "$GT" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
    | CLAUDE_PLUGIN_ROOT="$KIT_DIR" DWARVES_KIT_LOG_DIR="$DWARVES_KIT_LOG_DIR" bash "$KIT_DIR/hooks/ship-gate.sh" 2>"$GTERR" >/dev/null; echo $? ); }
sg_case() { # slug, header lane, ledger lines (START lanes) -> prints gate exit; gates recorded for $4
  local slug="$1" hdr="$2" start="$3" gates="$4"
  git -C "$GT" switch -qc "feat/$slug"
  printf '# Spec: x\nStatus: DRAFT\n%s\n' "${hdr:+Lane: $hdr}" > "$GT/docs/specs/SPEC-001-$slug.md"
  printf '# Notes\nNo deviations; matches the spec verbatim\n' > "$GT/docs/implementation-notes/$slug.md"
  git -C "$GT" add -A; git -C "$GT" commit -qm spec
  [ -z "$start" ] || legacy "$slug" "$(st "$start")"
  local g
  while read -r g; do gl record "$slug" "$g" ran test >/dev/null 2>&1; done < <(gl required "$gates")
  gl record "$slug" validate ran test >/dev/null 2>&1
  gate
}
sg_lower_case() { # header full, START full, then a sanctioned --lower amend to normal, normal gates
  local slug="$1" g
  git -C "$GT" switch -qc "feat/$slug"
  printf '# Spec: x\nStatus: DRAFT\nLane: full\n' > "$GT/docs/specs/SPEC-001-$slug.md"
  printf '# Notes\nNo deviations; matches the spec verbatim\n' > "$GT/docs/implementation-notes/$slug.md"
  git -C "$GT" add -A; git -C "$GT" commit -qm spec
  gl start "$slug" full full feature feature r >/dev/null 2>&1
  gl start --amend --lower --reason "test lowering" "$slug" normal full feature feature r >/dev/null 2>&1
  while read -r g; do gl record "$slug" "$g" ran test >/dev/null 2>&1; done < <(gl required normal)
  gl record "$slug" validate ran test >/dev/null 2>&1
  gate
}
check "header full, first START normal, normal gates -> blocked (the stricter header wins)" '[ "$(sg_case sga full normal normal)" = 2 ]'
check "the lighter ledger lane is announced" 'grep -q "lighter than the spec" "$GTERR"'
check "header full, first START normal, full gates -> pass" '[ "$(sg_case sgf full normal full)" = 0 ]'
check "header full, START full + amend --lower normal, normal gates -> pass (a reasoned lowering)" '[ "$(sg_lower_case sgl)" = 0 ]'
check "header normal, first START full, normal gates -> blocked (START raises)" '[ "$(sg_case sgb normal full normal)" = 2 ]'
check "header full, stray START fix, full gates -> pass (stray START is absent)" '[ "$(sg_case sgc full fix full)" = 0 ]'
check "header full, stray START fix, normal gates -> blocked (the header answers)" '[ "$(sg_case sgd full fix normal)" = 2 ]'
check "no header, no START -> blocked (the no-lane rule stays closed)" '[ "$(sg_case sge "" "" normal)" = 2 ]'

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

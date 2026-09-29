#!/usr/bin/env bash
# test-gate-validate-round.sh -- `validate-round` verb on gate-ledger.sh.
# The parallel validation round's bookkeeping as a state machine: open binds the rid
# to the spec the ship-gate will read and pins blob+head+porcelain; close writes the
# round's GATE/OUTCOME records in a fixed order; `| ROUND |` lines are additive.
#
# Isolation: every case runs under a fresh DWARVES_KIT_LOG_DIR in its own mktemp dir,
# and each git repo is a fresh mktemp repo on feat/vr-<case>.
#
# Run: bash tests/test-gate-validate-round.sh        (all cases)
#      VR_CASES="C1 C3" bash tests/test-gate-validate-round.sh   (subset)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

LOGD=""
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" "$@"; }
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }
ledger() { printf '%s/runs/%s.log' "$LOGD" "$1"; }

# Case filter: `want C3 && { ...; }`
want() { [ -z "${VR_CASES:-}" ] && return 0; case " $VR_CASES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# fresh repo on feat/vr-<suffix> with a committed docs/specs/SPEC-001-vr-<suffix>.md;
# prints the repo path.
mkrepo() {
  local d; d="$(_mk)/repo-$1"
  mkdir -p "$d/docs/specs"
  git init -q -b "feat/vr-$1" "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false
  printf '# SPEC-001 vr-%s\n\nStatus: DRAFT\n' "$1" > "$d/docs/specs/SPEC-001-vr-$1.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
  (cd "$d" && pwd -P)   # canonical: `open` pins pwd -P paths, so compare like for like
}

# fields-2-onward view of a ledger (timestamps + timing fields masked)
block() { sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z \| //' "$(ledger "$1")" | sed -E 's/at=[0-9]+/at=E/g; s/dur_s=[0-9]+/dur_s=D/g'; }
tailn() { block "$1" | tail -"$2"; }

# $1=want rc, $2=desc, $3=rid whose ledger must be unchanged, rest=command
refuse() {
  local want="$1" desc="$2" rid="$3"; shift 3
  local f before rc
  f="$(ledger "$rid")"
  if [ -f "$f" ]; then before="$(cat "$f")"; else before="__NOFILE__"; fi
  "$@" >/dev/null 2>&1; rc=$?
  local ok=0
  [ "$rc" -eq "$want" ] || ok=1
  if [ "$ok" = 0 ]; then
    if [ "$before" = "__NOFILE__" ]; then
      [ ! -e "$f" ] || ok=1
    else
      [ "$(cat "$f" 2>/dev/null)" = "$before" ] || ok=1
    fi
  fi
  assert "$desc (want rc=$want got $rc)" "$ok"
}

echo "=== gate validate-round ==="

# ---------------------------------------------------------------------------
# C1: `open` pins the spec blob and writes the two starts + ROUND open (sha1 +
# sha256 object formats).
# ---------------------------------------------------------------------------
if want C1; then
  echo "-- C1 open"
  new_log; R="$(mkrepo c1)"
  SP="$R/docs/specs/SPEC-001-vr-c1.md"
  printf 'extra line\n' >> "$SP"           # dirty the committed spec: its blob exists nowhere yet
  T="$(gl validate-round open vr-c1 "$SP")"; RC=$?
  assert "C1 open exits 0" "$([ "$RC" -eq 0 ]; echo $?)"
  assert "C1 token is <40hex>.<epoch>.<n>" "$({ trap '' PIPE; echo "$T" | grep -qE '^[0-9a-f]{40}\.[0-9]+\.[0-9]+$'; } && echo 0 || echo 1)"
  BLOB="${T%%.*}"
  git -C "$R" cat-file -e "$BLOB" 2>/dev/null; assert "C1 pinned blob exists in the spec's object store" "$?"
  TOP="$(git -C "$R" rev-parse --show-toplevel)"
  HEAD="$(git -C "$R" rev-parse HEAD)"
  EXP="OUTCOME | validate | start | at=E
OUTCOME | design-record | start | at=E
ROUND | open | token=$T top=$TOP spec=$SP blob=$BLOB head=$HEAD"
  GOT="$(tailn vr-c1 3 | sed -E 's/ porcelain=[0-9a-f]+$//')"
  assert "C1 ledger tail: two OUTCOME starts then ROUND open with pins" "$([ "$GOT" = "$EXP" ]; echo $?)"
  POR="$(tail -1 "$(ledger vr-c1)" | sed -nE 's/.* porcelain=([0-9a-f]+).*/\1/p')"
  assert "C1 porcelain pin is a sha" "$({ trap '' PIPE; echo "$POR" | grep -qE '^[0-9a-f]{40,64}$'; } && echo 0 || echo 1)"

  # sha256 leg: object store + token both 64-hex
  new_log; R2="$(_mk)/repo-c1s"; mkdir -p "$R2/docs/specs"
  git init -q --object-format=sha256 -b feat/vr-c1s "$R2"
  git -C "$R2" config user.email t@t; git -C "$R2" config user.name t; git -C "$R2" config commit.gpgsign false
  SP2="$R2/docs/specs/SPEC-001-vr-c1s.md"
  printf '# SPEC-001 vr-c1s\n' > "$SP2"
  git -C "$R2" add -A; git -C "$R2" commit -qm init
  T2="$(gl validate-round open vr-c1s "$SP2")"; RC=$?
  assert "C1 sha256 open exits 0" "$([ "$RC" -eq 0 ]; echo $?)"
  assert "C1 sha256 token is <64hex>.<epoch>.<n>" "$({ trap '' PIPE; echo "$T2" | grep -qE '^[0-9a-f]{64}\.[0-9]+\.[0-9]+$'; } && echo 0 || echo 1)"
  git -C "$R2" cat-file -e "${T2%%.*}" 2>/dev/null; assert "C1 sha256 pinned blob exists" "$?"
fi

# ---------------------------------------------------------------------------
# C1b: open from anywhere -- cwd elsewhere, a foreign repo cwd, a repo subdir,
# and an exported GIT_DIR / GIT_COMMON_DIR all pin the same canonical spec=.
# Each leg gets its own log dir (one open per rid per ledger).
# ---------------------------------------------------------------------------
if want C1b; then
  echo "-- C1b open-from-anywhere"
  R="$(mkrepo c1b)"; OTHER="$(mkrepo c1b-other)"
  SP="$R/docs/specs/SPEC-001-vr-c1b.md"
  SUB="$R/src"; mkdir -p "$SUB"
  WANT_SP="$(cd "$R/docs/specs" && pwd -P)/SPEC-001-vr-c1b.md"
  SPECS=""
  i=0
  for leg in plain outside subdir gitdir gitcommon; do
    i=$((i+1)); new_log
    case "$leg" in
      plain)     T="$(cd "$R" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      outside)   T="$(cd "$(_mk)" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      subdir)    T="$(cd "$SUB" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b ../docs/specs/SPEC-001-vr-c1b.md)" ;;
      gitdir)    T="$(cd "$R" && env GIT_DIR="$OTHER/.git" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      gitcommon) T="$(cd "$R" && env GIT_COMMON_DIR="$OTHER/.git" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
    esac
    RC=$?
    assert "C1b $leg: open exits 0" "$([ "$RC" -eq 0 ]; echo $?)"
    GOT="$(tail -1 "$(ledger vr-c1b)" | sed -nE 's/.* spec=([^ ]+).*/\1/p')"
    assert "C1b $leg: spec= is the canonical path" "$([ "$GOT" = "$WANT_SP" ]; echo $?)"
    SPECS="$SPECS $GOT"
    # the blob went to the SPEC repo's object store, never the foreign one
    if [ "$leg" = gitdir ] || [ "$leg" = gitcommon ]; then
      if git -C "$OTHER" cat-file -e "${T%%.*}" 2>/dev/null; then B_RC=1; else B_RC=0; fi
      assert "C1b $leg: pinned blob absent from the foreign repo" "$B_RC"
    fi
  done
fi

# ---------------------------------------------------------------------------
# C1c: two opens in one second (a void line between them) still differ in .n.
# ---------------------------------------------------------------------------
if want C1c; then
  echo "-- C1c token uniqueness"
  new_log; R="$(mkrepo c1c)"; SP="$R/docs/specs/SPEC-001-vr-c1c.md"
  T1="$(gl validate-round open vr-c1c "$SP")"
  printf '%s | ROUND | void | token=%s why=ledger\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T1" >> "$(ledger vr-c1c)"
  T2="$(gl validate-round open vr-c1c "$SP")"
  N1="${T1##*.}"; N2="${T2##*.}"
  assert "C1c second open succeeds after a void" "$?"
  assert "C1c tokens differ in .n (1 then 2)" "$([ "$N1" = 1 ] && [ "$N2" = 2 ]; echo $?)"
  assert "C1c both share the pinned spec blob" "$([ "${T1%%.*}" = "${T2%%.*}" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C2: close verdict=APPROVED writes the fixed block and prints blob=<pin>.
# ---------------------------------------------------------------------------
if want C2; then
  echo "-- C2 close APPROVED"
  new_log; R="$(mkrepo c2)"; SP="$R/docs/specs/SPEC-001-vr-c2.md"
  T="$(gl validate-round open vr-c2 "$SP")"
  OUT="$(gl validate-round close vr-c2 "$T" verdict=APPROVED critical=0 warnings=3 agents=7 r6="design-bearing=yes pass")"; RC=$?
  assert "C2 close exits 0" "$([ "$RC" -eq 0 ]; echo $?)"
  assert "C2 close prints blob=<pin>" "$([ "$OUT" = "blob=${T%%.*}" ]; echo $?)"
  EXP="ROUND | closing | token=$T kind=close verdict=APPROVED critical=0 warnings=3 agents=7 | design-bearing=yes pass | 0 critical
GATE | validate | ran | APPROVED critical=0 warnings=3 fresh agents=7 parallel
OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | ran | design-bearing=yes pass
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | close | token=$T verdict=APPROVED"
  GOT="$(tailn vr-c2 6)"
  assert "C2 close block in fixed order" "$([ "$GOT" = "$EXP" ]; echo $?)"
  OR="$(gl outcome-read vr-c2 validate 2>/dev/null)"
  assert "C2 outcome-read sees validate caught=false" "$({ trap '' PIPE; echo "$OR" | grep -q 'validate caught=false'; } && echo 0 || echo 1)"
fi

# ---------------------------------------------------------------------------
# C3: NEEDS-REVISION with R6 pass: validate skipped + caught=true, design-record
# ran + caught=false. Summary default `<critical> critical`.
# ---------------------------------------------------------------------------
if want C3; then
  echo "-- C3 close NEEDS-REVISION r6 pass"
  new_log; R="$(mkrepo c3)"; SP="$R/docs/specs/SPEC-001-vr-c3.md"
  T="$(gl validate-round open vr-c3 "$SP")"
  gl validate-round close vr-c3 "$T" verdict=NEEDS-REVISION critical=2 warnings=1 agents=7 r6="design-bearing=no pass" summary="stale fixture" >/dev/null 2>&1
  EXP="ROUND | closing | token=$T kind=close verdict=NEEDS-REVISION critical=2 warnings=1 agents=7 | design-bearing=no pass | stale fixture
GATE | validate | skipped | NEEDS REVISION: stale fixture
OUTCOME | validate | end | at=E caught=true dur_s=D
GATE | design-record | ran | design-bearing=no pass
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | close | token=$T verdict=NEEDS-REVISION"
  GOT="$(tailn vr-c3 6)"
  assert "C3 NR+r6pass block in fixed order" "$([ "$GOT" = "$EXP" ]; echo $?)"

  new_log
  T="$(gl validate-round open vr-c3 "$SP")"
  gl validate-round close vr-c3 "$T" verdict=NEEDS-REVISION critical=2 warnings=0 agents=4 r6="design-bearing=yes pass" >/dev/null 2>&1
  G="$(tailn vr-c3 6 | sed -n '2p')"
  assert "C3 missing summary defaults to '<critical> critical'" "$([ "$G" = 'GATE | validate | skipped | NEEDS REVISION: 2 critical' ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C4: NEEDS-REVISION with R6 critical: design-record is skipped with the finding
# and caught=true.
# ---------------------------------------------------------------------------
if want C4; then
  echo "-- C4 close NEEDS-REVISION r6 critical"
  new_log; R="$(mkrepo c4)"; SP="$R/docs/specs/SPEC-001-vr-c4.md"
  T="$(gl validate-round open vr-c4 "$SP")"
  gl validate-round close vr-c4 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=5 r6="design-bearing=yes critical: empty Design section" summary="1 critical" >/dev/null 2>&1
  EXP="ROUND | closing | token=$T kind=close verdict=NEEDS-REVISION critical=1 warnings=0 agents=5 | design-bearing=yes critical: empty Design section | 1 critical
GATE | validate | skipped | NEEDS REVISION: 1 critical
OUTCOME | validate | end | at=E caught=true dur_s=D
GATE | design-record | skipped | critical: empty Design section
OUTCOME | design-record | end | at=E caught=true dur_s=D
ROUND | close | token=$T verdict=NEEDS-REVISION"
  GOT="$(tailn vr-c4 6)"
  assert "C4 NR+r6critical block in fixed order" "$([ "$GOT" = "$EXP" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C11a: open + close-key refusals. Every leg asserts an exact exit (1/64/never
# 128) and an unchanged ledger.
# ---------------------------------------------------------------------------
if want C11a; then
  echo "-- C11a open/key refusals"
  new_log; R="$(mkrepo c11)"; SP="$R/docs/specs/SPEC-001-vr-c11.md"

  # rid not the branch's slug-derived rid
  refuse 1 "C11a open with a non-binding rid" vr-c11 gl validate-round open wrong-rid "$SP"
  # spec path problems (all 64, before any git call)
  refuse 64 "C11a open: missing spec file" vr-c11 gl validate-round open vr-c11 "$R/docs/specs/SPEC-999-vr-c11.md"
  L="$(_mk)/spec-link.md"; ln -s "$SP" "$L"
  refuse 64 "C11a open: spec is a symlink" vr-c11 gl validate-round open vr-c11 "$L"
  refuse 64 "C11a open: spec path holds whitespace" vr-c11 gl validate-round open vr-c11 "$R/docs/specs/a b.md"
  refuse 64 "C11a open: spec path holds '='" vr-c11 gl validate-round open vr-c11 "$R/docs/specs/a=b.md"
  refuse 64 "C11a open: spec directory missing" vr-c11 gl validate-round open vr-c11 "$R/docs/nope/SPEC-001-vr-c11.md"
  # a real file that is not the ship-gate pick
  printf '# other\n' > "$R/docs/specs/SPEC-001-other.md"; git -C "$R" add -A; git -C "$R" commit -qm other
  refuse 1 "C11a open: committed spec with the wrong name" vr-c11 gl validate-round open vr-c11 "$R/docs/specs/SPEC-001-other.md"
  printf '# readme\n' > "$R/README.md"; git -C "$R" add README.md >/dev/null; git -C "$R" commit -qm readme
  refuse 1 "C11a open: real file outside docs/specs" vr-c11 gl validate-round open vr-c11 "$R/README.md"
  # a foreign repo whose branch slug does not derive the rid
  RF="$(_mk)/repo-foreign"; mkdir -p "$RF/docs/specs"
  git init -q -b feat/other "$RF"; git -C "$RF" config user.email t@t; git -C "$RF" config user.name t
  printf '# foreign copy\n' > "$RF/docs/specs/SPEC-001-vr-c11.md"; git -C "$RF" add -A; git -C "$RF" commit -qm init
  refuse 1 "C11a open: foreign repo spec" vr-c11 gl validate-round open vr-c11 "$RF/docs/specs/SPEC-001-vr-c11.md"
  # a second spec sorting before the pick (glob head -1 takes SPEC-000)
  R13="$(_mk)/repo-c11two"; mkdir -p "$R13/docs/specs"
  git init -q -b feat/vr-c11two "$R13"; git -C "$R13" config user.email t@t; git -C "$R13" config user.name t
  printf '# a\n' > "$R13/docs/specs/SPEC-001-vr-c11two.md"; printf '# b\n' > "$R13/docs/specs/SPEC-000-vr-c11two.md"
  git -C "$R13" add -A; git -C "$R13" commit -qm init
  refuse 1 "C11a open: earlier-sorting spec is the ship-gate pick" vr-c11two gl validate-round open vr-c11two "$R13/docs/specs/SPEC-001-vr-c11two.md"
  # branch refusals
  RM="$(_mk)/repo-main"; mkdir -p "$RM/docs/specs"
  git init -q -b main "$RM"; git -C "$RM" config user.email t@t; git -C "$RM" config user.name t
  printf '# m\n' > "$RM/docs/specs/SPEC-001-main.md"; git -C "$RM" add -A; git -C "$RM" commit -qm init
  refuse 1 "C11a open: branch main refused" main gl validate-round open main "$RM/docs/specs/SPEC-001-main.md"
  RB="$(_mk)/repo-badslug"; mkdir -p "$RB/docs/specs"
  git init -q -b 'feat/Vr+C11' "$RB"; git -C "$RB" config user.email t@t; git -C "$RB" config user.name t
  printf '# b\n' > "$RB/docs/specs/SPEC-001-x.md"; git -C "$RB" add -A; git -C "$RB" commit -qm init
  refuse 1 "C11a open: raw slug survives normalization" vrc11 gl validate-round open vrc11 "$RB/docs/specs/SPEC-001-x.md"
  RN="$(_mk)/repo-nospec"; mkdir -p "$RN/docs/specs"
  git init -q -b feat/no-such-spec "$RN"; git -C "$RN" config user.email t@t; git -C "$RN" config user.name t
  printf '# n\n' > "$RN/docs/specs/SPEC-001-other.md"; git -C "$RN" add -A; git -C "$RN" commit -qm init
  refuse 1 "C11a open: no spec matches the slug glob" no-such-spec gl validate-round open no-such-spec "$RN/docs/specs/SPEC-001-other.md"
  # a git failure mid-open (PATH shim fails every git call) exits 1, never 128
  SHIM="$(_mk)/shim"; mkdir -p "$SHIM"; printf '#!/bin/sh\nexit 1\n' > "$SHIM/git"; chmod +x "$SHIM/git"
  refuse 1 "C11a open: git failure maps to exit 1" vr-c11 env PATH="$SHIM:/usr/bin:/bin" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c11 "$SP"

  # open over open / over a hand-written closing
  T="$(gl validate-round open vr-c11 "$SP")"
  refuse 1 "C11a open over an open round" vr-c11 gl validate-round open vr-c11 "$SP"
  new_log
  printf '%s | ROUND | closing | token=%s kind=close verdict=APPROVED critical=0 warnings=0 agents=1 | design-bearing=yes pass | 0 critical\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T" >> "$(ledger vr-c11)"
  refuse 1 "C11a open over a closing round" vr-c11 gl validate-round open vr-c11 "$SP"

  # a GATE reason holding `| ROUND | open | token=<t>` never registers as a round
  new_log
  gl record vr-c11 grill ran "pre-round | ROUND | open | token=deadbeef.1.1" >/dev/null 2>&1
  T="$(gl validate-round open vr-c11 "$SP")"
  gl validate-round close vr-c11 "$T" verdict=APPROVED critical=0 warnings=0 agents=1 r6="design-bearing=yes pass" >/dev/null 2>&1
  assert "C11a forged ROUND text inside a GATE reason never registers" "$?"

  # ship-gate agreement: spec= equals the slug glob's first hit
  new_log
  gl validate-round open vr-c11 "$SP" >/dev/null 2>&1
  TOP="$(git -C "$R" rev-parse --show-toplevel)"
  PICK="$(ls "$TOP"/docs/specs/SPEC-*-vr-c11.md 2>/dev/null | head -1)"
  GOT="$(tail -1 "$(ledger vr-c11)" | sed -nE 's/.* spec=([^ ]+).*/\1/p')"
  assert "C11a spec= equals the ship-gate glob pick" "$([ "$GOT" = "$PICK" ]; echo $?)"

  # ---- close refusals -------------------------------------------------------
  new_log
  T="$(gl validate-round open vr-c11 "$SP")"
  KEYS="verdict=APPROVED critical=0 warnings=0 agents=1"
  # token grammar (bash [[ =~ ]]): no epoch, no nonce, uppercase, 41 hex, newline
  refuse 64 "C11a close: token without epoch" vr-c11 gl validate-round close vr-c11 deadbeef verdict=APPROVED
  refuse 64 "C11a close: token without nonce" vr-c11 gl validate-round close vr-c11 "$(printf '%040d.123' 0)" $KEYS 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: uppercase blob" vr-c11 gl validate-round close vr-c11 "$(printf '%040d.1.1' 0 | tr '0' 'A')" $KEYS 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: 41-hex blob" vr-c11 gl validate-round close vr-c11 "a$(printf '%040d' 0).1.1" $KEYS 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: token then newline+x" vr-c11 gl validate-round close vr-c11 "$T
x" $KEYS 'r6=design-bearing=yes pass'
  # a grammar-fine token that is not the round's
  refuse 1 "C11a close: stale token" vr-c11 gl validate-round close vr-c11 "${T%.*}.99" $KEYS 'r6=design-bearing=yes pass'
  # key problems (all 64)
  refuse 64 "C11a close: warnings=x" vr-c11 gl validate-round close vr-c11 "$T" verdict=APPROVED critical=0 warnings=x agents=1 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: agents=0" vr-c11 gl validate-round close vr-c11 "$T" verdict=APPROVED critical=0 warnings=0 agents=0 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: missing agents" vr-c11 gl validate-round close vr-c11 "$T" verdict=APPROVED critical=0 warnings=0 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: unknown key" vr-c11 gl validate-round close vr-c11 "$T" $KEYS 'r6=design-bearing=yes pass' bogus=1
  refuse 64 "C11a close: repeated key" vr-c11 gl validate-round close vr-c11 "$T" verdict=APPROVED verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: bare arg not k=v" vr-c11 gl validate-round close vr-c11 "$T" $KEYS 'r6=design-bearing=yes pass' stray
  # consistency (all 64)
  refuse 64 "C11a close: APPROVED with critical=2" vr-c11 gl validate-round close vr-c11 "$T" verdict=APPROVED critical=2 warnings=0 agents=1 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: APPROVED with r6 critical" vr-c11 gl validate-round close vr-c11 "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes critical: x'
  refuse 64 "C11a close: NEEDS-REVISION with critical=0" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass'
  refuse 64 "C11a close: r6 critical with critical=0" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=0 warnings=0 agents=1 'r6=design-bearing=yes critical: x'
  # r6 grammar + raw-charset checks (all 64)
  refuse 64 "C11a close: r6 'yes ok'" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=yes ok'
  refuse 64 "C11a close: r6 with bare pipe" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes pass | x'
  refuse 64 "C11a close: r6 with newline" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 "r6=design-bearing=yes pass
x"
  refuse 64 "C11a close: r6 with CR" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 "r6=design-bearing=yes pass$(printf '\r')x"
  refuse 64 "C11a close: summary with pipe" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes pass' 'summary=x | ran | y'
  refuse 64 "C11a close: summary newline+pipe" vr-c11 gl validate-round close vr-c11 "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes pass' "summary=a
| ran |
b"
  # unknown subverb
  refuse 64 "C11a unknown subverb" vr-c11 gl validate-round frobnicate vr-c11
  # close with no open round at all
  new_log
  refuse 1 "C11a close: no open round" vr-c11 gl validate-round close vr-c11 "$T" $KEYS 'r6=design-bearing=yes pass'
fi

echo ""
echo "=== results: $PASS/$TOTAL pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ]

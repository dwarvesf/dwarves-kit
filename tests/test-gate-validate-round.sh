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
# Hermetic git: no inherited repo env (GIT_DIR/GIT_COMMON_DIR/...), no user
# config, no real HOME -- the suite must behave identically on any host.
unset $(git rev-parse --local-env-vars)
VR_HOME="$(mktemp -d)"; HOME="$VR_HOME"; export HOME
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

TMPS=("$VR_HOME")
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

# A git shim that exits 128 for exactly one subcommand ($1) and passes every
# other call through to the real git. Prints the shim dir.
gitshim() {
  local d real
  d="$(_mk)/shim"; mkdir -p "$d"
  real="$(command -v git)"
  printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "%s" ] && exit 128; done\nexec "%s" "$@"\n' "$1" "$real" > "$d/git"
  chmod +x "$d/git"
  printf '%s' "$d"
}

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
  # dirty the spec: its blob exists only because `open` wrote it with -w, so
  # `cat-file -e` in the SPEC repo proves where the pin landed
  printf 'dirty at open\n' >> "$SP"
  SPECS=""
  i=0
  for leg in plain outside otherrepo subdir gitdir gitcommon; do
    i=$((i+1)); new_log
    case "$leg" in
      plain)     T="$(cd "$R" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      outside)   T="$(cd "$(_mk)" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      otherrepo) T="$(cd "$OTHER" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      subdir)    T="$(cd "$SUB" && env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b ../docs/specs/SPEC-001-vr-c1b.md)" ;;
      gitdir)    T="$(cd "$R" && env GIT_DIR="$OTHER/.git" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
      gitcommon) T="$(cd "$R" && env GIT_COMMON_DIR="$OTHER/.git" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c1b "$SP")" ;;
    esac
    RC=$?
    assert "C1b $leg: open exits 0" "$([ "$RC" -eq 0 ]; echo $?)"
    GOT="$(tail -1 "$(ledger vr-c1b)" | sed -nE 's/.* spec=([^ ]+).*/\1/p')"
    assert "C1b $leg: spec= is the canonical path" "$([ "$GOT" = "$WANT_SP" ]; echo $?)"
    SPECS="$SPECS $GOT"
    # the pinned blob is readable out of the SPEC repo's object store
    git -C "$R" cat-file -e "${T%%.*}" 2>/dev/null; assert "C1b $leg: pinned blob in the spec repo" "$?"
    # and never in the foreign repo's store
    if [ "$leg" = otherrepo ] || [ "$leg" = gitdir ] || [ "$leg" = gitcommon ]; then
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
  T2="$(gl validate-round open vr-c1c "$SP")"; RC=$?
  N1="${T1##*.}"; N2="${T2##*.}"
  assert "C1c second open succeeds after a void" "$([ "$RC" -eq 0 ]; echo $?)"
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
  # the files exist, so only the charset rule can produce the 64
  printf '# w\n' > "$R/docs/specs/a b.md"; printf '# e\n' > "$R/docs/specs/a=b.md"
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
  # rid IS runid(slug) and the spec is named for the raw slug, so the only check
  # that can refuse is the raw-slug-vs-runid one
  RB="$(_mk)/repo-badslug"; mkdir -p "$RB/docs/specs"
  git init -q -b 'feat/Vr+C11' "$RB"; git -C "$RB" config user.email t@t; git -C "$RB" config user.name t
  printf '# b\n' > "$RB/docs/specs/SPEC-001-Vr+C11.md"; git -C "$RB" add -A; git -C "$RB" commit -qm init
  refuse 1 "C11a open: raw slug survives normalization" VrC11 gl validate-round open VrC11 "$RB/docs/specs/SPEC-001-Vr+C11.md"
  RN="$(_mk)/repo-nospec"; mkdir -p "$RN/docs/specs"
  git init -q -b feat/no-such-spec "$RN"; git -C "$RN" config user.email t@t; git -C "$RN" config user.name t
  printf '# n\n' > "$RN/docs/specs/SPEC-001-other.md"; git -C "$RN" add -A; git -C "$RN" commit -qm init
  refuse 1 "C11a open: no spec matches the slug glob" no-such-spec gl validate-round open no-such-spec "$RN/docs/specs/SPEC-001-other.md"
  # a git failure mid-open exits 1, never 128 -- one leg per git call the verb
  # makes (the shim fails exactly that subcommand and execs real git otherwise)
  for sub in hash-object rev-parse status; do
    SHIM="$(gitshim "$sub")"
    refuse 1 "C11a open: git $sub failure maps to exit 1" vr-c11 env PATH="$SHIM:/usr/bin:/bin" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round open vr-c11 "$SP"
  done

  # open over open / over a hand-written closing
  T="$(gl validate-round open vr-c11 "$SP")"
  refuse 1 "C11a open over an open round" vr-c11 gl validate-round open vr-c11 "$SP"
  new_log
  printf '%s | ROUND | closing | token=%s kind=close verdict=APPROVED critical=0 warnings=0 agents=1 | design-bearing=yes pass | 0 critical\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T" >> "$(ledger vr-c11)"
  refuse 1 "C11a open over a closing round" vr-c11 gl validate-round open vr-c11 "$SP"

  # a GATE reason holding `| ROUND | open | token=<t>` never registers as a
  # round, and closing with that forged token text refuses without a write
  new_log
  FT="$(printf 'deadbeef%.0s' 1 1 1 1 1).1.1"   # grammar-valid 40-hex token text, never opened
  gl record vr-c11 grill ran "pre-round | ROUND | open | token=$FT" >/dev/null 2>&1
  T="$(gl validate-round open vr-c11 "$SP")"
  refuse 1 "C11a close with the forged token text refuses" vr-c11 gl validate-round close vr-c11 "$FT" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass'
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

# ---------------------------------------------------------------------------
# C5: blob drift -- spec dirty at open, edited again before close -> void, why
# holds blob only (the dirty-at-open control keeps porcelain still).
# ---------------------------------------------------------------------------
if want C5; then
  echo "-- C5 blob drift"
  new_log; R="$(mkrepo c5)"; SP="$R/docs/specs/SPEC-001-vr-c5.md"
  printf 'dirty at open\n' >> "$SP"
  T="$(gl validate-round open vr-c5 "$SP")"
  git -C "$R" cat-file -e "${T%%.*}" 2>/dev/null; assert "C5 pinned blob exists right after open" "$?"
  printf 'edited again\n' >> "$SP"
  gl validate-round close vr-c5 "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C5 close exits 2 (void)" "$([ "$RC" = 2 ]; echo $?)"
  LAST="$(tailn vr-c5 1)"
  assert "C5 last line is ROUND void" "$({ trap '' PIPE; echo "$LAST" | grep -q '^ROUND | void | '; } && echo 0 || echo 1)"
  assert "C5 why=blob only (porcelain unchanged by the second edit)" "$({ trap '' PIPE; echo "$LAST" | grep -q 'why=blob$'; } && echo 0 || echo 1)"
  git -C "$R" cat-file -e "${T%%.*}" 2>/dev/null; assert "C5 pinned blob still in the object store" "$?"
  GN=$(grep -c ' | GATE | validate | ' "$(ledger vr-c5)" || true)
  assert "C5 a void writes no GATE validate line" "$([ "$GN" = 0 ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C5b: HEAD drift -- an empty commit mid-round.
# ---------------------------------------------------------------------------
if want C5b; then
  echo "-- C5b head drift"
  new_log; R="$(mkrepo c5b)"; SP="$R/docs/specs/SPEC-001-vr-c5b.md"
  T="$(gl validate-round open vr-c5b "$SP")"
  git -C "$R" commit -q --allow-empty -m mid-round
  gl validate-round close vr-c5b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C5b close exits 2" "$([ "$RC" = 2 ]; echo $?)"
  assert "C5b why holds head" "$({ trap '' PIPE; tail -1 "$(ledger vr-c5b)" | grep -q 'why=.*head'; } && echo 0 || echo 1)"
fi

# ---------------------------------------------------------------------------
# C5c: spec removed or replaced by a symlink mid-round -> void exit 2 (blob),
# never 1 and no git error text on stderr.
# ---------------------------------------------------------------------------
if want C5c; then
  echo "-- C5c spec removed/symlinked"
  for mode in rm symlink; do
    new_log; R="$(mkrepo c5c-$mode)"; SP="$R/docs/specs/SPEC-001-vr-c5c-$mode.md"
    T="$(gl validate-round open "vr-c5c-$mode" "$SP")"
    if [ "$mode" = rm ]; then rm "$SP"; else cp "$SP" "$SP.copy" && rm "$SP" && ln -s "$SP.copy" "$SP"; fi
    ERRS="$(gl validate-round close "vr-c5c-$mode" "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' 2>&1 >/dev/null)"; RC=$?
    assert "C5c $mode: close exits 2" "$([ "$RC" = 2 ]; echo $?)"
    assert "C5c $mode: why holds blob" "$({ trap '' PIPE; tail -1 "$(ledger "vr-c5c-$mode")" | grep -q 'why=.*blob'; } && echo 0 || echo 1)"
    assert "C5c $mode: no git error text on stderr" "$({ trap '' PIPE; echo "$ERRS" | grep -qE 'fatal|error:'; } && echo 1 || echo 0)"
  done
fi

# ---------------------------------------------------------------------------
# C6: ledger drift -- a foreign line after ROUND open voids; the forged line is
# listed on stderr.
# ---------------------------------------------------------------------------
if want C6; then
  echo "-- C6 ledger drift"
  new_log; R="$(mkrepo c6)"; SP="$R/docs/specs/SPEC-001-vr-c6.md"
  T="$(gl validate-round open vr-c6 "$SP")"
  gl action vr-c6 "foreign write" >/dev/null 2>&1
  ERRS="$(gl validate-round close vr-c6 "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' 2>&1 >/dev/null)"; RC=$?
  assert "C6 close exits 2" "$([ "$RC" = 2 ]; echo $?)"
  assert "C6 why holds ledger" "$({ trap '' PIPE; tail -1 "$(ledger vr-c6)" | grep -q 'why=.*ledger'; } && echo 0 || echo 1)"
  assert "C6 foreign ACTION line listed on stderr" "$({ trap '' PIPE; echo "$ERRS" | grep -q 'ACTION | foreign write'; } && echo 0 || echo 1)"
  # forged GATE validate ran between open and close
  new_log
  T="$(gl validate-round open vr-c6 "$SP")"
  gl record vr-c6 Validate ran "forged" >/dev/null 2>&1
  ERRS="$(gl validate-round close vr-c6 "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' 2>&1 >/dev/null)"; RC=$?
  assert "C6 forged-GATE close exits 2" "$([ "$RC" = 2 ]; echo $?)"
  assert "C6 forged GATE line listed on stderr" "$({ trap '' PIPE; echo "$ERRS" | grep -q 'GATE | validate | ran | forged'; } && echo 0 || echo 1)"
fi

# ---------------------------------------------------------------------------
# C7: porcelain drift + the exclusion set.
# ---------------------------------------------------------------------------
if want C7; then
  echo "-- C7 porcelain drift"
  new_log; R="$(mkrepo c7)"; SP="$R/docs/specs/SPEC-001-vr-c7.md"
  T="$(gl validate-round open vr-c7 "$SP")"
  mkdir -p "$R/src/sub"; printf 'x\n' > "$R/src/sub/new.txt"
  gl validate-round close vr-c7 "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C7 nested untracked file drifts porcelain -> exit 2" "$([ "$RC" = 2 ]; echo $?)"
  assert "C7 why holds porcelain" "$({ trap '' PIPE; tail -1 "$(ledger vr-c7)" | grep -q 'why=.*porcelain'; } && echo 0 || echo 1)"
fi
if want C7b; then
  echo "-- C7b clean-at-open spec edit drifts blob and porcelain"
  new_log; R="$(mkrepo c7b)"; SP="$R/docs/specs/SPEC-001-vr-c7b.md"
  T="$(gl validate-round open vr-c7b "$SP")"   # spec committed and CLEAN at open
  sed 's/Status: DRAFT/Status: EDITED/' "$SP" > "$SP.tmp" && mv "$SP.tmp" "$SP"
  gl validate-round close vr-c7b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C7b close exits 2" "$([ "$RC" = 2 ]; echo $?)"
  WY="$(tail -1 "$(ledger vr-c7b)" | sed -nE 's/.*why=([^ ]+).*/\1/p')"
  assert "C7b why holds blob and porcelain" "$([ "$WY" = "blob,porcelain" ]; echo $?)"
fi
if want C7c; then
  echo "-- C7c excluded writers do not drift"
  new_log; R="$(mkrepo c7c)"; SP="$R/docs/specs/SPEC-001-vr-c7c.md"
  T="$(gl validate-round open vr-c7c "$SP")"
  mkdir -p "$R/_meta" "$R/.claude/session-state" "$R/lib/x/.pytest_cache" "$R/lib/y/.ruff_cache" "$R/lib/z/.mypy_cache" "$R/.hypothesis"
  printf 'x\n' > "$R/_meta/learned-ledger.md"; printf 'x\n' > "$R/.claude/session-state/last-state.md"
  printf 'x\n' > "$R/lib/x/.pytest_cache/v"; printf 'x\n' > "$R/lib/y/.ruff_cache/v"
  printf 'x\n' > "$R/lib/z/.mypy_cache/v"; printf 'x\n' > "$R/.hypothesis/x"
  gl validate-round close vr-c7c "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C7c excluded writers close clean (exit 0)" "$([ "$RC" = 0 ]; echo $?)"
  assert "C7c terminal ROUND close written" "$({ trap '' PIPE; tail -1 "$(ledger vr-c7c)" | grep -q '| ROUND | close | '; } && echo 0 || echo 1)"
fi

# ---------------------------------------------------------------------------
# C8: restart budget -- the second void since the last round-terminal stops the
# round as incomplete with reason `restart budget spent`, exit 3.
# ---------------------------------------------------------------------------
if want C8; then
  echo "-- C8 void budget"
  new_log; R="$(mkrepo c8)"; SP="$R/docs/specs/SPEC-001-vr-c8.md"
  T1="$(gl validate-round open vr-c8 "$SP")"
  printf 'edit1\n' >> "$SP"
  gl validate-round close vr-c8 "$T1" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC1=$?
  T2="$(gl validate-round open vr-c8 "$SP")"
  printf 'edit2\n' >> "$SP"
  gl validate-round close vr-c8 "$T2" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC2=$?
  assert "C8 first void exits 2" "$([ "$RC1" = 2 ]; echo $?)"
  assert "C8 second void exits 3 (budget spent)" "$([ "$RC2" = 3 ]; echo $?)"
  EXP="ROUND | closing | token=$T2 kind=incomplete | restart budget spent
GATE | validate | skipped | incomplete: restart budget spent
OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | skipped | incomplete: restart budget spent
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | incomplete | token=$T2"
  assert "C8 budget stop writes the incomplete block" "$([ "$(tailn vr-c8 6)" = "$EXP" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C8b: a round-terminal line resets the void budget: void, open, close
# NEEDS-REVISION, open, void -> the last void exits 2, not 3.
# ---------------------------------------------------------------------------
if want C8b; then
  echo "-- C8b budget reset by a round-terminal line"
  new_log; R="$(mkrepo c8b)"; SP="$R/docs/specs/SPEC-001-vr-c8b.md"
  T1="$(gl validate-round open vr-c8b "$SP")"
  printf 'edit1\n' >> "$SP"
  gl validate-round close vr-c8b "$T1" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC1=$?
  assert "C8b first close exits 2 (drift void)" "$([ "$RC1" = 2 ]; echo $?)"
  git -C "$R" checkout -q -- docs/specs/SPEC-001-vr-c8b.md
  T2="$(gl validate-round open vr-c8b "$SP")"
  gl validate-round close vr-c8b "$T2" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC2=$?
  T3="$(gl validate-round open vr-c8b "$SP")"
  printf 'edit3\n' >> "$SP"
  gl validate-round close vr-c8b "$T3" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC3=$?
  assert "C8b mid NEEDS-REVISION close exits 0" "$([ "$RC2" = 0 ]; echo $?)"
  assert "C8b third void exits 2 (budget was reset by ROUND close)" "$([ "$RC3" = 2 ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C9: a void then a clean APPROVED close; every GATE gets its own bracket pair.
# ---------------------------------------------------------------------------
if want C9; then
  echo "-- C9 void then pass"
  new_log; R="$(mkrepo c9)"; SP="$R/docs/specs/SPEC-001-vr-c9.md"
  T1="$(gl validate-round open vr-c9 "$SP")"
  printf 'edit\n' >> "$SP"
  gl validate-round close vr-c9 "$T1" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC1=$?
  assert "C9 first close exits 2 (drift void)" "$([ "$RC1" = 2 ]; echo $?)"
  git -C "$R" checkout -q -- docs/specs/SPEC-001-vr-c9.md
  T2="$(gl validate-round open vr-c9 "$SP")"
  gl validate-round close vr-c9 "$T2" verdict=APPROVED critical=0 warnings=2 agents=5 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C9 close after void exits 0" "$([ "$RC" = 0 ]; echo $?)"
  G=$(grep -c ' | GATE | validate | ' "$(ledger vr-c9)"); O=$(grep -c ' | OUTCOME | validate | end' "$(ledger vr-c9)")
  assert "C9 one GATE bracket per OUTCOME end for validate" "$([ "$G" = "$O" ]; echo $?)"
  G=$(grep -c ' | GATE | design-record | ' "$(ledger vr-c9)"); O=$(grep -c ' | OUTCOME | design-record | end' "$(ledger vr-c9)")
  assert "C9 one GATE bracket per OUTCOME end for design-record" "$([ "$G" = "$O" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C9b: validation-wide caught rollup (DEC-N window) on APPROVED closes.
# ---------------------------------------------------------------------------
if want C9b; then
  echo "-- C9b caught rollup"
  # NEEDS-REVISION(r6 pass) then APPROVED: validate caught=true, design-record false
  new_log; R="$(mkrepo c9b)"; SP="$R/docs/specs/SPEC-001-vr-c9b.md"
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  V=$(tailn vr-c9b 5 | sed -n '2p'); D=$(tailn vr-c9b 5 | sed -n '4p')
  assert "C9b NR-then-APPROVED: validate caught=true" "$({ trap '' PIPE; echo "$V" | grep -q 'OUTCOME | validate | end | at=E caught=true'; } && echo 0 || echo 1)"
  assert "C9b NR-then-APPROVED: design-record caught=false" "$({ trap '' PIPE; echo "$D" | grep -q 'OUTCOME | design-record | end | at=E caught=false'; } && echo 0 || echo 1)"
  # NEEDS-REVISION(r6 critical) then APPROVED: both true
  new_log
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes critical: x' >/dev/null 2>&1
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  D=$(tailn vr-c9b 5 | sed -n '4p')
  assert "C9b r6-critical first: design-record caught=true" "$({ trap '' PIPE; echo "$D" | grep -q 'OUTCOME | design-record | end | at=E caught=true'; } && echo 0 || echo 1)"
  OR="$(gl outcome-read vr-c9b validate 2>/dev/null)"
  assert "C9b outcome-read validate caught=true" "$({ trap '' PIPE; echo "$OR" | grep -q 'validate caught=true'; } && echo 0 || echo 1)"
  # a lone legacy `end caught=true` before the first open does not leak in
  new_log
  printf '%s | OUTCOME | validate | end | at=1 caught=true dur_s=1\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$(ledger vr-c9b)"
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  V=$(tailn vr-c9b 5 | sed -n '2p')
  assert "C9b legacy end line does not leak into the rollup" "$({ trap '' PIPE; echo "$V" | grep -q 'caught=false'; } && echo 0 || echo 1)"
  # a single-pass fallback (record+outcome outside a block) then a verb round
  new_log
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=NEEDS-REVISION critical=1 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  gl record vr-c9b Validate ran "fallback" >/dev/null 2>&1
  gl outcome vr-c9b Validate end caught=true >/dev/null 2>&1
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  V=$(tailn vr-c9b 5 | sed -n '2p'); D=$(tailn vr-c9b 5 | sed -n '4p')
  assert "C9b fallback caught=true outside a block: validate false" "$({ trap '' PIPE; echo "$V" | grep -q 'caught=false'; } && echo 0 || echo 1)"
  assert "C9b fallback caught=true outside a block: design-record false" "$({ trap '' PIPE; echo "$D" | grep -q 'caught=false'; } && echo 0 || echo 1)"
  # APPROVED-only validation keeps caught=false
  new_log
  T="$(gl validate-round open vr-c9b "$SP")"
  gl validate-round close vr-c9b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  V=$(tailn vr-c9b 5 | sed -n '2p')
  assert "C9b APPROVED-only keeps caught=false" "$({ trap '' PIPE; echo "$V" | grep -q 'caught=false'; } && echo 0 || echo 1)"
fi

# ---------------------------------------------------------------------------
# C10: incomplete -- closing kind=incomplete + paired skipped records + terminal.
# ---------------------------------------------------------------------------
if want C10; then
  echo "-- C10 incomplete"
  new_log; R="$(mkrepo c10)"; SP="$R/docs/specs/SPEC-001-vr-c10.md"
  T="$(gl validate-round open vr-c10 "$SP")"
  gl validate-round incomplete vr-c10 "$T" "reviewer 4 dead" >/dev/null 2>&1; RC=$?
  assert "C10 incomplete exits 0" "$([ "$RC" = 0 ]; echo $?)"
  EXP="ROUND | closing | token=$T kind=incomplete | reviewer 4 dead
GATE | validate | skipped | incomplete: reviewer 4 dead
OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | skipped | incomplete: reviewer 4 dead
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | incomplete | token=$T"
  assert "C10 incomplete block" "$([ "$(tailn vr-c10 6)" = "$EXP" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C10b: incomplete then a clean close still pairs every GATE with its end.
# ---------------------------------------------------------------------------
if want C10b; then
  echo "-- C10b incomplete pairs"
  new_log; R="$(mkrepo c10b)"; SP="$R/docs/specs/SPEC-001-vr-c10b.md"
  T="$(gl validate-round open vr-c10b "$SP")"
  gl validate-round incomplete vr-c10b "$T" "stopped" >/dev/null 2>&1
  T="$(gl validate-round open vr-c10b "$SP")"
  gl validate-round close vr-c10b "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
  assert "C10b close after incomplete exits 0" "$([ "$RC" = 0 ]; echo $?)"
  for ph in validate design-record; do
    G=$(grep -c " | GATE | $ph | " "$(ledger vr-c10b)"); O=$(grep -c " | OUTCOME | $ph | end" "$(ledger vr-c10b)")
    assert "C10b $ph: GATE count == OUTCOME end count (2)" "$([ "$G" = 2 ] && [ "$O" = 2 ]; echo $?)"
  done
fi

# ---------------------------------------------------------------------------
# C10c: --stale resolves the token from the last ROUND line (open and void).
# ---------------------------------------------------------------------------
if want C10c; then
  echo "-- C10c --stale"
  new_log; R="$(mkrepo c10c)"; SP="$R/docs/specs/SPEC-001-vr-c10c.md"
  T="$(gl validate-round open vr-c10c "$SP")"
  gl validate-round incomplete vr-c10c --stale "lead restarted" >/dev/null 2>&1; RC=$?
  assert "C10c --stale over open exits 0" "$([ "$RC" = 0 ]; echo $?)"
  EXP="ROUND | closing | token=$T kind=incomplete | lead restarted
GATE | validate | skipped | incomplete: lead restarted
OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | skipped | incomplete: lead restarted
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | incomplete | token=$T"
  assert "C10c --stale wrote the complete incomplete block" "$([ "$(tailn vr-c10c 6)" = "$EXP" ]; echo $?)"
  # over a void
  new_log
  T="$(gl validate-round open vr-c10c "$SP")"
  printf 'edit\n' >> "$SP"
  gl validate-round close vr-c10c "$T" verdict=APPROVED critical=0 warnings=0 agents=1 'r6=design-bearing=yes pass' >/dev/null 2>&1
  gl validate-round incomplete vr-c10c --stale "why2" >/dev/null 2>&1; RC=$?
  assert "C10c --stale over a void exits 0" "$([ "$RC" = 0 ]; echo $?)"
  EXP="ROUND | closing | token=$T kind=incomplete | why2
GATE | validate | skipped | incomplete: why2
OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | skipped | incomplete: why2
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | incomplete | token=$T"
  assert "C10c --stale over void wrote the complete block" "$([ "$(tailn vr-c10c 6)" = "$EXP" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C10d: resume -- a hand-written `closing` + partial records complete cleanly
# with no duplicates.
# ---------------------------------------------------------------------------
if want C10d; then
  echo "-- C10d resume"
  new_log; R="$(mkrepo c10d)"; SP="$R/docs/specs/SPEC-001-vr-c10d.md"
  T="$(gl validate-round open vr-c10d "$SP")"
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # simulate a crash after `closing` + the first GATE line
  printf '%s | ROUND | closing | token=%s kind=close verdict=APPROVED critical=0 warnings=3 agents=7 | design-bearing=yes pass | 0 critical\n' "$TS" "$T" >> "$(ledger vr-c10d)"
  printf '%s | GATE | validate | ran | APPROVED critical=0 warnings=3 fresh agents=7 parallel\n' "$TS" >> "$(ledger vr-c10d)"
  gl validate-round close vr-c10d "$T" >/dev/null 2>&1; RC=$?
  assert "C10d resume close exits 0" "$([ "$RC" = 0 ]; echo $?)"
  G=$(grep -c ' | GATE | validate | ran' "$(ledger vr-c10d)")
  assert "C10d GATE validate ran not duplicated" "$([ "$G" = 1 ]; echo $?)"
  EXP_TAIL="OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | ran | design-bearing=yes pass
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | close | token=$T verdict=APPROVED"
  assert "C10d resume tail completes the block" "$([ "$(tailn vr-c10d 4)" = "$EXP_TAIL" ]; echo $?)"
  # incomplete resume
  new_log
  T="$(gl validate-round open vr-c10d "$SP")"
  printf '%s | ROUND | closing | token=%s kind=incomplete | died mid-flight\n' "$TS" "$T" >> "$(ledger vr-c10d)"
  printf '%s | GATE | validate | skipped | incomplete: died mid-flight\n' "$TS" >> "$(ledger vr-c10d)"
  gl validate-round incomplete vr-c10d "$T" >/dev/null 2>&1; RC=$?
  assert "C10d resume incomplete exits 0" "$([ "$RC" = 0 ]; echo $?)"
  G=$(grep -c ' | GATE | validate | skipped' "$(ledger vr-c10d)")
  assert "C10d GATE validate skipped not duplicated" "$([ "$G" = 1 ]; echo $?)"
  EXP="ROUND | closing | token=$T kind=incomplete | died mid-flight
GATE | validate | skipped | incomplete: died mid-flight
OUTCOME | validate | end | at=E caught=false dur_s=D
GATE | design-record | skipped | incomplete: died mid-flight
OUTCOME | design-record | end | at=E caught=false dur_s=D
ROUND | incomplete | token=$T"
  assert "C10d resume completes the full incomplete block" "$([ "$(tailn vr-c10d 6)" = "$EXP" ]; echo $?)"

  # a forged line after `closing` is foreign, never adopted: both resume paths
  # must list it on stderr, refuse 1, and leave the ledger byte-identical
  new_log
  T="$(gl validate-round open vr-c10d "$SP")"
  printf '%s | ROUND | closing | token=%s kind=close verdict=APPROVED critical=0 warnings=3 agents=7 | design-bearing=yes pass | 0 critical\n' "$TS" "$T" >> "$(ledger vr-c10d)"
  gl record vr-c10d Validate ran "FORGED" >/dev/null 2>&1
  F="$(ledger vr-c10d)"; BEFORE="$(cat "$F")"
  ERRS="$(gl validate-round close vr-c10d "$T" 2>&1 >/dev/null)"; RC=$?
  assert "C10d forged record after closing: close exits 1" "$([ "$RC" = 1 ]; echo $?)"
  assert "C10d forged record named on stderr" "$({ trap '' PIPE; echo "$ERRS" | grep -q 'foreign: .*GATE | validate | ran | FORGED'; } && echo 0 || echo 1)"
  assert "C10d forged resume leaves the ledger unchanged" "$([ "$(cat "$F")" = "$BEFORE" ]; echo $?)"
  # same on the incomplete resume path
  new_log
  T="$(gl validate-round open vr-c10d "$SP")"
  printf '%s | ROUND | closing | token=%s kind=incomplete | died mid-flight\n' "$TS" "$T" >> "$(ledger vr-c10d)"
  gl record vr-c10d Validate ran "FORGED" >/dev/null 2>&1
  F="$(ledger vr-c10d)"; BEFORE="$(cat "$F")"
  ERRS="$(gl validate-round incomplete vr-c10d "$T" 2>&1 >/dev/null)"; RC=$?
  assert "C10d forged record under closing kind=incomplete: exits 1" "$([ "$RC" = 1 ]; echo $?)"
  assert "C10d forged record named on stderr (incomplete)" "$({ trap '' PIPE; echo "$ERRS" | grep -q 'foreign: .*FORGED'; } && echo 0 || echo 1)"
  assert "C10d forged incomplete-resume leaves ledger unchanged" "$([ "$(cat "$F")" = "$BEFORE" ]; echo $?)"
fi

# ---------------------------------------------------------------------------
# C11b: incomplete/resume/close-state refusals.
# ---------------------------------------------------------------------------
if want C11b; then
  echo "-- C11b incomplete/resume refusals"
  new_log; R="$(mkrepo c11b)"; SP="$R/docs/specs/SPEC-001-vr-c11b.md"
  T="$(gl validate-round open vr-c11b "$SP")"
  KEYS="verdict=APPROVED critical=0 warnings=0 agents=1"
  # full-key close over a closing round -> 1
  printf '%s | ROUND | closing | token=%s kind=close verdict=APPROVED critical=0 warnings=0 agents=1 | design-bearing=yes pass | 0 critical\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T" >> "$(ledger vr-c11b)"
  refuse 1 "C11b full-key close over a closing round" vr-c11b gl validate-round close vr-c11b "$T" $KEYS 'r6=design-bearing=yes pass'
  # bare close over closing kind=incomplete -> 1
  new_log
  T="$(gl validate-round open vr-c11b "$SP")"
  printf '%s | ROUND | closing | token=%s kind=incomplete | died\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T" >> "$(ledger vr-c11b)"
  refuse 1 "C11b close-resume over closing kind=incomplete" vr-c11b gl validate-round close vr-c11b "$T"
  # incomplete reason charset (64)
  new_log; T="$(gl validate-round open vr-c11b "$SP")"
  refuse 64 "C11b incomplete empty reason" vr-c11b gl validate-round incomplete vr-c11b "$T" ""
  refuse 64 "C11b --stale empty reason" vr-c11b gl validate-round incomplete vr-c11b --stale ""
  refuse 64 "C11b incomplete reason with pipe" vr-c11b gl validate-round incomplete vr-c11b "$T" 'a | b'
  refuse 64 "C11b incomplete reason with newline" vr-c11b gl validate-round incomplete vr-c11b "$T" "a
b"
  refuse 64 "C11b incomplete reason with CR" vr-c11b gl validate-round incomplete vr-c11b "$T" "a$(printf '\r')b"
  refuse 64 "C11b incomplete malformed token" vr-c11b gl validate-round incomplete vr-c11b "deadbeef.1" "x"
  refuse 64 "C11b incomplete token then newline" vr-c11b gl validate-round incomplete vr-c11b "$T
x" "r"
  # --stale refusals
  refuse 1 "C11b --stale with no round" vr-nope gl validate-round incomplete vr-nope --stale "x"
  # --stale over closing kind=close -> 1
  new_log; T="$(gl validate-round open vr-c11b "$SP")"
  printf '%s | ROUND | closing | token=%s kind=close verdict=APPROVED critical=0 warnings=0 agents=1 | design-bearing=yes pass | 0 critical\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T" >> "$(ledger vr-c11b)"
  refuse 1 "C11b --stale over closing kind=close" vr-c11b gl validate-round incomplete vr-c11b --stale "x"
  # incomplete <rid> <token> over open (no reason) is not a resume -> 1
  new_log; T="$(gl validate-round open vr-c11b "$SP")"
  refuse 1 "C11b incomplete with token but no reason over open" vr-c11b gl validate-round incomplete vr-c11b "$T"
  # --stale over closing kind=incomplete ignores the given reason (stderr note)
  new_log; T="$(gl validate-round open vr-c11b "$SP")"
  printf '%s | ROUND | closing | token=%s kind=incomplete | pinned reason\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T" >> "$(ledger vr-c11b)"
  ERRS="$(gl validate-round incomplete vr-c11b --stale "other reason" 2>&1 >/dev/null)"; RC=$?
  assert "C11b --stale resumes a closing kind=incomplete" "$([ "$RC" = 0 ]; echo $?)"
  assert "C11b --stale prints the ignored reason" "$({ trap '' PIPE; echo "$ERRS" | grep -q 'other reason'; } && echo 0 || echo 1)"
  assert "C11b pinned reason kept on the records" "$({ trap '' PIPE; grep -q 'incomplete: pinned reason' "$(ledger vr-c11b)"; } && echo 0 || echo 1)"
  # git failure in close on a present regular spec -> 1, no void, never 128 --
  # one leg per git call the verb makes
  for sub in hash-object rev-parse status; do
    new_log; T="$(gl validate-round open vr-c11b "$SP")"
    SHIM="$(gitshim "$sub")"
    BEFORE="$(cat "$(ledger vr-c11b)")"
    env PATH="$SHIM:/usr/bin:/bin" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" validate-round close vr-c11b "$T" $KEYS 'r6=design-bearing=yes pass' >/dev/null 2>&1; RC=$?
    assert "C11b git $sub failure in close exits 1 (never 128)" "$([ "$RC" = 1 ]; echo $?)"
    assert "C11b git $sub failure wrote nothing" "$([ "$(cat "$(ledger vr-c11b)")" = "$BEFORE" ]; echo $?)"
  done
fi

# ---------------------------------------------------------------------------
# C12: additive equivalence -- every marker-keyed reader is byte-identical with
# the ROUND lines stripped; last-timestamp readers differ only there.
# ---------------------------------------------------------------------------
if want C12; then
  echo "-- C12 additive equivalence"
  D1="$(_mk)/with"; D2="$(_mk)/without"; mkdir -p "$D1/runs" "$D2/runs"
  F1="$D1/runs/vr-c12.log"
  # hand-built ledger: the same records either way, plus ROUND lines (last one a
  # second later than the last record so last-timestamp readers move). Dated
  # TODAY so `report`'s window includes it -- report has no --period year.
  TSD="$(date -u +%Y-%m-%d)"
  cat > "$F1" <<EOF
${TSD}T00:00:00Z | START | lane=full classified=full type=feature repo=vr-c12
${TSD}T00:00:01Z | OUTCOME | validate | start | at=1790000001
${TSD}T00:00:01Z | OUTCOME | design-record | start | at=1790000001
${TSD}T00:00:01Z | ROUND | open | token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.1790000001.1 top=/tmp/x spec=/tmp/x/docs/specs/SPEC-001-vr-c12.md blob=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb porcelain=cccccccccccccccccccccccccccccccccccccccc
${TSD}T00:00:02Z | ROUND | closing | token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.1790000001.1 kind=close verdict=APPROVED critical=0 warnings=0 agents=3 | design-bearing=yes pass | 0 critical
${TSD}T00:00:02Z | GATE | validate | ran | APPROVED critical=0 warnings=0 fresh agents=3 parallel
${TSD}T00:00:02Z | OUTCOME | validate | end | at=1790000002 caught=false dur_s=1
${TSD}T00:00:02Z | GATE | design-record | ran | design-bearing=yes pass
${TSD}T00:00:02Z | OUTCOME | design-record | end | at=1790000002 caught=false dur_s=1
${TSD}T00:00:03Z | GATE | build | ran | ok
${TSD}T00:00:03Z | GATE | ship | ran | ok
${TSD}T00:00:04Z | ROUND | close | token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.1790000001.1 verdict=APPROVED
EOF
  grep -v ' | ROUND | ' "$F1" > "$D2/runs/vr-c12.log"
  # marker-keyed readers: byte-identical across the two ledgers
  for v in "check full vr-c12" "progress vr-c12 full" "descent vr-c12 full" "outcome-read vr-c12" "outcome-read vr-c12 design-record"; do
    O1="$(env DWARVES_KIT_LOG_DIR="$D1" bash "$GL" $v 2>/dev/null)"; R1=$?
    O2="$(env DWARVES_KIT_LOG_DIR="$D2" bash "$GL" $v 2>/dev/null)"; R2=$?
    assert "C12 '$v' byte-identical (rc $R1/$R2)" "$([ "$R1" = "$R2" ] && [ "$O1" = "$O2" ]; echo $?)"
  done
  O1="$(env DWARVES_KIT_LOG_DIR="$D1" bash "$GL" report --period month 2>/dev/null)"
  O2="$(env DWARVES_KIT_LOG_DIR="$D2" bash "$GL" report --period month 2>/dev/null)"
  assert "C12 report --period month non-empty (run inside the window)" "$([ -n "$O1" ] && { trap '' PIPE; echo "$O1" | grep -q 'vr-c12'; } && echo 0 || echo 1)"
  assert "C12 report --period month byte-identical" "$([ "$O1" = "$O2" ]; echo $?)"
  # python marker readers
  A1="$(env DWARVES_KIT_LOG_DIR="$D1" python3 -c "import sys,os;from pathlib import Path;sys.path.insert(0,'$KIT_DIR/lib/stats/src');from stats.adapters import read_kit_gates;print(read_kit_gates(Path(os.environ['DWARVES_KIT_LOG_DIR'])/'runs'))" 2>/dev/null)"
  A2="$(env DWARVES_KIT_LOG_DIR="$D2" python3 -c "import sys,os;from pathlib import Path;sys.path.insert(0,'$KIT_DIR/lib/stats/src');from stats.adapters import read_kit_gates;print(read_kit_gates(Path(os.environ['DWARVES_KIT_LOG_DIR'])/'runs'))" 2>/dev/null)"
  assert "C12 read_kit_gates identical" "$([ -n "$A1" ] && [ "$A1" = "$A2" ]; echo $?)"
  M1="$(python3 -c "import sys;sys.path.insert(0,'$KIT_DIR/lib/mega');import importlib.util;spec=importlib.util.spec_from_file_location('mr','$KIT_DIR/lib/mega/mega-report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);print(m.parse_ledger('$D1','vr-c12'))" 2>/dev/null)"
  M2="$(python3 -c "import sys;sys.path.insert(0,'$KIT_DIR/lib/mega');import importlib.util;spec=importlib.util.spec_from_file_location('mr','$KIT_DIR/lib/mega/mega-report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);print(m.parse_ledger('$D2','vr-c12'))" 2>/dev/null)"
  assert "C12 mega-report parse_ledger identical" "$([ -n "$M1" ] && [ "$M1" = "$M2" ]; echo $?)"
  P1="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('ptg','$KIT_DIR/lib/gate/proof-table-gen.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);print(m.parse_ledger('$F1'))" 2>/dev/null)"
  P2="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('ptg','$KIT_DIR/lib/gate/proof-table-gen.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);print(m.parse_ledger('$D2/runs/vr-c12.log'))" 2>/dev/null)"
  assert "C12 proof-table-gen parse_ledger identical" "$([ -n "$P1" ] && [ "$P1" = "$P2" ]; echo $?)"
  # generator output confined under a scratch KIT_ROOT; the rendered file embeds
  # the ledger path, so normalize each log dir before comparing
  KR="$(_mk)/kitroot"; mkdir -p "$KR/docs/verification/generated"
  env KIT_ROOT="$KR" KIT_LOG_DIR="$D1" python3 "$KIT_DIR/lib/gate/proof-table-gen.py" vr-c12 "$KR/docs/verification/generated/d1.md" >/dev/null 2>&1; G1_RC=$?
  env KIT_ROOT="$KR" KIT_LOG_DIR="$D2" python3 "$KIT_DIR/lib/gate/proof-table-gen.py" vr-c12 "$KR/docs/verification/generated/d2.md" >/dev/null 2>&1
  sed "s|$D1|LOGDIR|g" "$KR/docs/verification/generated/d1.md" > "$KR/d1.norm" 2>/dev/null
  sed "s|$D2|LOGDIR|g" "$KR/docs/verification/generated/d2.md" > "$KR/d2.norm" 2>/dev/null
  assert "C12 proof-table generated output identical modulo ledger path" "$([ "$G1_RC" = 0 ] && cmp -s "$KR/d1.norm" "$KR/d2.norm"; echo $?)"
  # pitch/execute greps
  S1="$(env DWARVES_KIT_LOG_DIR="$D1" bash "$GL" show vr-c12 | grep -Ei '\| GATE \| (grill|validate) \| ' | tail -1)"
  S2="$(env DWARVES_KIT_LOG_DIR="$D2" bash "$GL" show vr-c12 | grep -Ei '\| GATE \| (grill|validate) \| ' | tail -1)"
  assert "C12 execute/pitch GATE greps identical" "$([ "$S1" = "$S2" ]; echo $?)"
  # last-timestamp readers: identical except the moved last ts / derived value
  H1="$(env DWARVES_KIT_LOG_DIR="$D1" bash "$GL" history --json 2>/dev/null | grep vr-c12)"
  H2="$(env DWARVES_KIT_LOG_DIR="$D2" bash "$GL" history --json 2>/dev/null | grep vr-c12)"
  N1="$(echo "$H1" | sed -E "s/${TSD}T[0-9:]+Z/TS/g")"; N2="$(echo "$H2" | sed -E "s/${TSD}T[0-9:]+Z/TS/g")"
  assert "C12 history identical modulo timestamps" "$([ "$N1" = "$N2" ] && [ "$H1" != "$H2" ]; echo $?)"
  RS1="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('rp','$KIT_DIR/lib/bench/report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);r=m.run_summary('$F1');print({k:v for k,v in r.items() if k!='t1'},r['t1'])" 2>/dev/null)"
  RS2="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('rp','$KIT_DIR/lib/bench/report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);r=m.run_summary('$D2/runs/vr-c12.log');print({k:v for k,v in r.items() if k!='t1'},r['t1'])" 2>/dev/null)"
  assert "C12 report.run_summary identical modulo t1" "$([ -n "$RS1" ] && [ "${RS1% *}" = "${RS2% *}" ] && [ "$RS1" != "$RS2" ]; echo $?)"
  E1="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('ev','$KIT_DIR/lib/bench/events.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);ev=m.ledger_to_events('$F1');last=ev[-1];print(ev[:-1], last.get('ev'), last.get('status'), {k:v for k,v in last.get('totals',{}).items() if k!='duration_s'}, last.get('totals',{}).get('duration_s'))" 2>/dev/null)"
  E2="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('ev','$KIT_DIR/lib/bench/events.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);ev=m.ledger_to_events('$D2/runs/vr-c12.log');last=ev[-1];print(ev[:-1], last.get('ev'), last.get('status'), {k:v for k,v in last.get('totals',{}).items() if k!='duration_s'}, last.get('totals',{}).get('duration_s'))" 2>/dev/null)"
  assert "C12 events.ledger_to_events identical modulo duration_s" "$([ -n "$E1" ] && [ "${E1% *}" = "${E2% *}" ] && [ "$E1" != "$E2" ]; echo $?)"
  DSH1="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('db','$KIT_DIR/lib/bench/dashboard.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);rows=m.collect_runs('$D1');print([{k:v for k,v in r.items() if k!='t1'} for r in rows],[r['t1'] for r in rows])" 2>/dev/null)"
  DSH2="$(python3 -c "import importlib.util;spec=importlib.util.spec_from_file_location('db','$KIT_DIR/lib/bench/dashboard.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);rows=m.collect_runs('$D2');print([{k:v for k,v in r.items() if k!='t1'} for r in rows],[r['t1'] for r in rows])" 2>/dev/null)"
  assert "C12 dashboard.collect_runs identical modulo t1" "$([ -n "$DSH1" ] && [ "${DSH1% \[*}" = "${DSH2% \[*}" ] && [ "$DSH1" != "$DSH2" ]; echo $?)"
  # lane-telemetry report: same rows modulo the `last` column timestamp
  T1o="$(env DWARVES_KIT_LOG_DIR="$D1" bash "$KIT_DIR/lib/telemetry/lane-telemetry.sh" report 2>/dev/null | sed -E "s/${TSD}T[0-9:]+Z/TS/g")"
  T2o="$(env DWARVES_KIT_LOG_DIR="$D2" bash "$KIT_DIR/lib/telemetry/lane-telemetry.sh" report 2>/dev/null | sed -E "s/${TSD}T[0-9:]+Z/TS/g")"
  assert "C12 lane-telemetry report identical modulo timestamps" "$([ -n "$T1o" ] && [ "$T1o" = "$T2o" ]; echo $?)"
fi

echo ""
echo "=== results: $PASS/$TOTAL pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ]

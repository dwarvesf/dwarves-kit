#!/usr/bin/env bash
# test-ship-gate-fail-closed.sh -- the lane arm fails CLOSED on spec-exists-no-lane in an adopted
# repo, and stays fail-open everywhere else. Drives hooks/ship-gate.sh with crafted stdin.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"   # quality gates are opt-in; this suite exercises them ON
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

LOGDIR="$(mktemp -d)"   # isolate the gate-ledger store from the real one

mkrepo() { # $1=dir  $2=adopted(yes/no)
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  mkdir -p "$1/docs/specs"
  if [ "$2" = yes ]; then mkdir -p "$1/docs/verification"; echo marker > "$1/docs/verification/README.md"; fi
  git -C "$1" add -A; git -C "$1" commit -qm init
}

gate() { # $1=repo  $2=command  -> echoes exit code
  ( cd "$1" && printf '{"tool_input":{"command":"%s"}}' "$2" \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1; echo $? )
}

# 1. spec, NO lane, adopted -> BLOCK (exit 2)
T1="$(mktemp -d)"; mkrepo "$T1" yes
git -C "$T1" switch -qc feat/sgone
printf '# Spec: x\nStatus: DRAFT\n' > "$T1/docs/specs/SPEC-001-sgone.md"
git -C "$T1" add -A; git -C "$T1" commit -qm spec
[ "$(gate "$T1" 'git push -u origin HEAD')" = 2 ] && ok "spec + no-lane + adopted -> blocked (exit 2)" || no "spec-no-lane-adopted should block"

# 2. spec WITH lane + all gates recorded -> PASS (exit 0), for every accepted header shape.
# The canonical form is plain `Lane: full`; the two markdown-bold variants must parse the
# same, because a bold header used to BLOCK the push with "Spec has no 'Lane:' header".
lane_header_case() { # $1=slug  $2=header line
  local d; d="$(mktemp -d)"; mkrepo "$d" yes
  git -C "$d" switch -qc "feat/$1"
  printf '# Spec: x\nStatus: DRAFT\n%s\n' "$2" > "$d/docs/specs/SPEC-001-$1.md"
  mkdir -p "$d/docs/implementation-notes"   # a full-lane push needs its notes file
  printf '# Notes\nNo deviations; matches the spec verbatim\n' > "$d/docs/implementation-notes/$1.md"
  git -C "$d" add -A; git -C "$d" commit -qm spec
  while read -r g; do
    DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/lib/gate/gate-ledger.sh" record "$1" "$g" ran "test" >/dev/null 2>&1
  done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/lib/gate/gate-ledger.sh" required full)
  [ "$(gate "$d" 'git push -u origin HEAD')" = 0 ] \
    && ok "header '$2' parsed as lane full -> pass (exit 0)" \
    || no "header '$2' should parse as lane full and pass"
}
lane_header_case sgtwo   'Lane: full'
lane_header_case sgtwob  '**Lane**: full'
lane_header_case sgtwoc  '**Lane:** full'

# 3. spec, no lane, NOT adopted (no marker) -> fail open (exit 0)
T3="$(mktemp -d)"; mkrepo "$T3" no
git -C "$T3" switch -qc feat/sgthree
printf '# Spec: x\nStatus: DRAFT\n' > "$T3/docs/specs/SPEC-001-sgthree.md"
git -C "$T3" add -A; git -C "$T3" commit -qm spec
[ "$(gate "$T3" 'git push -u origin HEAD')" = 0 ] && ok "spec + no-lane + NOT adopted -> fail open (exit 0)" || no "no-marker should fail open"

# 4. no spec for the slug -> fail open (exit 0)
T4="$(mktemp -d)"; mkrepo "$T4" yes
git -C "$T4" switch -qc feat/sgfour
echo x > "$T4/foo.txt"; git -C "$T4" add -A; git -C "$T4" commit -qm c
[ "$(gate "$T4" 'git push -u origin HEAD')" = 0 ] && ok "no spec for slug -> fail open (exit 0)" || no "no-spec should fail open"

# 5. non-push command -> exit 0 (gate not engaged)
[ "$(gate "$T1" 'git status')" = 0 ] && ok "non-push command -> exit 0" || no "non-push should exit 0"

# 6. START-AMEND lane resolution: the last amend wins over the spec header; a plain START never does.
# $1=slug $2=spec header lane $3=gates to record (lane name) $4=ledger verb line ("" | amend <lane> | start <lane>)
amend_case() {
  local d; d="$(mktemp -d)"; mkrepo "$d" yes
  git -C "$d" switch -qc "feat/$1"
  printf '# Spec: x\nStatus: DRAFT\nLane: %s\n' "$2" > "$d/docs/specs/SPEC-001-$1.md"
  mkdir -p "$d/docs/implementation-notes"
  printf '# Notes\nNo deviations; matches the spec verbatim\n' > "$d/docs/implementation-notes/$1.md"
  git -C "$d" add -A; git -C "$d" commit -qm spec
  local GL="$KIT/lib/gate/gate-ledger.sh"
  DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$GL" start "$1" "$2" "$2" spec-feature spec-feature r >/dev/null 2>&1
  case "$4" in
    amend\ *) DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$GL" start --amend "$1" "${4#amend }" full spec-feature spec-feature r >/dev/null 2>&1 ;;
    start\ *) DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$GL" start "$1" "${4#start }" full spec-feature spec-feature r >/dev/null 2>&1 ;;
  esac
  while read -r g; do
    DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$GL" record "$1" "$g" ran "test" >/dev/null 2>&1
  done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$GL" required "$3")
  # a task-less spec counts as large on the normal lane, so it owes a validate disposition
  DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$GL" record "$1" validate ran "test" >/dev/null 2>&1
  gate "$d" 'git push -u origin HEAD'
}
[ "$(amend_case amdone full normal 'amend normal')" = 0 ] && ok "spec full + amend normal + normal gates -> pass (amend clears full-only gates)" || no "amend to normal should clear full-only gates"
[ "$(amend_case amdtwo full normal '')" = 2 ] && ok "spec full + no amend + normal gates -> blocked (full kept)" || no "no amend should keep the full lane"
[ "$(amend_case amdthree normal normal 'amend full')" = 2 ] && ok "spec normal + amend full + normal gates -> blocked (amend raises)" || no "amend to full should raise a normal run"
[ "$(amend_case amdfour full normal 'start normal')" = 2 ] && ok "spec full + second plain START normal -> blocked (plain START never lowers)" || no "a plain START must not override the spec lane"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

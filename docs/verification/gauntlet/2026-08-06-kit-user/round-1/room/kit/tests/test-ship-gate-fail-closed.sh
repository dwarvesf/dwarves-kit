#!/usr/bin/env bash
# test-ship-gate-fail-closed.sh -- the lane arm fails CLOSED on spec-exists-no-lane in an adopted
# repo, and stays fail-open everywhere else. Drives hooks/ship-gate.sh with crafted stdin.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
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

# 2. spec WITH lane + all gates recorded -> PASS (exit 0)
T2="$(mktemp -d)"; mkrepo "$T2" yes
git -C "$T2" switch -qc feat/sgtwo
printf '# Spec: x\nStatus: DRAFT\nLane: full\n' > "$T2/docs/specs/SPEC-001-sgtwo.md"
git -C "$T2" add -A; git -C "$T2" commit -qm spec
while read -r g; do
  DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/lib/gate/gate-ledger.sh" record sgtwo "$g" ran "test" >/dev/null 2>&1
done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/lib/gate/gate-ledger.sh" required full)
[ "$(gate "$T2" 'git push -u origin HEAD')" = 0 ] && ok "spec + lane + gates recorded -> pass (exit 0)" || no "spec+lane+gates should pass"

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

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

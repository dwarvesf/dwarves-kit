#!/usr/bin/env bash
# test-mega-gate-parity.sh -- a green `mega-merge.sh gate` means the push passes the ship-gate's two
# diff and spec rules (large-spec validate, hard-path floor). Both callers share lib/gate/ship-rules.sh.
# Each case runs hooks/ship-gate.sh and mega-merge.sh gate against one temp repo and compares exit
# codes and, on a block, the BLOCKED message byte for byte.
# Run: bash tests/test-mega-gate-parity.sh   (exit 0 = all green)
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
LOGDIR="$(mktemp -d)"
LEDGER="$KIT/lib/gate/gate-ledger.sh"
MM="${MEGA_GATE_PARITY_MM:-$KIT/lib/goal/mega-merge.sh}"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

mkrepo() { # $1=dir $2=slug $3=tasks $4=nomarker-or-empty -> repo on feat/<slug>, normal-lane spec committed
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  mkdir -p "$1/docs/specs"
  if [ "${4:-}" != nomarker ]; then mkdir -p "$1/docs/verification"; echo marker > "$1/docs/verification/README.md"; fi
  : > "$1/.keep"
  # A tracked, clean project lane override: normal makes docs required (it is light in the kit default).
  if [ "${5:-}" = kittoml ]; then
    printf '[lane.normal]\nphases = ["think", "spec", "validate", "design-record", "test-plan", "build", "review", "docs", "ship"]\nlight  = ["think", "validate", "design-record", "test-plan"]\n' > "$1/.kit.toml"
  fi
  git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" switch -qc "feat/$2"
  { printf '# Spec: x\nStatus: DRAFT\nLane: normal\n\n'; local i; for i in $(seq 1 "$3"); do printf -- '- [ ] TASK-%s: x\n' "$i"; done; } > "$1/docs/specs/SPEC-001-$2.md"
  git -C "$1" add -A; git -C "$1" commit -qm spec
}
gates() { # $1=slug $2=lane [$3=skip phase] -> record every required phase as ran
  local g
  while read -r g; do
    [ "$g" = "${3:-}" ] && continue
    DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" record "$1" "$g" ran "test" >/dev/null 2>&1
  done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" required "$2")
}
ship() { # $1=repo $2=stderr-file -> exit code of the push gate
  ( cd "$1" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$2"; echo $? )
}
mega() { # $1=repo $2=rid $3=lane $4=stderr-file [$5=subdir to run from] -> exit code of the mega gate
  ( cd "$1/${5:-}" && DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$MM" gate "$2" "$3" >/dev/null 2>"$4"; echo $? )
}
# case <label> <repo> <slug> <expect-block 0|1> <message-pattern>
parity() {
  local label="$1" repo="$2" slug="$3" block="$4" pat="$5" es em rs rmega blk
  es="$(mktemp)"; em="$(mktemp)"
  rs="$(ship "$repo" "$es")"; rmega="$(mega "$repo" "$slug" normal "$em")"
  if [ "$block" = 1 ]; then
    blk="$(mktemp)"; sed -n '/^BLOCKED: ship-gate/,$p' "$es" > "$blk"
    if [ "$rs" = 2 ] && [ "$rmega" = 1 ] && grep -q -- "$pat" "$es" && cmp -s "$blk" "$em"; then ok "$label: ship gate exit $rs, mega gate exit $rmega, same message"
    else no "$label: want ship 2 / mega 1 / same /$pat/; got ship $rs, mega $rmega; ship: $(tr '\n' ' ' < "$es"); mega: $(tr '\n' ' ' < "$em")"; fi
  else
    if [ "$rs" = 0 ] && [ "$rmega" = 0 ]; then ok "$label: ship gate exit $rs, mega gate exit $rmega"
    else no "$label: want both 0; got ship $rs, mega $rmega; ship: $(tr '\n' ' ' < "$es"); mega: $(tr '\n' ' ' < "$em")"; fi
  fi
}

# a: large normal spec, no validate
R="$(mktemp -d)"; mkrepo "$R" pa 5; gates pa normal
parity "a large normal spec without validate" "$R" pa 1 'is large (4+ tasks'
# b: same, with a validate override
DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" override pa validate "test" >/dev/null 2>&1
parity "b large spec with a validate override" "$R" pa 0 ''

# c: a hard path (.github/) touched under a normal-lane ledger that lacks the full lane's phases
R="$(mktemp -d)"; mkrepo "$R" pc 1 nomarker; gates pc normal
mkdir -p "$R/.github/workflows"; printf 'name: x\n' > "$R/.github/workflows/ci.yml"; git -C "$R" add -A; git -C "$R" commit -qm ci
parity "c hard path under a normal ledger" "$R" pc 1 'touches a hard path (ci: .github/workflows/ci.yml'
# d: every full phase recorded
gates pc full
parity "d hard path with every full phase recorded" "$R" pc 0 ''

# e: small spec, normal lane, no hard path
R="$(mktemp -d)"; mkrepo "$R" pe 1; gates pe normal
printf 'y\n' > "$R/notes.txt"; git -C "$R" add -A; git -C "$R" commit -qm notes
parity "e small spec, no hard path" "$R" pe 0 ''

# f: a hard-path diff with no spec at all still owes the full lane's gates in both gates
R="$(mktemp -d)"; mkrepo "$R" pf 1 nomarker; gates pf normal; git -C "$R" rm -q "docs/specs/SPEC-001-pf.md"; git -C "$R" commit -qm nospec
mkdir -p "$R/.github/workflows"; printf 'name: x\n' > "$R/.github/workflows/ci.yml"; git -C "$R" add -A; git -C "$R" commit -qm ci
parity "f hard path, no spec, no ledger" "$R" pf 1 'no spec found'

# g: a project .kit.toml lane override makes docs required. The hook reads it from the repo root; the
# mega gate runs from a subdirectory, where the cwd fallback finds no .kit.toml. Both must block.
R="$(mktemp -d)"; mkrepo "$R" pg 1 "" kittoml; gates pg normal; mkdir -p "$R/sub"
eg="$(mktemp)"; em="$(mktemp)"
rsg="$(ship "$R" "$eg")"; rmg="$(mega "$R" pg normal "$em" sub)"
if [ "$rsg" = 2 ] && [ "$rmg" = 1 ] && grep -q 'MISSING-GATE: docs' "$eg" && grep -q 'MISSING-GATE: docs' "$em"; then ok "g project lane override: ship gate exit $rsg, mega gate exit $rmg, both name docs"
else no "g want ship 2 / mega 1 / MISSING-GATE: docs; got ship $rsg, mega $rmg; ship: $(tr '\n' ' ' < "$eg"); mega: $(tr '\n' ' ' < "$em")"; fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# test-ship-gate-coverage-map.sh -- ID-466: spec ## Test plan -> proof-of-done coverage map.
# The ship-gate WARNS (advisory, never blocks) when the spec has a test plan but the proof
# doc carries no ## Test plan coverage map, or the map leaves matrix rows unmapped. No test
# plan = no new requirement. Drives proof-gate.sh coverage directly, then hooks/ship-gate.sh
# with crafted stdin (same harness shape as test-ship-gate-fail-closed.sh).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

LOGDIR="$(mktemp -d)"   # isolate the gate-ledger store from the real one
PG="$KIT/lib/gate/proof-gate.sh"

# --- unit: proof-gate.sh coverage ---------------------------------------------------------
FIX="$(mktemp -d)"
cat > "$FIX/spec.md" <<'EOF'
# Spec: x
Lane: full

## Test plan

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | happy | happy-path | AC-1 | ok | cmd |
| 2 | edge | boundary | AC-1 | ok | cmd |
| 3 | fail | failure-injection | AC-2 | err | cmd |

### Coverage notes
- none

## Test plan critique
| # | Finding |
|---|---|
| 9 | a critique row, must not count as a plan row |

## Verification
EOF
cat > "$FIX/spec-dialect.md" <<'EOF'
## Test plan

| Category | Case | How |
|---|---|---|
| Happy path | a | run it |
| Edge | b | run it |
EOF
cat > "$FIX/spec-noplan.md" <<'EOF'
# Spec: y
Lane: tiny
## Verification
EOF
cat > "$FIX/proof-full.md" <<'EOF'
## Test plan coverage
| Row | Run / skip reason |
|---|---|
| 1 | R1 |
| 2 | R2 |
| 3 | skipped: env-only |
EOF
cat > "$FIX/proof-partial.md" <<'EOF'
## Test plan coverage
| Row | Run / skip reason |
|---|---|
| 1 | R1 |
EOF
cat > "$FIX/proof-nomap.md" <<'EOF'
Command: `x` Exit: 0 Verdict: PASS
NEGATIVE CONTROL
EOF

[ "$(bash "$PG" coverage "$FIX/spec-noplan.md" "$FIX/proof-full.md")" = "no-test-plan" ] \
  && ok "coverage: no ## Test plan -> no-test-plan" || no "no-plan spec should report no-test-plan"
[ "$(bash "$PG" coverage "$FIX/spec.md" "$FIX/proof-nomap.md")" = "NO-MAP rows=3" ] \
  && ok "coverage: plan + proof without map -> NO-MAP rows=3" || no "mapless proof should report NO-MAP"
[ "$(bash "$PG" coverage "$FIX/spec.md")" = "NO-MAP rows=3" ] \
  && ok "coverage: plan + no proof files -> NO-MAP" || no "no proof files should report NO-MAP"
[ "$(bash "$PG" coverage "$FIX/spec.md" "$FIX/proof-partial.md")" = "UNMAPPED: 2 3" ] \
  && ok "coverage: partial map -> UNMAPPED: 2 3" || no "partial map should report the unmapped rows"
[ "$(bash "$PG" coverage "$FIX/spec.md" "$FIX/proof-full.md")" = "OK" ] \
  && ok "coverage: all rows mapped -> OK (critique table not counted)" || no "full map should report OK"
[ "$(bash "$PG" coverage "$FIX/spec-dialect.md" "$FIX/proof-partial.md")" = "UNMAPPED: 2" ] \
  && ok "coverage: no-# dialect falls back to ordinals" || no "dialect matrix should use ordinal row ids"

# --- hook: ship-gate advisory wiring ------------------------------------------------------
mkrepo() { # $1=dir  (adopted repo: proof marker present)
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  mkdir -p "$1/docs/specs" "$1/docs/verification"
  echo marker > "$1/docs/verification/README.md"
  git -C "$1" add -A; git -C "$1" commit -qm init
}

gate() { # $1=repo  $2=command  $3=stderr-capture  -> echoes exit code
  ( cd "$1" && printf '{"tool_input":{"command":"%s"}}' "$2" \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$3"; echo $? )
}

record_gates() { # $1=slug -- record every gate the full lane requires, so the lane arm passes
  while read -r g; do
    DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/lib/gate/gate-ledger.sh" record "$1" "$g" ran "test" >/dev/null 2>&1
  done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/lib/gate/gate-ledger.sh" required full)
}

spec_with_plan() { # $1=path -- a full-lane spec carrying a 2-row ## Test plan
  cat > "$1" <<'EOF'
# Spec: x
Status: DRAFT
Lane: full

## Test plan

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | happy | happy-path | AC-1 | ok | cmd |
| 2 | edge | boundary | AC-1 | ok | cmd |
EOF
}

# (a) test plan + proof WITHOUT coverage map -> warning emitted, merge NOT blocked
TA="$(mktemp -d)"; mkrepo "$TA"
git -C "$TA" switch -qc feat/cmapa
spec_with_plan "$TA/docs/specs/SPEC-001-cmapa.md"
printf 'Command: `x`\nExit: 0\nVerdict: PASS\nNEGATIVE CONTROL\n' > "$TA/docs/verification/cmapa.md"
git -C "$TA" add -A; git -C "$TA" commit -qm work
record_gates cmapa
EA="$(mktemp)"
RCA="$(gate "$TA" 'git push -u origin HEAD' "$EA")"
[ "$RCA" = 0 ] && grep -q '\[advisory\] test-plan coverage' "$EA" \
  && ok "(a) plan + mapless proof -> advisory emitted, exit 0 (not blocked)" \
  || no "(a) expected exit 0 + coverage advisory; got exit $RCA, stderr: $(cat "$EA")"

# (b) all rows mapped -> no warning
TB="$(mktemp -d)"; mkrepo "$TB"
git -C "$TB" switch -qc feat/cmapb
spec_with_plan "$TB/docs/specs/SPEC-001-cmapb.md"
printf 'NEGATIVE CONTROL\nVerdict: PASS\n\n## Test plan coverage\n| Row | Run / skip reason |\n|---|---|\n| 1 | R1 |\n| 2 | skipped: covered by row 1 |\n' > "$TB/docs/verification/cmapb.md"
git -C "$TB" add -A; git -C "$TB" commit -qm work
record_gates cmapb
EB="$(mktemp)"
RCB="$(gate "$TB" 'git push -u origin HEAD' "$EB")"
[ "$RCB" = 0 ] && ! grep -q '\[advisory\] test-plan coverage' "$EB" \
  && ok "(b) all rows mapped -> no coverage advisory, exit 0" \
  || no "(b) expected exit 0 + no coverage advisory; got exit $RCB, stderr: $(cat "$EB")"

# (c) spec with NO test plan -> no warning (no new requirement, pass path unchanged)
TC="$(mktemp -d)"; mkrepo "$TC"
git -C "$TC" switch -qc feat/cmapc
printf '# Spec: x\nStatus: DRAFT\nLane: full\n' > "$TC/docs/specs/SPEC-001-cmapc.md"
git -C "$TC" add -A; git -C "$TC" commit -qm work
record_gates cmapc
EC="$(mktemp)"
RCC="$(gate "$TC" 'git push -u origin HEAD' "$EC")"
[ "$RCC" = 0 ] && ! grep -q '\[advisory\] test-plan coverage' "$EC" \
  && ok "(c) no test plan -> no coverage advisory, exit 0" \
  || no "(c) expected exit 0 + no coverage advisory; got exit $RCC, stderr: $(cat "$EC")"

# (d) partially mapped -> advisory names the unmapped rows, still not blocked
TD="$(mktemp -d)"; mkrepo "$TD"
git -C "$TD" switch -qc feat/cmapd
spec_with_plan "$TD/docs/specs/SPEC-001-cmapd.md"
printf 'NEGATIVE CONTROL\nVerdict: PASS\n\n## Test plan coverage\n| Row | Run / skip reason |\n|---|---|\n| 1 | R1 |\n' > "$TD/docs/verification/cmapd.md"
git -C "$TD" add -A; git -C "$TD" commit -qm work
record_gates cmapd
ED="$(mktemp)"
RCD="$(gate "$TD" 'git push -u origin HEAD' "$ED")"
[ "$RCD" = 0 ] && grep -q 'UNMAPPED: 2' "$ED" \
  && ok "(d) partial map -> advisory names unmapped row 2, exit 0" \
  || no "(d) expected exit 0 + UNMAPPED: 2 advisory; got exit $RCD, stderr: $(cat "$ED")"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

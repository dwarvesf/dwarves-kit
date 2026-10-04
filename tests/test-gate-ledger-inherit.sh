#!/usr/bin/env bash
# test-gate-ledger-inherit.sh -- `gate-ledger.sh inherit <rid> full --from <parent>` carries a
# validated spec's spec-level gates onto a task branch rid, and refuses, writing nothing, when
# the parent's ledger does not hold `ran` as the last state for every one of them.
#
# Isolation: every case runs under a fresh DWARVES_KIT_LOG_DIR with KIT_LEDGER_DIR unset, so
# reads and writes land in one temp root and the real machine corpus is never touched.
#
# Run: bash tests/test-gate-ledger-inherit.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }
ok() { if eval "$2"; then assert "$1" 0; else assert "$1 (out: ${OUT:-} err: ${ERR:-})" 1; fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

SEVEN="think design design-critique spec validate design-record test-plan"
LOGD=""; GLX="$GL"
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; GLX="$GL"; }
# Run the verb; stdout -> OUT, stderr -> ERR, exit -> RC.
run() {
  local e; e="$(_mk)/err"
  OUT="$(env -u KIT_LEDGER_DIR DWARVES_KIT_LOG_DIR="$LOGD" bash "$GLX" "$@" 2>"$e")"; RC=$?
  ERR="$(cat "$e")"
}
ledger_of() { cat "$LOGD/runs/$1.log" 2>/dev/null; }
gate_line() { printf '%s | GATE | %s | %s | %s\n' "$2" "$3" "$4" "$5" >> "$LOGD/runs/$1.log"; }   # rid ts phase state reason
# A parent whose seven spec-level phases all end in `ran`, timestamps ...:01Z to ...:07Z.
full_parent() { local i=1 ph; for ph in $SEVEN; do gate_line "$1" "2026-10-01T00:00:0${i}Z" "$ph" ran "fixture"; i=$((i+1)); done; }
# The same, with one phase left out.
parent_without() { local i=1 ph; for ph in $SEVEN; do [ "$ph" = "$2" ] || gate_line "$1" "2026-10-01T00:00:0${i}Z" "$ph" ran "fixture"; i=$((i+1)); done; }
# Child lines exactly as the verb writes them, seeded by hand so a mutated verb cannot shape its own fixture.
seed_child() { local i=1 ph; for ph in $SEVEN; do gate_line "$1" "2026-10-02T00:00:0${i}Z" "$ph" override "inherited from $2: $ph ran there at 2026-10-01T00:00:0${i}Z"; i=$((i+1)); done; }
n_gate() { ledger_of "$1" | grep -c '| GATE | ' || true; }

echo "=== gate-ledger inherit ==="

# AC-1: happy path, seven override lines with the exact built reason.
new_log; full_parent p
run inherit c full --from p
ok "AC-1 exits 0" '[ "$RC" -eq 0 ]'
ok "AC-1 writes exactly seven GATE lines" '[ "$(n_gate c)" -eq 7 ]'
ok "AC-1 every line is an override" '[ "$(ledger_of c | grep -c "| GATE | [a-z-]* | override | ")" -eq 7 ]'
ok "AC-1 reason is exact for think" 'ledger_of c | grep -qxE "[0-9T:Z-]+ \| GATE \| think \| override \| inherited from p: think ran there at 2026-10-01T00:00:01Z"'
ok "AC-1 reason is exact for test-plan" 'ledger_of c | grep -qxE "[0-9T:Z-]+ \| GATE \| test-plan \| override \| inherited from p: test-plan ran there at 2026-10-01T00:00:07Z"'
ok "AC-1 one stdout line per phase" '[ "$(printf "%s\n" "$OUT" | grep -c " inherited from p$")" -eq 7 ]'

# Ledger root: the verb's write and `show` read one file under DWARVES_KIT_LOG_DIR.
SHOW="$(env -u KIT_LEDGER_DIR DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" show c 2>/dev/null)"
ok "ROOT write and show read the same file" '[ -n "$SHOW" ] && [ "$SHOW" = "$(ledger_of c)" ]'

# AC-2: the per-branch gates stay open and are never written.
new_log; full_parent p; gate_line p "2026-10-01T00:00:09Z" build ran "parent build"
run inherit c full --from p
CHK="$(env -u KIT_LEDGER_DIR DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" check full c --kit-lanes 2>&1)"; CRC=$?
ok "AC-2 check full --kit-lanes exits 1" '[ "$CRC" -eq 1 ]'
for ph in build review docs ship reflect; do
  ok "AC-2 check lists $ph" 'printf "%s\n" "$CHK" | grep -q "^MISSING-GATE: $ph "'
done
ok "AC-2 check lists none of the seven" '! printf "%s\n" "$CHK" | grep -qE "^MISSING-GATE: (think|design|design-critique|spec|validate|design-record|test-plan) "'
ok "AC-2 child holds no per-branch line" '! ledger_of c | grep -qE "\| GATE \| (build|review|docs|ship|reflect) \|"'

# AC-3: a missing parent gate refuses and writes nothing (first and last phase in order).
for miss in think test-plan; do
  new_log; parent_without p "$miss"
  run inherit c full --from p
  ok "AC-3 ($miss missing) exits 1" '[ "$RC" -eq 1 ]'
  ok "AC-3 ($miss missing) names it" 'printf "%s\n" "$ERR" | grep -q "  $miss: no GATE line in the parent"'
  ok "AC-3 ($miss missing) child ledger stays absent" '[ ! -e "$LOGD/runs/c.log" ]'
done

# AC-4: a hand-overridden parent gate refuses.
new_log; full_parent p; gate_line p "2026-10-01T00:00:20Z" design override "operator waived it"
run inherit c full --from p
ok "AC-4 exits 1" '[ "$RC" -eq 1 ]'
ok "AC-4 names design as overridden" 'printf "%s\n" "$ERR" | grep -q "  design: last state override, not ran"'
ok "AC-4 wording says last state ran" 'printf "%s\n" "$ERR" | grep -q "does not hold last state ran"'
ok "AC-4 nothing written" '[ ! -e "$LOGD/runs/c.log" ]'

# AC-5: the last GATE line wins.
new_log; full_parent p; gate_line p "2026-10-01T00:00:30Z" validate skipped "NEEDS REVISION round 2"
run inherit c full --from p
ok "AC-5 ran then skipped exits 1" '[ "$RC" -eq 1 ]'
ok "AC-5 names validate" 'printf "%s\n" "$ERR" | grep -q "  validate: last state skipped, not ran"'
ok "AC-5 nothing written" '[ ! -e "$LOGD/runs/c.log" ]'
new_log; gate_line p "2026-10-01T00:00:00Z" validate skipped "NEEDS REVISION round 1"; full_parent p
run inherit c full --from p
ok "AC-5 reverse (skipped rounds then ran) exits 0" '[ "$RC" -eq 0 ] && [ "$(n_gate c)" -eq 7 ]'

# AC-6: a task-branch parent refuses and names the grandparent, sanitized.
new_log; seed_child mid g
run inherit c full --from mid
ok "AC-6 exits 1" '[ "$RC" -eq 1 ]'
ok "AC-6 names g to inherit from directly" 'printf "%s\n" "$ERR" | grep -q "the parent inherited it from '"'"'g'"'"'; inherit from '"'"'g'"'"' directly"'
ok "AC-6 nothing written" '[ ! -e "$LOGD/runs/c.log" ]'
new_log; full_parent mid; gate_line mid "2026-10-01T00:00:40Z" spec override 'inherited from g$(id)/x: spec ran there at 2026-10-01T00:00:04Z'
run inherit c full --from mid
ok "AC-6 grandparent name passes through runid" 'printf "%s\n" "$ERR" | grep -q "inherited it from '"'"'gid-x'"'"'" && ! printf "%s\n" "$ERR" | grep -qF "\$("'

# Timestamp shape: a ran line with a malformed ts refuses.
new_log; full_parent p; gate_line p "yesterday" think ran "bad clock"
run inherit c full --from p
ok "TS malformed timestamp exits 1" '[ "$RC" -eq 1 ] && printf "%s\n" "$ERR" | grep -q "  think: last state ran, but its timestamp is malformed"'

# AC-7: a reused slug. Both parents fully pass, so any refusal comes from the conflict check.
new_log; full_parent x; full_parent y; seed_child c x; BEFORE="$(ledger_of c)"
run inherit c full --from y
ok "AC-7 x-vs-y exits 65" '[ "$RC" -eq 65 ]'
ok "AC-7 x-vs-y prints the conflict line" 'printf "%s\n" "$ERR" | grep -q "^inherit: child '"'"'c'"'"' already inherited think from another parent"'
ok "AC-7 x-vs-y writes nothing" '[ "$(ledger_of c)" = "$BEFORE" ]'
run inherit c full --from x
ok "AC-7 same parent exits 0" '[ "$RC" -eq 0 ]'
ok "AC-7 same parent prints already per phase" '[ "$(printf "%s\n" "$OUT" | grep -c " already inherited from x$")" -eq 7 ]'
ok "AC-7 same parent writes no line" '[ "$(ledger_of c)" = "$BEFORE" ]'
for pair in "watch-hub-spec watch-hub" "watch-hub watch-hub-spec"; do
  set -- $pair
  new_log; full_parent watch-hub; full_parent watch-hub-spec; seed_child c "$1"; BEFORE="$(ledger_of c)"
  run inherit c full --from "$2"
  ok "AC-7 child from $1, call $2: exits 65" '[ "$RC" -eq 65 ]'
  ok "AC-7 child from $1, call $2: conflict line" 'printf "%s\n" "$ERR" | grep -q "already inherited think from another parent"'
  ok "AC-7 child from $1, call $2: writes nothing" '[ "$(ledger_of c)" = "$BEFORE" ]'
done

# AC-8: a write fails partway, the code propagates, a re-run finishes.
new_log; full_parent p
gate_line c "2026-10-02T00:00:00Z" build override "inherited from p: test-plan ran there at 2026-10-01T00:00:07Z"
run inherit c full --from p
ok "AC-8 exits 65" '[ "$RC" -eq 65 ]'
ok "AC-8 prints the override() refusal line" 'printf "%s\n" "$ERR" | grep -q "^inherit: override() refused the test-plan write (exit 65)"'
ok "AC-8 six phases written before the stop" '[ "$(ledger_of c | grep -cE "\| GATE \| (think|design|design-critique|spec|validate|design-record) \| override \| inherited from p: ")" -eq 6 ]'
ok "AC-8 test-plan not written" '! ledger_of c | grep -q "| GATE | test-plan |"'
grep -v '| GATE | build |' "$LOGD/runs/c.log" > "$LOGD/runs/c.tmp"; mv -f "$LOGD/runs/c.tmp" "$LOGD/runs/c.log"
run inherit c full --from p
ok "AC-8 re-run exits 0" '[ "$RC" -eq 0 ]'
ok "AC-8 re-run skips six as already" '[ "$(printf "%s\n" "$OUT" | grep -c " already inherited from p$")" -eq 6 ]'
ok "AC-8 re-run writes test-plan" 'printf "%s\n" "$OUT" | grep -qx "test-plan inherited from p" && [ "$(n_gate c)" -eq 7 ]'

# AC-9: lane guard, and a project overlay does not shrink the set.
for ln in normal bug backfill; do
  new_log; full_parent p
  run inherit c "$ln" --from p
  ok "AC-9 $ln exits 64 with the v1 message" '[ "$RC" -eq 64 ] && printf "%s\n" "$ERR" | grep -q "full lane only"'
  ok "AC-9 $ln writes nothing" '[ ! -e "$LOGD/runs/c.log" ]'
done
PROJ="$(_mk)/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q 2>/dev/null
printf '[lane.full]\nphases = ["think", "design", "ui-design", "spec", "validate", "design-record", "test-plan", "build", "review", "docs", "ship", "reflect"]\nlight  = ["ui-design"]\n' > "$PROJ/.kit.toml"
git -C "$PROJ" add .kit.toml && git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm overlay
REQ="$(cd "$PROJ" && KIT_PROJECT_ROOT="$PROJ" bash "$GL" required full 2>/dev/null)"
ok "AC-9 overlay is live (required full drops design-critique)" '! printf "%s\n" "$REQ" | grep -qx design-critique && printf "%s\n" "$REQ" | grep -qx design'
new_log; full_parent p
OUT="$(cd "$PROJ" && env -u KIT_LEDGER_DIR KIT_PROJECT_ROOT="$PROJ" DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" inherit c full --from p 2>&1)"; RC=$?
ok "AC-9 overlay still gets seven lines" '[ "$RC" -eq 0 ] && [ "$(n_gate c)" -eq 7 ] && ledger_of c | grep -q "| GATE | design-critique | override |"'

# AC-10: usage and self-parent.
new_log; full_parent p
run inherit c full p;                 ok "AC-10 no --from exits 64" '[ "$RC" -eq 64 ]'
run inherit c full --from;            ok "AC-10 --from with no value exits 64" '[ "$RC" -eq 64 ]'
run inherit c full --from p extra;    ok "AC-10 extra argument exits 64" '[ "$RC" -eq 64 ]'
run inherit c full --frm p;           ok "AC-10 misspelt flag exits 64" '[ "$RC" -eq 64 ]'
run inherit c full --from c;          ok "AC-10 self-parent exits 64" '[ "$RC" -eq 64 ]'
run inherit feat/a-b full --from feat-a-b; ok "AC-10 slash self-parent exits 64" '[ "$RC" -eq 64 ] && printf "%s\n" "$ERR" | grep -q "is the child rid itself"'
run inherit '@@@' full --from p;      ok "AC-10 empty-normalizing rid exits 64" '[ "$RC" -eq 64 ]'
ok "AC-10 nothing written by any usage refusal" '[ "$(ls "$LOGD/runs")" = "p.log" ]'
run inherit c full --from nosuch
ok "NOLEDGER exits 1 and says host-local" '[ "$RC" -eq 1 ] && printf "%s\n" "$ERR" | grep -q "host-local"'
run frobnicate
ok "USAGE string lists inherit" 'printf "%s\n" "$ERR" | grep -q "|inherit|"'

# AC-11: hermetic positive. inherit + the per-branch gates leaves the kit-lanes floor clean.
new_log; full_parent p
run inherit c full --from p
for ph in build review docs; do run record c "$ph" ran "per-branch $ph"; done
run override c ship "reviewed task branch, pushed by the lead"
run override c reflect "reflect runs once at session close"
env -u KIT_LEDGER_DIR DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" check full c --kit-lanes >/dev/null 2>&1; CRC=$?
ok "AC-11 check full --kit-lanes exits 0" '[ "$CRC" -eq 0 ]'

# FAILCLOSED: a broken or spec-gate-free kit-root lane table refuses with exit 1.
for variant in malformed empty; do
  KC="$(_mk)/kit"; mkdir -p "$KC/lib"
  for sub in gate telemetry ledger config spec; do cp -R "$KIT_DIR/lib/$sub" "$KC/lib/"; done
  if [ "$variant" = malformed ]; then
    sed -E 's/^(phases = \["think", "design", "design-critique".*)$/phases = "not-an-array"/' "$KIT_DIR/kit.toml" > "$KC/kit.toml"
  else
    sed -E 's/^(phases = \["think", "design", "design-critique".*)$/phases = ["build", "review", "docs", "ship", "reflect"]/' "$KIT_DIR/kit.toml" > "$KC/kit.toml"
  fi
  new_log; full_parent p; GLX="$KC/lib/gate/gate-ledger.sh"
  run inherit c full --from p
  ok "FAILCLOSED ($variant lane table) exits 1" '[ "$RC" -eq 1 ] && printf "%s\n" "$ERR" | grep -q "fail-closed"'
  ok "FAILCLOSED ($variant lane table) writes nothing" '[ ! -e "$LOGD/runs/c.log" ]'
done

echo ""
echo "inherit: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]

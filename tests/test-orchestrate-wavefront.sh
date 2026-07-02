#!/usr/bin/env bash
# test-orchestrate-wavefront.sh
# Pins _ready_set (SPEC-106 TASK-001, DAG-wavefront phase 1). The ready set = every sub-goal that
# is unchecked AND whose `depends SG-NN` tokens are all checked, emitted in ROADMAP order as
# "id<TAB>policy" (the _subgoals shape minus the checked column). _ready_set is a PURE read helper:
# it changes no scheduling (nothing calls it into the run loop yet). The file is SOURCED (not run
# via `bash orchestrate.sh <cmd>`) so the internal function is directly callable; orchestrate.sh's
# `main "$@"` guard (BASH_SOURCE == $0) keeps main from firing on source. Invariants asserted:
#   - linear/no-deps ROADMAP -> ready set is ALL unchecked in order; first line == _next (size-1
#     superset invariant: _next is `_ready_set | head -1`).
#   - diamond (SG-02,SG-03 depends SG-01; SG-04 depends SG-02 SG-03) -> the wave opens SG-01 alone,
#     then {SG-02,SG-03}, then SG-04, cycle by cycle.
#   - partially-checked -> checked boxes drop out; a dep on an unchecked box still blocks.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/orchestrate.sh
source "$KIT/lib/orchestrate.sh"   # guard in orchestrate.sh keeps main from running when sourced

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Assert _ready_set's full output for a roadmap equals a printf-built expected block.
# want() args after the roadmap are the expected "id<TAB>policy" lines (already TAB-joined).
assert_ready() {  # label roadmap expected
  local label="$1" roadmap="$2" expected="$3" got
  got=$(_ready_set "$roadmap")
  [ "$got" = "$expected" ] && pass "$label" || { fail "$label"; printf 'got:\n%s\nwant:\n%s\n' "$got" "$expected"; }
}

# Assert the size-1 superset invariant: `_ready_set | head -1` == `_next`.
assert_next_invariant() {  # label roadmap
  local label="$1" roadmap="$2" head1 nxt
  head1=$(_ready_set "$roadmap" | head -1)
  nxt=$(_next "$roadmap")
  [ "$head1" = "$nxt" ] && pass "$label" || { fail "$label"; printf 'head-1: %q  _next: %q\n' "$head1" "$nxt"; }
}

# Flip a sub-goal's box to [x] in place (mimics a grounded completion between cycles).
flip() { local rm="$1" id="$2"; awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$rm" > "$rm.t" && mv "$rm.t" "$rm"; }

# ============================ FIXTURE A: linear no-deps chain ============================
A="$TMP/roadmap-linear.md"
cat > "$A" <<'EOF'
# Mega-goal: linear
## Sub-goals
- [ ] SG-01 first , auto , PR #__
- [ ] SG-02 second , auto , PR #__
- [ ] SG-03 third , gate , PR #__
EOF
# Cycle 1: no deps anywhere -> the ready set is EVERY unchecked sub-goal, in ROADMAP order.
assert_ready "linear cycle1: all unchecked ready in order" "$A" \
  "$(printf 'SG-01\tauto\nSG-02\tauto\nSG-03\tgate')"
assert_next_invariant "linear cycle1: head-1 == _next (SG-01)" "$A"
# Cycle 2: after SG-01 completes, the rest remain ready (still no deps).
flip "$A" SG-01
assert_ready "linear cycle2: SG-01 drops, rest ready" "$A" \
  "$(printf 'SG-02\tauto\nSG-03\tgate')"
assert_next_invariant "linear cycle2: head-1 == _next (SG-02)" "$A"

# ============================ FIXTURE B: diamond ============================
B="$TMP/roadmap-diamond.md"
cat > "$B" <<'EOF'
# Mega-goal: diamond
## Sub-goals
- [ ] SG-01 root , auto , PR #__
- [ ] SG-02 left , auto , PR #__ , depends SG-01
- [ ] SG-03 right , auto , PR #__ , depends SG-01
- [ ] SG-04 join , gate , PR #__ , depends SG-02 SG-03
EOF
# Cycle 1: only SG-01 is unblocked; SG-02/03 wait on SG-01, SG-04 waits on SG-02+SG-03.
assert_ready "diamond cycle1: only the root SG-01 is ready" "$B" \
  "$(printf 'SG-01\tauto')"
assert_next_invariant "diamond cycle1: head-1 == _next (SG-01)" "$B"
# Cycle 2: SG-01 done -> both mid-branches open as a wave; SG-04 still blocked (SG-02/03 unchecked).
flip "$B" SG-01
assert_ready "diamond cycle2: SG-02 + SG-03 both ready, SG-04 blocked" "$B" \
  "$(printf 'SG-02\tauto\nSG-03\tauto')"
assert_next_invariant "diamond cycle2: head-1 == _next (SG-02)" "$B"
# Cycle 3: SG-02 done, SG-03 not -> SG-04 still blocked (needs BOTH parents).
flip "$B" SG-02
assert_ready "diamond cycle3: SG-03 ready, SG-04 still blocked on SG-03" "$B" \
  "$(printf 'SG-03\tauto')"
# Cycle 4: both parents done -> SG-04 (the join) opens.
flip "$B" SG-03
assert_ready "diamond cycle4: join SG-04 ready" "$B" \
  "$(printf 'SG-04\tgate')"
assert_next_invariant "diamond cycle4: head-1 == _next (SG-04)" "$B"

# ============================ FIXTURE C: partially checked ============================
C="$TMP/roadmap-partial.md"
cat > "$C" <<'EOF'
# Mega-goal: partial
## Sub-goals
- [x] SG-01 done , auto , PR #1
- [ ] SG-02 ready , auto , PR #__
- [x] SG-03 done , auto , PR #2
- [ ] SG-04 blocked , gate , PR #__ , depends SG-02
EOF
# Checked boxes (SG-01, SG-03) drop out; SG-02 has no deps -> ready; SG-04 depends on the still-
# unchecked SG-02 -> blocked. So the ready set is exactly SG-02.
assert_ready "partial: only unchecked+unblocked SG-02 is ready" "$C" \
  "$(printf 'SG-02\tauto')"
assert_next_invariant "partial: head-1 == _next (SG-02)" "$C"
# After SG-02 completes, its dependent SG-04 opens.
flip "$C" SG-02
assert_ready "partial: SG-02 done -> dependent SG-04 opens" "$C" \
  "$(printf 'SG-04\tgate')"

# ============================ EDGE: all checked -> empty ready set == empty _next ============================
Z="$TMP/roadmap-done.md"
cat > "$Z" <<'EOF'
# Mega-goal: done
## Sub-goals
- [x] SG-01 first , auto , PR #1
- [x] SG-02 second , auto , PR #2
EOF
got=$(_ready_set "$Z")
[ -z "$got" ] && pass "all-checked: ready set empty" || { fail "all-checked: ready set not empty"; printf 'got: %q\n' "$got"; }
assert_next_invariant "all-checked: head-1 == _next (both empty)" "$Z"

# ============================ TASK-002: mkdir-lock + cmd_flip ============================
# The CLI is exercised out-of-process (real distinct PIDs) for the concurrency + stale tests;
# `_lock` is called directly (sourced) for the reclaim probe. ORCH = the script under test.
ORCH="$KIT/lib/orchestrate.sh"

# ---- (a) cmd_flip flips the correct box, is idempotent, rejects an unknown id ----
MG="$TMP/mg-flip"; mkdir -p "$MG"
cat > "$MG/ROADMAP.md" <<'EOF'
# Mega-goal: flip
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
- [ ] SG-03 gamma , gate , PR #__
EOF
cmd_flip "$MG" SG-02 >/dev/null 2>&1
after=$(_sg_line "$MG/ROADMAP.md" SG-02)
case "$after" in '- [x] SG-02'*) pass "flip: SG-02 box checked" ;; *) fail "flip: SG-02 not checked (got: $after)" ;; esac
_sg_line "$MG/ROADMAP.md" SG-01 | grep -q '^- \[ \] SG-01' && pass "flip: SG-01 untouched" || fail "flip: SG-01 mutated"
_sg_line "$MG/ROADMAP.md" SG-03 | grep -q '^- \[ \] SG-03' && pass "flip: SG-03 untouched" || fail "flip: SG-03 mutated"
# idempotent: flipping an already-checked box is a no-op success
cmd_flip "$MG" SG-02 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && pass "flip: idempotent re-flip returns 0" || fail "flip: idempotent rc=$rc"
after2=$(_sg_line "$MG/ROADMAP.md" SG-02)
[ "$after2" = "$after" ] && pass "flip: idempotent re-flip leaves the line byte-identical" || fail "flip: re-flip changed the line"
# ROADMAP still well-formed: exactly 3 sub-goal lines, no torn/duplicated lines
lc=$(grep -cE '^- \[[ xX]\] SG-' "$MG/ROADMAP.md")
[ "$lc" = 3 ] && pass "flip: ROADMAP keeps its 3 sub-goal lines" || fail "flip: sub-goal line count = $lc (want 3)"
# unknown id -> nonzero + no mutation
cp "$MG/ROADMAP.md" "$MG/ROADMAP.before"
cmd_flip "$MG" SG-99 >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && pass "flip: unknown id returns nonzero" || fail "flip: unknown id returned 0"
cmp -s "$MG/ROADMAP.md" "$MG/ROADMAP.before" && pass "flip: unknown id leaves ROADMAP unchanged" || fail "flip: unknown id mutated ROADMAP"

# ---- (b) N (>=5) parallel flips on DISTINCT boxes all land, ROADMAP well-formed ----
# Each flip rewrites the WHOLE file; without the lock, concurrent rewrites would lose updates
# (torn/lost lines). Run them as real separate processes to get distinct holder PIDs.
MGP="$TMP/mg-par"; mkdir -p "$MGP"
{
  printf '# Mega-goal: parallel\n## Sub-goals\n'
  for n in 01 02 03 04 05 06; do printf -- '- [ ] SG-%s box%s , auto , PR #__\n' "$n" "$n"; done
} > "$MGP/ROADMAP.md"
for n in 01 02 03 04 05 06; do
  bash "$ORCH" flip "$MGP" "SG-$n" >/dev/null 2>&1 &
done
wait
allchecked=1
for n in 01 02 03 04 05 06; do
  _sg_line "$MGP/ROADMAP.md" "SG-$n" | grep -q "^- \[x\] SG-$n " || allchecked=0
done
[ "$allchecked" = 1 ] && pass "parallel flip: all 6 distinct boxes checked" || fail "parallel flip: some boxes lost"
plc=$(grep -cE '^- \[[ xX]\] SG-' "$MGP/ROADMAP.md")
[ "$plc" = 6 ] && pass "parallel flip: ROADMAP well-formed (6 sub-goal lines, none torn/lost)" || fail "parallel flip: line count = $plc (want 6)"
# no leftover temp files leaked into the mega-goal dir
tmpleft=$(ls "$MGP"/.roadmap.flip.* 2>/dev/null | wc -l | tr -d ' ')
[ "$tmpleft" = 0 ] && pass "parallel flip: no temp files leaked" || fail "parallel flip: $tmpleft temp files leaked"

# ---- (c) stale-lock reclaim: a lock held by a DEAD pid is reclaimed (no infinite hang) ----
MGS="$TMP/mg-stale"; mkdir -p "$MGS/.orchestrate"
LOCK="$MGS/.orchestrate/flip.lock"
mkdir "$LOCK"
# a guaranteed-dead PID: spawn a trivial process, reap it, reuse its (now-free) PID number
sh -c 'exit 0' & deadpid=$!; wait "$deadpid" 2>/dev/null
printf '%s\n' "$deadpid" > "$LOCK/pid"
kill -0 "$deadpid" 2>/dev/null && fail "stale reclaim: test setup pid still alive (retry)" || pass "stale reclaim: dead holder pid confirmed dead"
# attempt the acquire in the background; poll for success with a hard timeout so a hang = FAIL
: > "$MGS/acquired"
( _lock "$LOCK" && printf 'ok\n' > "$MGS/acquired" ) &
lpid=$!
ok=0
for _i in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$MGS/acquired" ] && { ok=1; break; }
  sleep 0.5
done
kill "$lpid" 2>/dev/null
if [ "$ok" = 1 ]; then
  pass "stale reclaim: _lock reclaimed a dead-holder lock (did not hang)"
else
  fail "stale reclaim: _lock hung on a dead-holder lock (never acquired)"
fi

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }

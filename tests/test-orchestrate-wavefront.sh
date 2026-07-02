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

# ============================ TASK-003: _wave_gate greedy admission ============================
# _wave_gate <megadir> <roadmap> reads the ready set, then admits ready sub-goals GREEDILY in
# ROADMAP order: a candidate is admitted iff (a) its goal file declares its OWN `## Touches` section
# AND (b) it proves disjoint (dispatch-gate.sh gate_disjoint) against EVERY already-admitted member;
# it stops admitting at WAVE_CAP (default 1). Output: one `run<TAB>id` / `defer<TAB>id` line per ready
# sub-goal, in ROADMAP order. Self-Touches is REQUIRED because gate_disjoint admits the first member
# vacuously (empty admitted set), so a Touches-less sub-goal would otherwise be wrongly admitted.

# Build a mega-goal dir with a ROADMAP + per-sub-goal goal files carrying (or lacking) ## Touches.
# make_goal <megadir> <id> [touches-glob]: write goals/<NN>-<id>.md; omit the glob for a Touches-less
# goal file (the Option-B opt-out).
make_goal() {  # megadir id [glob]
  local mg="$1" id="$2" glob="${3:-}"
  mkdir -p "$mg/goals"
  {
    printf '# %s: sub-goal\n' "$id"
    printf '**Branch:** feat/%s\n' "$(printf '%s' "$id" | tr 'A-Z' 'a-z')"
    if [ -n "$glob" ]; then printf '\n## Touches\n- %s\n' "$glob"; fi
  } > "$mg/goals/${id#SG-}-${id}.md"
}

# assert_gate <label> <cap> <megadir> <roadmap> <expected>: run WAVE_CAP=cap _wave_gate and compare.
# The command substitution is a subshell, so the inline WAVE_CAP assignment never leaks to the parent.
assert_gate() {  # label cap megadir roadmap expected
  local label="$1" cap="$2" mg="$3" rm="$4" expected="$5" got
  got=$(WAVE_CAP="$cap" _wave_gate "$mg" "$rm")
  [ "$got" = "$expected" ] && pass "$label" || { fail "$label"; printf 'got:\n%s\nwant:\n%s\n' "$got" "$expected"; }
}

# ---- (a) Touches-DECLARING + DISJOINT pair, WAVE_CAP=2 -> both run ----
GA="$TMP/mg-gate-a"; mkdir -p "$GA"
cat > "$GA/ROADMAP.md" <<'EOF'
# Mega-goal: gate-a
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
make_goal "$GA" SG-01 "lib/wave-a/**"
make_goal "$GA" SG-02 "lib/wave-b/**"
assert_gate "wave_gate a: disjoint declaring pair (cap 2) -> both run" 2 "$GA" "$GA/ROADMAP.md" \
  "$(printf 'run\tSG-01\nrun\tSG-02')"

# ---- (b) Touches-DECLARING but OVERLAPPING pair -> first run, second defer (negative control) ----
GB="$TMP/mg-gate-b"; mkdir -p "$GB"
cat > "$GB/ROADMAP.md" <<'EOF'
# Mega-goal: gate-b
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
make_goal "$GB" SG-01 "lib/shared/**"
make_goal "$GB" SG-02 "lib/shared/**"
assert_gate "wave_gate b: overlapping declaring pair (cap 2) -> SG-01 run, SG-02 defer" 2 "$GB" "$GB/ROADMAP.md" \
  "$(printf 'run\tSG-01\ndefer\tSG-02')"

# ---- (c) Touches-LESS ready set -> ALL defer (the Option-B opt-in gate) ----
GC="$TMP/mg-gate-c"; mkdir -p "$GC"
cat > "$GC/ROADMAP.md" <<'EOF'
# Mega-goal: gate-c
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
make_goal "$GC" SG-01   # no ## Touches
make_goal "$GC" SG-02   # no ## Touches
assert_gate "wave_gate c: Touches-less ready set (cap 2) -> all defer" 2 "$GC" "$GC/ROADMAP.md" \
  "$(printf 'defer\tSG-01\ndefer\tSG-02')"

# ---- (d) WAVE_CAP=1 on the disjoint pair -> at most one run (serial default) ----
assert_gate "wave_gate d: disjoint pair at cap 1 -> only SG-01 runs" 1 "$GA" "$GA/ROADMAP.md" \
  "$(printf 'run\tSG-01\ndefer\tSG-02')"

# ---- (e) mixed: a Touches-less FIRST candidate defers, a declaring second still admits ----
# Proves self-Touches is checked per-candidate (not "the first ready one wins"): SG-01 has no Touches
# so it defers; SG-02 declares Touches and, being the first ADMITTED member, admits vacuously.
GE="$TMP/mg-gate-e"; mkdir -p "$GE"
cat > "$GE/ROADMAP.md" <<'EOF'
# Mega-goal: gate-e
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
make_goal "$GE" SG-01              # Touches-less -> defer
make_goal "$GE" SG-02 "lib/only/**"
assert_gate "wave_gate e: Touches-less first defers, declaring second admits" 2 "$GE" "$GE/ROADMAP.md" \
  "$(printf 'defer\tSG-01\nrun\tSG-02')"

# ---- (f) default WAVE_CAP (unset) behaves as cap 1 ----
got=$(unset WAVE_CAP; _wave_gate "$GA" "$GA/ROADMAP.md")
[ "$got" = "$(printf 'run\tSG-01\ndefer\tSG-02')" ] && pass "wave_gate f: default cap (unset) == 1 (only SG-01 runs)" \
  || { fail "wave_gate f: default cap != 1"; printf 'got:\n%s\n' "$got"; }

# ============================ TASK-004a: _wave_run concurrent spawn/reap ============================
# _wave_run <megadir> <roadmap> takes the admitted `run` set (via _wave_gate), stands up a worktree
# per admitted sub-goal at <repo>/.claude/worktrees/<id>, backgrounds a MOCK session in each, tracks
# a pid->id reap map, polls `kill -0`, and does the grounded box-flip check per sub-goal. A sibling
# nonzero-exit lets healthy siblings DRAIN, then the wave returns nonzero. All tests use a real
# throwaway `git init` repo so worktree creation is genuinely exercised, and a MOCK CLAUDE_CMD (no
# real claude, no network).

# Stand up a throwaway git repo (so _wave_run creates REAL worktrees). The mega-goal dir lives at
# <repo>/mega; _wave_run derives the repo root from it via `git rev-parse --show-toplevel`.
mk_git_mega() {  # repo-root
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
}

# ---- (g) CONCURRENCY PROOF via mock-barrier fifo (REQUIRED) ----
# Two admitted, disjoint sub-goals. Each mock opens its OWN fifo read-write (a non-blocking open),
# writes a token to the SIBLING's fifo, then `read -t` its own fifo. That read only unblocks once the
# sibling has WRITTEN, which requires the sibling to be ALIVE at that instant -> proven temporal
# overlap. A SERIAL impl runs A fully before B; A's `read -t` finds no writer and TIMES OUT -> A
# exits nonzero WITHOUT flipping its box -> the "both boxes flipped + rc 0" assertion FAILS. So a
# serial implementation cannot pass this test.
WCR="$TMP/wave-cc-repo"
mk_git_mega "$WCR"
WCM="$WCR/mega"; mkdir -p "$WCM"
cat > "$WCM/ROADMAP.md" <<'EOF'
# Mega-goal: wave-concurrent
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WCM/POINTER_PROMPT.md"
make_goal "$WCM" SG-01 "lib/wave-a/**"
make_goal "$WCM" SG-02 "lib/wave-b/**"

FIFODIR="$TMP/fifos-cc"; mkdir -p "$FIFODIR"
mkfifo "$FIFODIR/SG-01.fifo" "$FIFODIR/SG-02.fifo"

# The single mock serves BOTH sub-goals (one CLAUDE_CMD, different prompt/id). It records a .running
# marker on start and clears it on EXIT, so a leftover marker == an orphaned/killed-and-not-reaped
# process.
cat > "$TMP/claude-barrier" <<'MOCK'
#!/usr/bin/env bash
# env: FIFODIR, WAVE_MOCK_IDS, ORCH, MEGADIR, BARRIER_T, RUNDIR
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
: > "$RUNDIR/$id.running"
trap 'rm -f "$RUNDIR/$id.running"' EXIT
IN="$FIFODIR/$id.fifo"; OUT=""
for x in $WAVE_MOCK_IDS; do [ "$x" != "$id" ] && OUT="$FIFODIR/$x.fifo"; done
exec 3<>"$IN"; exec 4<>"$OUT"       # RDWR opens: non-blocking, so a lone process does not deadlock
printf 'r\n' >&4                    # signal the sibling
if read -t "${BARRIER_T:-4}" _tok <&3; then
  # Sibling proven concurrently alive -> flip our box in the SHARED roadmap. Two wave sessions flip
  # the SAME file at once, so this MUST go through the locked `orchestrate.sh flip` CLI (DEC-008),
  # not a raw sed/awk+mv (which would race and lose one flip). This mirrors the real session contract.
  bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
  exit 0
fi
exit 7                              # timed out: sibling never overlapped (serial) -> do NOT flip
MOCK
chmod +x "$TMP/claude-barrier"

RUNDIR_CC="$TMP/run-cc"; mkdir -p "$RUNDIR_CC"
wrc=0
( export FIFODIR="$FIFODIR" WAVE_MOCK_IDS="SG-01 SG-02" ORCH="$ORCH" MEGADIR="$WCM" \
    RUNDIR="$RUNDIR_CC" BARRIER_T=4 CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-barrier"
  _wave_run "$WCM" "$WCM/ROADMAP.md" ) > "$TMP/cc.out" 2>&1 || wrc=$?

cc_b1=$(_sg_line "$WCM/ROADMAP.md" SG-01); cc_b2=$(_sg_line "$WCM/ROADMAP.md" SG-02)
cc_ok=1
[ "$wrc" = 0 ] || cc_ok=0
case "$cc_b1" in '- [x] SG-01'*) ;; *) cc_ok=0 ;; esac
case "$cc_b2" in '- [x] SG-02'*) ;; *) cc_ok=0 ;; esac
if [ "$cc_ok" = 1 ]; then
  pass "wave_run g: concurrency PROVEN via mock-barrier (both boxes flipped, rc 0)"
else
  fail "wave_run g: concurrency NOT proven (rc=$wrc b1='$cc_b1' b2='$cc_b2')"; cat "$TMP/cc.out"
fi
cc_left=$(ls "$RUNDIR_CC"/*.running 2>/dev/null | wc -l | tr -d ' ')
[ "$cc_left" = 0 ] && pass "wave_run g: no orphaned mock processes remain" || fail "wave_run g: $cc_left mock(s) still running"

# ---- (h) SIBLING-FAILURE DRAIN ----
# Two admitted sub-goals; the doomed one exits nonzero FAST without flipping, the healthy one sleeps
# briefly (so it is provably still in-flight when the doomed sibling has already died) then flips +
# exits 0. Assert: the healthy sibling still completed (drained, not killed), the doomed box stayed
# unflipped, _wave_run returned nonzero, and no mock was left orphaned.
WFR="$TMP/wave-fail-repo"
mk_git_mega "$WFR"
WFM="$WFR/mega"; mkdir -p "$WFM"
cat > "$WFM/ROADMAP.md" <<'EOF'
# Mega-goal: wave-fail
## Sub-goals
- [ ] SG-01 healthy , auto , PR #__
- [ ] SG-02 doomed , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WFM/POINTER_PROMPT.md"
make_goal "$WFM" SG-01 "lib/heal/**"
make_goal "$WFM" SG-02 "lib/doom/**"

cat > "$TMP/claude-sibfail" <<'MOCK'
#!/usr/bin/env bash
# env: WAVE_FAIL_ID, ORCH, MEGADIR, RUNDIR
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
: > "$RUNDIR/$id.running"
trap 'rm -f "$RUNDIR/$id.running"' EXIT
if [ "$id" = "$WAVE_FAIL_ID" ]; then
  exit 5                            # doomed: dies fast, box left unflipped
fi
sleep 1                            # healthy: still working when the doomed sibling has already died
bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1   # locked flip via the CLI (real session contract)
exit 0
MOCK
chmod +x "$TMP/claude-sibfail"

RUNDIR_SF="$TMP/run-sf"; mkdir -p "$RUNDIR_SF"
frc=0
( export WAVE_FAIL_ID=SG-02 ORCH="$ORCH" MEGADIR="$WFM" RUNDIR="$RUNDIR_SF" \
    CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-sibfail"
  _wave_run "$WFM" "$WFM/ROADMAP.md" ) > "$TMP/sf.out" 2>&1 || frc=$?

sf_h=$(_sg_line "$WFM/ROADMAP.md" SG-01)
case "$sf_h" in '- [x] SG-01'*) pass "wave_run h: healthy sibling drained to completion (box flipped, not killed)" ;; *) fail "wave_run h: healthy sibling did NOT complete (got '$sf_h')" ;; esac
sf_d=$(_sg_line "$WFM/ROADMAP.md" SG-02)
case "$sf_d" in '- [ ] SG-02'*) pass "wave_run h: doomed sub-goal box stayed unflipped" ;; *) fail "wave_run h: doomed box unexpectedly flipped (got '$sf_d')" ;; esac
[ "$frc" != 0 ] && pass "wave_run h: wave returns nonzero after a sibling failure" || fail "wave_run h: wave returned 0 despite a sibling failure"
sf_left=$(ls "$RUNDIR_SF"/*.running 2>/dev/null | wc -l | tr -d ' ')
[ "$sf_left" = 0 ] && pass "wave_run h: no orphaned mock processes after drain" || fail "wave_run h: $sf_left mock(s) still running"

# ---- (i) idempotent resume: an already-checked box in the admitted set is skipped, not re-run ----
WIR="$TMP/wave-idem-repo"
mk_git_mega "$WIR"
WIM="$WIR/mega"; mkdir -p "$WIM"
cat > "$WIM/ROADMAP.md" <<'EOF'
# Mega-goal: wave-idem
## Sub-goals
- [x] SG-01 already done , auto , PR #1
EOF
echo "POINTER: resume from ROADMAP" > "$WIM/POINTER_PROMPT.md"
make_goal "$WIM" SG-01 "lib/idem/**"
# a mock that would FAIL loudly if ever invoked on a checked box
cat > "$TMP/claude-nope" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
: > "$RUNDIR/RAN"
exit 9
MOCK
chmod +x "$TMP/claude-nope"
RUNDIR_ID="$TMP/run-idem"; mkdir -p "$RUNDIR_ID"
irc=0
( export RUNDIR="$RUNDIR_ID" CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-nope"
  _wave_run "$WIM" "$WIM/ROADMAP.md" ) > "$TMP/idem.out" 2>&1 || irc=$?
[ ! -f "$RUNDIR_ID/RAN" ] && pass "wave_run i: already-checked box was NOT re-run (idempotent resume)" || fail "wave_run i: re-ran a checked sub-goal"
[ "$irc" = 0 ] && pass "wave_run i: empty/skip-only wave returns 0" || fail "wave_run i: skip-only wave returned $irc"

# ============================ TASK-004b: cmd_run size-dispatch (serial-vs-wave) ============================
# Wire `_wave_run` into `cmd_run` via ADMITTED-count size-dispatch. Sacred invariant: the default
# (WAVE_CAP=1) path is byte-identical to the serial loop. Driven OUT-OF-PROCESS (`bash "$ORCH" run`)
# so the real WAVE_CAP env + parse-time validation are exercised, with a MOCK CLAUDE_CMD.

# ---- (j) no-deps / Touches-less mega-goal at DEFAULT WAVE_CAP -> serial path (admitted 0) ----
# A Touches-less mega-goal admits nothing (Option-B opt-in gate), so even if a wave were considered
# the admitted count is 0 -> the loop falls through to the byte-identical serial body on `_next`'s
# pick and completes serially, exactly as pre-wavefront cmd_run did. No git repo needed (the serial
# path stands up no worktrees). WAVE_CAP is left UNSET so the module default (1) applies.
JA="$TMP/mg-dispatch-serial"; mkdir -p "$JA"
cat > "$JA/ROADMAP.md" <<'EOF'
# Mega-goal: dispatch-serial
## Sub-goals
- [ ] SG-01 first , auto , PR #__
- [ ] SG-02 second , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$JA/POINTER_PROMPT.md"
make_goal "$JA" SG-01   # Touches-less -> never wave-admitted
make_goal "$JA" SG-02   # Touches-less -> never wave-admitted
# Confirm the admission premise: even at cap 2 this mega-goal admits NOTHING (all defer).
assert_gate "dispatch j: Touches-less mega admits nothing (serial fallback premise)" 2 "$JA" "$JA/ROADMAP.md" \
  "$(printf 'defer\tSG-01\ndefer\tSG-02')"
# A serial mock that flips its own box via the locked flip CLI (grounded completion).
cat > "$TMP/claude-serial" <<'MOCK'
#!/usr/bin/env bash
# env: ORCH, MEGADIR ; flips its own box (grounded completion) via the locked CLI.
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
MOCK
chmod +x "$TMP/claude-serial"
jrc=0
( unset WAVE_CAP; export ORCH="$ORCH" MEGADIR="$JA" CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-serial"
  bash "$ORCH" run "$JA" ) > "$TMP/dispatch-serial.out" 2>&1 || jrc=$?
[ "$jrc" = 0 ] && pass "dispatch j: default-WAVE_CAP run exits 0" || { fail "dispatch j: run exited $jrc"; cat "$TMP/dispatch-serial.out"; }
{ grep -q '^- \[x\] SG-01' "$JA/ROADMAP.md" && grep -q '^- \[x\] SG-02' "$JA/ROADMAP.md"; } \
  && pass "dispatch j: both boxes flipped (serial completion)" || fail "dispatch j: boxes not flipped serially"
# The serial marker must appear and the wave path must NOT have been taken.
grep -q 'running SG-01 in a fresh session' "$TMP/dispatch-serial.out" \
  && pass "dispatch j: took the serial body (fresh-session marker present)" || { fail "dispatch j: no serial marker"; cat "$TMP/dispatch-serial.out"; }
grep -q '\[wave\]' "$TMP/dispatch-serial.out" \
  && { fail "dispatch j: wave path was taken on the default serial run"; cat "$TMP/dispatch-serial.out"; } \
  || pass "dispatch j: wave path NOT taken at default WAVE_CAP (byte-identical serial)"

# ---- (k) WAVE_CAP=2 + two Touches-disjoint ready sub-goals -> WAVE path runs (proven concurrent) ----
# Drive the FULL wire cmd_run -> _wave_run through the mock-barrier fifo: a serial impl would time out
# on the barrier and leave a box unflipped, so passing this proves cmd_run routed to the concurrent
# wave. Reuses the barrier mock ($TMP/claude-barrier) defined in TASK-004a (g).
WKR="$TMP/wave-dispatch-repo"
mk_git_mega "$WKR"
WKM="$WKR/mega"; mkdir -p "$WKM"
cat > "$WKM/ROADMAP.md" <<'EOF'
# Mega-goal: wave-dispatch
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WKM/POINTER_PROMPT.md"
make_goal "$WKM" SG-01 "lib/disp-a/**"
make_goal "$WKM" SG-02 "lib/disp-b/**"
FIFODIR_K="$TMP/fifos-k"; mkdir -p "$FIFODIR_K"
mkfifo "$FIFODIR_K/SG-01.fifo" "$FIFODIR_K/SG-02.fifo"
RUNDIR_K="$TMP/run-k"; mkdir -p "$RUNDIR_K"
krc=0
( export FIFODIR="$FIFODIR_K" WAVE_MOCK_IDS="SG-01 SG-02" ORCH="$ORCH" MEGADIR="$WKM" \
    RUNDIR="$RUNDIR_K" BARRIER_T=6 CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-barrier"
  bash "$ORCH" run "$WKM" ) > "$TMP/dispatch-wave.out" 2>&1 || krc=$?
k_b1=$(_sg_line "$WKM/ROADMAP.md" SG-01); k_b2=$(_sg_line "$WKM/ROADMAP.md" SG-02)
k_ok=1
[ "$krc" = 0 ] || k_ok=0
case "$k_b1" in '- [x] SG-01'*) ;; *) k_ok=0 ;; esac
case "$k_b2" in '- [x] SG-02'*) ;; *) k_ok=0 ;; esac
if [ "$k_ok" = 1 ]; then
  pass "dispatch k: cmd_run routed to the WAVE path (both boxes flipped concurrently, rc 0)"
else
  fail "dispatch k: wave not taken/failed (rc=$krc b1='$k_b1' b2='$k_b2')"; cat "$TMP/dispatch-wave.out"
fi
grep -q '\[wave\] spawned' "$TMP/dispatch-wave.out" \
  && pass "dispatch k: wave-path marker present ([wave] spawned)" || { fail "dispatch k: no wave marker"; cat "$TMP/dispatch-wave.out"; }
k_left=$(ls "$RUNDIR_K"/*.running 2>/dev/null | wc -l | tr -d ' ')
[ "$k_left" = 0 ] && pass "dispatch k: no orphaned mock processes remain" || fail "dispatch k: $k_left mock(s) still running"

# ---- (l) WAVE_CAP=0 / non-numeric -> REJECTED at parse (nonzero exit + clear message) ----
# Validation lands AFTER the dir/roadmap/board checks, so a VALID mega dir is used to reach it.
# DEC-009 / Edge case 4: reject, never silently coerce.
lrc=0
( export WAVE_CAP=0 CLAUDE_CMD="$TMP/claude-nope"; bash "$ORCH" run "$JA" ) > "$TMP/cap-zero.out" 2>&1 || lrc=$?
{ [ "$lrc" != 0 ] && grep -qi 'WAVE_CAP' "$TMP/cap-zero.out"; } \
  && pass "dispatch l: WAVE_CAP=0 rejected (nonzero exit + message)" || { fail "dispatch l: WAVE_CAP=0 not rejected (rc=$lrc)"; cat "$TMP/cap-zero.out"; }
mrc=0
( export WAVE_CAP=two CLAUDE_CMD="$TMP/claude-nope"; bash "$ORCH" run "$JA" ) > "$TMP/cap-nan.out" 2>&1 || mrc=$?
{ [ "$mrc" != 0 ] && grep -qi 'WAVE_CAP' "$TMP/cap-nan.out"; } \
  && pass "dispatch l: non-numeric WAVE_CAP rejected (nonzero exit + message)" || { fail "dispatch l: non-numeric WAVE_CAP not rejected (rc=$mrc)"; cat "$TMP/cap-nan.out"; }

# ============================ TASK-004c: _wave_converge convergence sequencer ============================
# _wave_converge <megadir> [<id>...] merges the LANDED wave sub-goals back to the mega-goal base ONE AT
# A TIME (never concurrently), in ROADMAP order, each under the flip lock, through the MOCKABLE
# WAVE_MERGE_CMD hook (real gh-backed merge via lib/mega-merge.sh is deferred to ID-085-followup). It is
# a THIN sequencer: it does not reimplement merging, only orders the calls. Before merging it runs a
# same-file cross-wave guard (belt-and-suspenders over dispatch-gate's pre-admission disjointness): if
# two landed branches changed the SAME file it FLAGS (nonzero + message/event) rather than land a
# clean-but-wrong merge. Tests set WAVE_MERGE_CMD to a mock recording merge ordering.

# A merge-recording mock: append an enter/exit marker around a brief sleep. A SERIAL sequencer emits
# non-interleaved pairs (enter:A exit:A enter:B exit:B); a concurrent one would interleave them, so the
# exact-sequence assertion below is a strict no-temporal-overlap proof. args: <pr> <id>; env: MERGE_LOG.
cat > "$TMP/merge-mock" <<'MOCK'
#!/usr/bin/env bash
printf 'enter:%s:%s\n' "$2" "$1" >> "$MERGE_LOG"
sleep 0.2
printf 'exit:%s:%s\n' "$2" "$1" >> "$MERGE_LOG"
MOCK
chmod +x "$TMP/merge-mock"

# Stand up two wave branches off the base, each editing a DISTINCT file per the id:file pairs given.
# make_wave_branches <repo> <base> <pair...>  where pair = "SG-NN:relpath".
make_wave_branches() {  # repo base pair...
  local repo="$1" base="$2"; shift 2
  local pair id f br
  for pair in "$@"; do
    id="${pair%%:*}"; f="${pair#*:}"
    br="feat/$(printf '%s' "$id" | tr 'A-Z' 'a-z')"
    git -C "$repo" worktree add -q -b "$br" "$repo/.claude/worktrees/$id" "$base" 2>/dev/null
    printf '%s\n' "$id" > "$repo/.claude/worktrees/$id/$f"
    git -C "$repo/.claude/worktrees/$id" add "$f"
    git -C "$repo/.claude/worktrees/$id" commit -q -m "$id: edit $f"
  done
}

# ---- (m) two landed, DISJOINT sub-goals -> merged strictly one-at-a-time in ROADMAP order ----
# Args are passed REVERSED (SG-02 SG-01) to prove the sequencer orders by ROADMAP position, not argv.
CVR="$TMP/converge-repo"
mk_git_mega "$CVR"
CVM="$CVR/mega"; mkdir -p "$CVM"
cat > "$CVM/ROADMAP.md" <<'EOF'
# Mega-goal: converge
## Sub-goals
- [x] SG-01 alpha , auto , PR #101
- [x] SG-02 beta , auto , PR #102
EOF
echo "POINTER: resume" > "$CVM/POINTER_PROMPT.md"
make_goal "$CVM" SG-01 "lib/cv-a/**"
make_goal "$CVM" SG-02 "lib/cv-b/**"
cv_base=$(git -C "$CVR" rev-parse --abbrev-ref HEAD)
make_wave_branches "$CVR" "$cv_base" "SG-01:a.txt" "SG-02:b.txt"
MERGE_LOG_M="$TMP/merge-order.log"; : > "$MERGE_LOG_M"
cvrc=0
( export MERGE_LOG="$MERGE_LOG_M" WAVE_MERGE_CMD="$TMP/merge-mock"
  _wave_converge "$CVM" SG-02 SG-01 ) > "$TMP/cv.out" 2>&1 || cvrc=$?
[ "$cvrc" = 0 ] && pass "converge m: sequencer returns 0 on a clean disjoint wave" || { fail "converge m: rc=$cvrc"; cat "$TMP/cv.out"; }
cv_merges=$(grep -c '^enter:' "$MERGE_LOG_M")
[ "$cv_merges" = 2 ] && pass "converge m: exactly 2 merges recorded" || fail "converge m: $cv_merges merges (want 2)"
cv_seq=$(tr '\n' ' ' < "$MERGE_LOG_M" | sed 's/ *$//')
cv_want="enter:SG-01:101 exit:SG-01:101 enter:SG-02:102 exit:SG-02:102"
[ "$cv_seq" = "$cv_want" ] && pass "converge m: merges strictly serialized in ROADMAP order (no temporal overlap, argv order ignored)" \
  || fail "converge m: sequence '$cv_seq' != '$cv_want'"

# ---- (n) same-file cross-wave edit -> flagged (nonzero), NOT merged ----
CFR="$TMP/converge-samefile-repo"
mk_git_mega "$CFR"
CFM="$CFR/mega"; mkdir -p "$CFM"
cat > "$CFM/ROADMAP.md" <<'EOF'
# Mega-goal: converge-samefile
## Sub-goals
- [x] SG-01 alpha , auto , PR #201
- [x] SG-02 beta , auto , PR #202
EOF
echo "POINTER: resume" > "$CFM/POINTER_PROMPT.md"
make_goal "$CFM" SG-01 "lib/shared/**"
make_goal "$CFM" SG-02 "lib/shared/**"
cf_base=$(git -C "$CFR" rev-parse --abbrev-ref HEAD)
# BOTH branches edit the SAME file (collide.txt) -> the cross-wave overlap the guard must catch.
make_wave_branches "$CFR" "$cf_base" "SG-01:collide.txt" "SG-02:collide.txt"
MERGE_LOG_N="$TMP/merge-order-n.log"; : > "$MERGE_LOG_N"
nfrc=0
( export MERGE_LOG="$MERGE_LOG_N" WAVE_MERGE_CMD="$TMP/merge-mock"
  _wave_converge "$CFM" SG-01 SG-02 ) > "$TMP/cf.out" 2>&1 || nfrc=$?
[ "$nfrc" != 0 ] && pass "converge n: same-file cross-wave edit flagged (nonzero)" || { fail "converge n: not flagged (rc=$nfrc)"; cat "$TMP/cf.out"; }
nf_merges=$(grep -c '^enter:' "$MERGE_LOG_N")
[ "$nf_merges" = 0 ] && pass "converge n: no merge attempted on the flagged wave (not silently merged)" || fail "converge n: $nf_merges merge(s) attempted despite same-file overlap"
grep -qi 'same-file' "$TMP/cf.out" && pass "converge n: clear same-file message emitted" || { fail "converge n: no same-file message"; cat "$TMP/cf.out"; }

# ---- (o) a landed sub-goal with a PLACEHOLDER PR (#__) is skipped, not failed (merge wiring deferred) ----
CPR="$TMP/converge-placeholder-repo"
mk_git_mega "$CPR"
CPM="$CPR/mega"; mkdir -p "$CPM"
cat > "$CPM/ROADMAP.md" <<'EOF'
# Mega-goal: converge-placeholder
## Sub-goals
- [x] SG-01 alpha , auto , PR #__
- [x] SG-02 beta , auto , PR #301
EOF
echo "POINTER: resume" > "$CPM/POINTER_PROMPT.md"
make_goal "$CPM" SG-01 "lib/cp-a/**"
make_goal "$CPM" SG-02 "lib/cp-b/**"
cp_base=$(git -C "$CPR" rev-parse --abbrev-ref HEAD)
make_wave_branches "$CPR" "$cp_base" "SG-01:a.txt" "SG-02:b.txt"
MERGE_LOG_O="$TMP/merge-order-o.log"; : > "$MERGE_LOG_O"
oprc=0
( export MERGE_LOG="$MERGE_LOG_O" WAVE_MERGE_CMD="$TMP/merge-mock"
  _wave_converge "$CPM" SG-01 SG-02 ) > "$TMP/co.out" 2>&1 || oprc=$?
[ "$oprc" = 0 ] && pass "converge o: placeholder-PR sub-goal skipped, wave converges 0" || { fail "converge o: rc=$oprc"; cat "$TMP/co.out"; }
op_seq=$(tr '\n' ' ' < "$MERGE_LOG_O" | sed 's/ *$//')
[ "$op_seq" = "enter:SG-02:301 exit:SG-02:301" ] && pass "converge o: only the real-PR sub-goal (SG-02) merged; placeholder SG-01 skipped" \
  || fail "converge o: sequence '$op_seq' != 'enter:SG-02:301 exit:SG-02:301'"

# ==================== FIXTURE H: per-edge HANDOFF (SPEC-106 TASK-005) ====================
# WRITE keyed on DEPENDENTS (a sub-goal with dependents writes HANDOFF-<id>.md); READ keyed on a
# sub-goal's OWN deps, injecting each dep-parent's HANDOFF-<parent>.md with a plain-HANDOFF.md
# fallback. The linear/no-dependents path stays plain (byte-identical, guarded by test-orchestrate).
HB="$TMP/mg-handoff-edge"; mkdir -p "$HB"
cat > "$HB/ROADMAP.md" <<'EOF'
# Mega-goal: diamond-handoff
## Sub-goals
- [ ] SG-01 root , auto , PR #__
- [ ] SG-02 left , auto , PR #__ , depends SG-01
- [ ] SG-03 right , auto , PR #__ , depends SG-01
- [ ] SG-04 join , gate , PR #__ , depends SG-02 SG-03
EOF
echo "POINTER: resume the mega-goal" > "$HB/POINTER_PROMPT.md"
make_goal "$HB" SG-01; make_goal "$HB" SG-02; make_goal "$HB" SG-03; make_goal "$HB" SG-04

# (a) dependents detection: SG-01 has dependents; SG-04 (the join leaf) has none.
_sg_dependents "$HB/ROADMAP.md" SG-01 && pass "edge a: SG-01 has dependents" || fail "edge a: SG-01 should have dependents"
_sg_dependents "$HB/ROADMAP.md" SG-04 && fail "edge a: SG-04 (leaf) should have NO dependents" || pass "edge a: SG-04 leaf has no dependents"

# (a) WRITE side: SG-01's prompt tells it to overwrite the per-edge HANDOFF-SG-01.md.
p01=$(_build_prompt "$HB" SG-01)
printf '%s' "$p01" | grep -q 'overwrite HANDOFF-SG-01.md with' \
  && pass "edge a: SG-01 (has dependents) write-target is HANDOFF-SG-01.md" \
  || { fail "edge a: SG-01 write-target not per-edge"; printf '%s\n' "$p01" | grep -i overwrite; }

# (a) READ side: SG-04 injects BOTH parents' per-edge handoffs.
printf 'HOTFEED-FROM-SG02-unique\n' > "$HB/HANDOFF-SG-02.md"
printf 'HOTFEED-FROM-SG03-unique\n' > "$HB/HANDOFF-SG-03.md"
p04=$(_build_prompt "$HB" SG-04)
{ printf '%s' "$p04" | grep -q 'HOTFEED-FROM-SG02-unique' && printf '%s' "$p04" | grep -q 'HOTFEED-FROM-SG03-unique'; } \
  && pass "edge a: SG-04 prompt injects BOTH dep-parent handoffs (HANDOFF-SG-02 + HANDOFF-SG-03)" \
  || { fail "edge a: SG-04 missing a parent handoff"; printf '%s\n' "$p04"; }

# (b) fallback: SG-02 depends SG-01, but SG-01 wrote only plain HANDOFF.md (no per-edge file)
#     -> SG-02 still gets the plain handoff injected (no lost feed-forward).
HFB="$TMP/mg-handoff-fallback"; mkdir -p "$HFB"
cat > "$HFB/ROADMAP.md" <<'EOF'
# Mega-goal: fallback-handoff
## Sub-goals
- [ ] SG-01 root , auto , PR #__
- [ ] SG-02 child , auto , PR #__ , depends SG-01
EOF
echo "POINTER: resume" > "$HFB/POINTER_PROMPT.md"
make_goal "$HFB" SG-01; make_goal "$HFB" SG-02
printf 'PLAIN-HANDOFF-fallback-unique\n' > "$HFB/HANDOFF.md"   # parent wrote plain; no HANDOFF-SG-01.md
pfb=$(_build_prompt "$HFB" SG-02)
printf '%s' "$pfb" | grep -q 'PLAIN-HANDOFF-fallback-unique' \
  && pass "edge b: absent per-edge file -> child falls back to plain HANDOFF.md" \
  || { fail "edge b: fallback lost the plain handoff"; printf '%s\n' "$pfb"; }

# (c) linear/no-dependents: plain HANDOFF.md written+read, no per-edge filename anywhere.
HLN="$TMP/mg-handoff-linear"; mkdir -p "$HLN"
cat > "$HLN/ROADMAP.md" <<'EOF'
# Mega-goal: linear-handoff
## Sub-goals
- [ ] SG-01 first , auto , PR #__
- [ ] SG-02 second , auto , PR #__
EOF
echo "POINTER: resume" > "$HLN/POINTER_PROMPT.md"
make_goal "$HLN" SG-01; make_goal "$HLN" SG-02
printf 'PLAIN-LINEAR-unique\n' > "$HLN/HANDOFF.md"
pln=$(_build_prompt "$HLN" SG-02)
{ printf '%s' "$pln" | grep -q 'PLAIN-LINEAR-unique' \
  && printf '%s' "$pln" | grep -q 'overwrite HANDOFF.md with' \
  && ! printf '%s' "$pln" | grep -q 'HANDOFF-SG'; } \
  && pass "edge c: linear/no-deps writes+reads plain HANDOFF.md (no per-edge filename)" \
  || { fail "edge c: linear path not plain"; printf '%s\n' "$pln"; }

# ============================ TASK-006: idempotent resume (exit-criterion 3) ============================
# Killing the orchestrator mid-run and restarting must RE-DERIVE state from the ROADMAP boxes and
# NEVER re-run a checked sub-goal. Model: run 1 flips SG-01+SG-02 then stops at the gate SG-03 (the
# "stop mid-run" boundary); each mock invocation appends to a per-id runlog. Run 2 (the restart)
# re-derives from the same ROADMAP -- SG-01+SG-02 are already checked so `_next` skips them -- and we
# assert each checked id's runlog count did NOT increase. Serial path (no WAVE_CAP), no git repo.
RES="$TMP/mg-resume"; mkdir -p "$RES"
cat > "$RES/ROADMAP.md" <<'EOF'
# Mega-goal: resume
## Sub-goals
- [ ] SG-01 first , auto , PR #__
- [ ] SG-02 second , auto , PR #__
- [ ] SG-03 gated , gate , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$RES/POINTER_PROMPT.md"
make_goal "$RES" SG-01; make_goal "$RES" SG-02; make_goal "$RES" SG-03
RESLOG="$TMP/resume-runlog"; mkdir -p "$RESLOG"
# Mock: append one line to <id>.runs per invocation, then flip the box via the locked flip CLI.
cat > "$TMP/claude-resume" <<'MOCK'
#!/usr/bin/env bash
# env: ORCH, MEGADIR, RESLOG
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
echo 1 >> "$RESLOG/$id.runs"
bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
MOCK
chmod +x "$TMP/claude-resume"
# Run 1: flips SG-01+SG-02, stops at the gate SG-03 (partway; the kill boundary).
( export ORCH="$ORCH" MEGADIR="$RES" RESLOG="$RESLOG" CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-resume"
  bash "$ORCH" run "$RES" ) > "$TMP/resume1.out" 2>&1
c1_r1=$(wc -l < "$RESLOG/SG-01.runs" 2>/dev/null | tr -d ' '); c2_r1=$(wc -l < "$RESLOG/SG-02.runs" 2>/dev/null | tr -d ' ')
{ grep -q '^- \[x\] SG-01' "$RES/ROADMAP.md" && grep -q '^- \[x\] SG-02' "$RES/ROADMAP.md" \
    && grep -q '^- \[ \] SG-03' "$RES/ROADMAP.md" && [ "$c1_r1" = 1 ] && [ "$c2_r1" = 1 ]; } \
  && pass "resume: run 1 flips SG-01+SG-02, stops at gate (each ran once)" \
  || { fail "resume: run 1 partial-progress wrong (c1=$c1_r1 c2=$c2_r1)"; cat "$TMP/resume1.out"; }
# Run 2 (the restart): re-derive from ROADMAP; already-checked boxes must NOT be re-run.
( export ORCH="$ORCH" MEGADIR="$RES" RESLOG="$RESLOG" CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-resume"
  bash "$ORCH" run "$RES" ) > "$TMP/resume2.out" 2>&1
c1_r2=$(wc -l < "$RESLOG/SG-01.runs" 2>/dev/null | tr -d ' '); c2_r2=$(wc -l < "$RESLOG/SG-02.runs" 2>/dev/null | tr -d ' ')
{ [ "$c1_r2" = 1 ] && [ "$c2_r2" = 1 ]; } \
  && pass "resume: restart re-runs NO already-checked sub-goal (SG-01/SG-02 count unchanged)" \
  || { fail "resume: a checked sub-goal was re-invoked (c1=$c1_r2 c2=$c2_r2)"; cat "$TMP/resume2.out"; }

# ==================== TASK-006: wave-path termination guard (wait-vs-complete) ====================
# On the WAVE path (WAVE_CAP>=2), when unchecked sub-goals REMAIN but the ready set is EMPTY (all
# dep-blocked, nothing runnable, no in-flight producer), the loop must HALT with a "blocked: N
# unchecked, none runnable" message + NONZERO exit -- NOT a false "all sub-goals checked; done", NOT
# a spin, and NOT run a dep-blocked sub-goal. Fixture: a mutual-dep cycle (SG-02 depends SG-03, SG-03
# depends SG-02) with SG-01 pre-checked, so admitted==0 and _ready_set is empty while 2 remain
# unchecked. (Without the guard, the dep-ignorant serial `_next` fallthrough ran BOTH boxes to a
# false "done" -- proven pre-fix.)
TG="$TMP/mg-wave-blocked"; mkdir -p "$TG"
cat > "$TG/ROADMAP.md" <<'EOF'
# Mega-goal: wave-blocked
## Sub-goals
- [x] SG-01 done , auto , PR #__
- [ ] SG-02 needs three , auto , PR #__ , depends SG-03
- [ ] SG-03 needs two , auto , PR #__ , depends SG-02
EOF
echo "POINTER: resume from ROADMAP" > "$TG/POINTER_PROMPT.md"
make_goal "$TG" SG-02 "lib/tg-a/**"; make_goal "$TG" SG-03 "lib/tg-b/**"
TGLOG="$TMP/wave-blocked-runlog"; : > "$TGLOG"
# A mock that would flip+log if ever invoked -- it must NOT be, because nothing is runnable.
cat > "$TMP/claude-blocked" <<'MOCK'
#!/usr/bin/env bash
# env: ORCH, MEGADIR, TGLOG
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
echo "INVOKED $id" >> "$TGLOG"
bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
MOCK
chmod +x "$TMP/claude-blocked"
tgrc=0
( export ORCH="$ORCH" MEGADIR="$TG" TGLOG="$TGLOG" CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-blocked"
  bash "$ORCH" run "$TG" ) > "$TMP/wave-blocked.out" 2>&1 || tgrc=$?
# (1) nonzero exit, not a false-complete
{ [ "$tgrc" != 0 ] && ! grep -q 'all sub-goals checked; done' "$TMP/wave-blocked.out"; } \
  && pass "wave-block: halts nonzero, no false-complete" \
  || { fail "wave-block: did not halt nonzero / false-completed (rc=$tgrc)"; cat "$TMP/wave-blocked.out"; }
# (2) clear blocked message naming the unchecked count
grep -q 'blocked: 2 unchecked, none runnable' "$TMP/wave-blocked.out" \
  && pass "wave-block: clear 'blocked: N unchecked, none runnable' message" \
  || { fail "wave-block: no blocked message"; cat "$TMP/wave-blocked.out"; }
# (3) no dep-blocked sub-goal was run; boxes untouched
{ [ ! -s "$TGLOG" ] && grep -q '^- \[ \] SG-02' "$TG/ROADMAP.md" && grep -q '^- \[ \] SG-03' "$TG/ROADMAP.md"; } \
  && pass "wave-block: ran no dep-blocked sub-goal (boxes untouched)" \
  || { fail "wave-block: a dep-blocked sub-goal ran"; cat "$TGLOG"; }

# ---- cleanup: remove wave worktrees via git's own remover (never rm -rf a tracked path) ----
for wtrepo in "$WCR" "$WFR" "$WIR" "$WKR" "$CVR" "$CFR" "$CPR"; do
  [ -d "$wtrepo" ] || continue
  git -C "$wtrepo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | while read -r w; do
    case "$w" in *"/.claude/worktrees/"*) git -C "$wtrepo" worktree remove --force "$w" 2>/dev/null ;; esac
  done
done

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }

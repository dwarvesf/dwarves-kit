#!/usr/bin/env bash
# test-wave-rolling.sh
# Pins rolling wave admission (WAVE_ROLLING=1, lib/queue/orchestrate.sh). With the switch off a wave
# is a barrier: a freed slot idles until the slowest member ends. With it on, a landed member's slot
# is refilled from the recomputed ready set, under the same disjointness and grounded-completion rules.
#
#   (a) fast + slow member: the fast one's slot admits its newly ready dependent before the slow one ends
#   (a-NC) NEGATIVE CONTROL: switch off, the same fixture runs the dependent only after the slow one ends
#   (b) a newly ready candidate that overlaps a running member waits until that member ends
#   (c) a member that exits 0 without flipping its box halts admission (no retry, siblings drain)
#   (d) abort during a rolling wave kills every live member, the late-admitted one included, no orphan
#   (e) WAVE_CAP=1: the switch changes nothing (stdout, prompts, events identical on and off)
#   (f) the switch resolves from [mega].wave_rolling and defaults off
#   (g) convergence runs per landed member, before its slot is refilled, and stays fail-closed
#   (h) a flipped box is not completion: a dependent waits for its parent to exit AND converge (h1),
#       and never runs on a parent that flipped then failed (h2)
#   (i) aborts: TERM during the last member's converge halts the run (i1); TERM while a refill is
#       spawning starts nothing new and the driver exits (i2)
#   (j) rolling-only branches: a refused refill spawn halts admission (j1), a gate! that becomes ready
#       mid-wave stops admission (j2), WAVE_CAP=3 refills two slots in one pass without overshoot (j3)
#
# Real `orchestrate.sh run` against a throwaway git repo (real worktrees), mock claude, no network.
# Run: bash tests/test-wave-rolling.sh   (exit 0 = pass, 1 = fail)
set -uo pipefail
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"   # physical path: worktree cwds come back from git resolved (/private/var/...)

alive() { kill -0 "$1" 2>/dev/null; }
wait_for_file() {  # path secs
  local i=0 max=$(( $2 * 10 ))
  while [ ! -s "$1" ] && [ "$i" -lt "$max" ]; do sleep 0.1; i=$((i + 1)); done
  [ -s "$1" ]
}

# Everything that could touch shared state points into $TMP: the run ledger, the SPEC reservation
# ledger (a missing reserve command degrades to "worker self-computes"), the tier-4 close, the merge hook,
# and the host-load warning (its line would make the (e) stdout comparison depend on host load).
export KIT_LOAD_STUB=0 DWARVES_KIT_LOG_DIR="$TMP/logs" SPEC_NEXT_CMD="$TMP/no-spec-next" TIER4_CLOSE=0 TURN_CAP=0 \
  CLAUDE_FLAGS="" MULTIPLEXER=0 PANE_VIEWER=none WAVE_POLL_SECS=0.1 WAVE_MERGE_CMD=true MEGA_MERGE_GH=false

mk_mega() {  # name roadmap-body -> prints the megadir
  local repo="$TMP/$1" mg="$TMP/$1/mega"
  mkdir -p "$mg/goals"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
  printf '# Mega-goal: %s\n## Sub-goals\n%s\n' "$1" "$2" > "$mg/ROADMAP.md"
  echo "POINTER: resume from ROADMAP" > "$mg/POINTER_PROMPT.md"
  printf '%s' "$mg"
}

goal() {  # megadir id touches-glob
  printf '# %s: sub-goal\n**Branch:** feat/roll-%s\n\n## Touches\n- %s\n' "$2" "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" "$3" \
    > "$1/goals/${2#SG-}-$2.md"
}

# Mock claude. Behavior per sub-goal comes from env:
#   NOFLIP_IDS  ids that exit 0 WITHOUT flipping their box
#   WAITFOR_<id>=<other>  block until <other> has started, or WAIT_SECS pass, before finishing
#   AFTER_<id>=<other>    block until <other> has ended (then 1s more), or WAIT_SECS pass, before finishing
#   HANG_IDS    ids that hang forever (sleep child), writing "<pid> <child>" to $TMP/hang.<id>
#   COMMIT_<id>=<file>  commit <file> on the member's branch (only inside a worktree under $TMP)
#   FLIPFIRST_<id>=<other>  flip the box FIRST (logging "flipped <id>"), then linger until <other> starts or
#                           WAIT_SECS pass, then exit FLIPRC_<id> (default 0): a session alive after its flip
# Every session appends "start <id>" / "end <id>" to $EVENTS (append order is the timeline) and keeps
# its prompt in $PROMPTS/<id>.<n>.
cat > "$TMP/claude" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | sed -nE 's/^NEXT SUB-GOAL: (SG-[0-9]+).*/\1/p' | head -1)
n=1; while [ -e "$PROMPTS/$id.$n" ]; do n=$((n + 1)); done
printf '%s' "$prompt" > "$PROMPTS/$id.$n"
echo "start $id" >> "$EVENTS"
case " ${HANG_IDS:-} " in *" $id "*)
  sleep 300 &
  echo "$$ $!" > "$TMP/hang.$id"
  wait
  exit 0 ;;
esac
waitvar="WAITFOR_${id//-/_}"; other="${!waitvar:-}"
if [ -n "$other" ]; then
  i=0; max=$(( ${WAIT_SECS:-5} * 10 ))
  while ! grep -qx "start $other" "$EVENTS" && [ "$i" -lt "$max" ]; do sleep 0.1; i=$((i + 1)); done
fi
aftervar="AFTER_${id//-/_}"; after="${!aftervar:-}"
if [ -n "$after" ]; then
  i=0; max=$(( ${WAIT_SECS:-5} * 10 ))
  while ! grep -qx "end $after" "$EVENTS" && [ "$i" -lt "$max" ]; do sleep 0.1; i=$((i + 1)); done
  sleep 1
fi
flipvar="FLIPFIRST_${id//-/_}"; ff="${!flipvar:-}"
if [ -n "$ff" ]; then
  bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1; echo "flipped $id" >> "$EVENTS"
  i=0; max=$(( ${WAIT_SECS:-5} * 10 ))
  while ! grep -qx "start $ff" "$EVENTS" && [ "$i" -lt "$max" ]; do sleep 0.1; i=$((i + 1)); done
  rcvar="FLIPRC_${id//-/_}"; echo "end $id" >> "$EVENTS"; exit "${!rcvar:-0}"
fi
commitvar="COMMIT_${id//-/_}"; cfile="${!commitvar:-}"
if [ -n "$cfile" ]; then
  case "$PWD" in "$TMP"/*/.claude/worktrees/*)
    echo "$id" > "$cfile" && git add "$cfile" && git commit -q -m "test: $id edits $cfile" ;;
  esac
fi
case " ${NOFLIP_IDS:-} " in *" $id "*) ;; *) bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1 ;; esac
echo "end $id" >> "$EVENTS"
MOCK
chmod +x "$TMP/claude"

run_case() {  # megadir outfile [env...]   -> rc in $RC; timeline in $mg/.events
  local mg="$1" out="$2"; shift 2
  mkdir -p "$mg/.prompts"; : > "$mg/.events"
  RC=0
  env ORCH="$ORCH" TMP="$TMP" MEGADIR="$mg" EVENTS="$mg/.events" PROMPTS="$mg/.prompts" \
    CLAUDE_CMD="$TMP/claude" "$@" bash "$ORCH" run "$mg" > "$out" 2>&1 < /dev/null || RC=$?
}
before() {  # timeline lineA lineB -> 0 iff A appears and precedes B
  awk -v a="$2" -v b="$3" '$0==a && !sa {sa=NR} $0==b && !sb {sb=NR} END{exit !(sa && sb && sa < sb)}' "$1"
}
boxes() { grep -cE '^- \[x\] SG-' "$1/ROADMAP.md"; }

# ============ (a) fast + slow: the dependent takes the fast member's slot ============
FIX_A='- [ ] SG-01 fast , auto , PR #__
- [ ] SG-02 slow , auto , PR #__
- [ ] SG-03 needs fast , auto , depends SG-01 , PR #__'
mk_a() {
  local mg; mg=$(mk_mega "$1" "$FIX_A")
  goal "$mg" SG-01 'lib/a/**'; goal "$mg" SG-02 'lib/b/**'; goal "$mg" SG-03 'lib/c/**'
  printf '%s' "$mg"
}
MA=$(mk_a roll-a)
run_case "$MA" "$TMP/a.out" WAVE_CAP=2 WAVE_ROLLING=1 WAITFOR_SG_02=SG-03 WAIT_SECS=6
if [ "$RC" = 0 ] && [ "$(boxes "$MA")" = 3 ] && before "$MA/.events" "start SG-03" "end SG-02"; then
  pass "(a) the slot SG-01 freed admitted its dependent SG-03 before the slow SG-02 ended (all 3 boxes, rc 0)"
else
  fail "(a) rc=$RC boxes=$(boxes "$MA") timeline: $(tr '\n' ' ' < "$MA/.events")"; tail -20 "$TMP/a.out"
fi
grep -q '\[rolling\] SG-03 admitted into a freed slot (still running: SG-02)' "$TMP/a.out" \
  && pass "(a) the driver says SG-03 was admitted while SG-02 was still running" \
  || { fail "(a) no rolling-admission line"; tail -20 "$TMP/a.out"; }
grep -q 'WAVE SESSION , SHARED-ROADMAP FLIP CONTRACT' "$MA/.prompts/SG-03.1" \
  && pass "(a) the late-admitted member got the wave prompt (shared-ROADMAP flip contract), same spawn path" \
  || fail "(a) SG-03's prompt has no wave flip contract"
grep -q '\[x\] SG-03' "$MA/ROADMAP.md" && [ -d "$TMP/roll-a/.claude/worktrees/SG-03" ] \
  && pass "(a) SG-03 ran in its own worktree" || fail "(a) SG-03 worktree missing"

# ============ (a-NC) switch off: the same fixture runs SG-03 only after SG-02 ends ============
MN=$(mk_a roll-nc)
run_case "$MN" "$TMP/nc.out" WAVE_CAP=2 WAVE_ROLLING=0 WAITFOR_SG_02=SG-03 WAIT_SECS=3
if before "$MN/.events" "start SG-03" "end SG-02"; then
  fail "(a-NC) switch off but SG-03 still started before SG-02 ended: $(tr '\n' ' ' < "$MN/.events")"
elif [ "$RC" = 0 ] && [ "$(boxes "$MN")" = 3 ] && before "$MN/.events" "end SG-02" "start SG-03"; then
  pass "(a-NC) NEGATIVE CONTROL: switch off, the barrier holds; SG-03 starts only after SG-02 ends (the (a) assertion fails here)"
else
  fail "(a-NC) rc=$RC boxes=$(boxes "$MN") timeline: $(tr '\n' ' ' < "$MN/.events")"; tail -20 "$TMP/nc.out"
fi

# ============ (b) an overlapping candidate waits for the member it overlaps ============
MB=$(mk_mega roll-b "$FIX_A")
goal "$MB" SG-01 'lib/a/**'; goal "$MB" SG-02 'lib/b/**'; goal "$MB" SG-03 'lib/b/**'
run_case "$MB" "$TMP/b.out" WAVE_CAP=2 WAVE_ROLLING=1 WAITFOR_SG_02=SG-03 WAIT_SECS=3
if [ "$RC" = 0 ] && [ "$(boxes "$MB")" = 3 ] && before "$MB/.events" "end SG-02" "start SG-03" \
   && ! grep -q 'SG-03 admitted into a freed slot' "$TMP/b.out"; then
  pass "(b) SG-03 overlaps the running SG-02 (lib/b/**): not admitted into the free slot, ran after SG-02 ended"
else
  fail "(b) rc=$RC boxes=$(boxes "$MB") timeline: $(tr '\n' ' ' < "$MB/.events")"; tail -20 "$TMP/b.out"
fi

# ============ (c) a member that exits without flipping halts admission ============
MC=$(mk_mega roll-c '- [ ] SG-01 noflip , auto , PR #__
- [ ] SG-02 slow , auto , PR #__
- [ ] SG-03 ready but over cap , auto , PR #__')
goal "$MC" SG-01 'lib/a/**'; goal "$MC" SG-02 'lib/b/**'; goal "$MC" SG-03 'lib/c/**'
run_case "$MC" "$TMP/c.out" WAVE_CAP=2 WAVE_ROLLING=1 NOFLIP_IDS=SG-01 WAITFOR_SG_02=SG-03 WAIT_SECS=2
if [ "$RC" != 0 ] && ! grep -q 'start SG-03' "$MC/.events" && [ "$(grep -c 'start SG-01' "$MC/.events")" = 1 ] \
   && grep -q '^- \[ \] SG-01' "$MC/ROADMAP.md" && grep -q '^- \[x\] SG-02' "$MC/ROADMAP.md" \
   && grep -q 'wave: box not flipped (no self-claim)' "$MC/.orchestrate/events.log" \
   && grep -q 'did not complete (nonzero exit or unflipped box); halting' "$TMP/c.out"; then
  pass "(c) SG-01 exited unflipped: no admission into its slot (SG-03 never ran), no wave retry, SG-02 drained, run halted nonzero"
else
  fail "(c) rc=$RC timeline: $(tr '\n' ' ' < "$MC/.events") roadmap: $(grep SG- "$MC/ROADMAP.md" | tr '\n' ' ')"; tail -20 "$TMP/c.out"
fi

# ============ (d) abort during a rolling wave leaves no orphan ============
MD=$(mk_mega roll-d '- [ ] SG-01 fast , auto , PR #__
- [ ] SG-02 hangs , auto , PR #__
- [ ] SG-03 needs fast, hangs , auto , depends SG-01 , PR #__
- [ ] SG-04 needs fast , auto , depends SG-01 , PR #__')
goal "$MD" SG-01 'lib/a/**'; goal "$MD" SG-02 'lib/b/**'; goal "$MD" SG-03 'lib/c/**'; goal "$MD" SG-04 'lib/d/**'
mkdir -p "$MD/.prompts"; : > "$MD/.events"
env ORCH="$ORCH" TMP="$TMP" MEGADIR="$MD" EVENTS="$MD/.events" PROMPTS="$MD/.prompts" CLAUDE_CMD="$TMP/claude" \
  WAVE_CAP=2 WAVE_ROLLING=1 HANG_IDS="SG-02 SG-03" bash "$ORCH" run "$MD" > "$TMP/d.out" 2>&1 < /dev/null &
opid=$!
if wait_for_file "$TMP/hang.SG-02" 20 && wait_for_file "$TMP/hang.SG-03" 20; then
  read -r m2 g2 < "$TMP/hang.SG-02"; read -r m3 g3 < "$TMP/hang.SG-03"
  kill -TERM "$opid"
  wait "$opid" 2>/dev/null; drc=$?
  sleep 0.5
  if ! alive "$m2" && ! alive "$g2" && ! alive "$m3" && ! alive "$g3" && [ "$drc" != 0 ] \
     && ! grep -q 'start SG-04' "$MD/.events" && grep -q '\[rolling\] SG-03 admitted' "$TMP/d.out"; then
    pass "(d) TERM mid rolling wave: SG-02 and the late-admitted SG-03 (sessions + grandchildren) are gone, nothing new admitted, rc $drc"
  else
    fail "(d) alive: m2=$(alive "$m2" && echo y || echo n) g2=$(alive "$g2" && echo y || echo n) m3=$(alive "$m3" && echo y || echo n) g3=$(alive "$g3" && echo y || echo n) rc=$drc timeline: $(tr '\n' ' ' < "$MD/.events")"
    tail -20 "$TMP/d.out"
    kill -KILL "$m2" "$g2" "$m3" "$g3" 2>/dev/null
  fi
else
  fail "(d) the hanging members never both started (rolling admission of SG-03 missing?)"; tail -20 "$TMP/d.out"
  kill -TERM "$opid" 2>/dev/null; wait "$opid" 2>/dev/null
fi

# ============ (e) WAVE_CAP=1: the switch changes nothing ============
FIX_E='- [ ] SG-01 first , auto , PR #__
- [ ] SG-02 second , auto , PR #__
- [ ] SG-03 third , auto , depends SG-01 , PR #__'
norm() { sed -e "s#$TMP/[a-z-]*#<T>#g" -e 's/^[0-9TZ:-]* |/<ts> |/' "$1"; }
for sw in 0 1; do
  ME=$(mk_mega "roll-e$sw" "$FIX_E")
  goal "$ME" SG-01 'lib/a/**'; goal "$ME" SG-02 'lib/b/**'; goal "$ME" SG-03 'lib/c/**'
  run_case "$ME" "$TMP/e$sw.out" WAVE_CAP=1 WAVE_ROLLING=$sw
  eval "RC_E$sw=\$RC"
done
E0="$TMP/roll-e0/mega"; E1="$TMP/roll-e1/mega"
same=1
diff <(norm "$TMP/e0.out") <(norm "$TMP/e1.out") >/dev/null || { same=0; echo "  stdout differs"; }
for f in SG-01.1 SG-02.1 SG-03.1; do
  diff <(norm "$E0/.prompts/$f") <(norm "$E1/.prompts/$f") >/dev/null || { same=0; echo "  prompt $f differs"; }
done
diff <(cut -f2- "$E0/.orchestrate/events.log") <(cut -f2- "$E1/.orchestrate/events.log") || { same=0; echo "  events differ"; }
diff "$E0/.events" "$E1/.events" >/dev/null || { same=0; echo "  session order differs"; }
if [ "$same" = 1 ] && [ "$RC_E0" = 0 ] && [ "$RC_E1" = 0 ] && [ "$(boxes "$E1")" = 3 ] \
   && ! grep -q '\[wave\]' "$TMP/e1.out" && [ ! -d "$TMP/roll-e1/.claude/worktrees" ]; then
  pass "(e) WAVE_CAP=1: stdout, prompts, events and session order identical with the switch on and off; serial, no worktrees"
else
  fail "(e) same=$same rc0=$RC_E0 rc1=$RC_E1 boxes=$(boxes "$E1")"; diff <(norm "$TMP/e0.out") <(norm "$TMP/e1.out") | head -10
fi

# ============ (f) config: [mega].wave_rolling, default off ============
mkdir -p "$TMP/proj"; printf '[mega]\nwave_rolling = true\n' > "$TMP/proj/.kit.toml"
v_def=$(env -u WAVE_ROLLING KIT_CONFIG_ROOT="$TMP/no-root" KIT_PROJECT_ROOT="$TMP/no-proj" bash -c 'source "$1"; printf %s "$WAVE_ROLLING"' _ "$ORCH" 2>/dev/null)
v_cfg=$(env -u WAVE_ROLLING KIT_CONFIG_ROOT="$TMP/no-root" KIT_PROJECT_ROOT="$TMP/proj" bash -c 'source "$1"; printf %s "$WAVE_ROLLING"' _ "$ORCH" 2>/dev/null)
v_env=$(WAVE_ROLLING=0 KIT_CONFIG_ROOT="$TMP/no-root" KIT_PROJECT_ROOT="$TMP/proj" bash -c 'source "$1"; printf %s "$WAVE_ROLLING"' _ "$ORCH" 2>/dev/null)
[ "$v_def" = 0 ] && [ "$v_cfg" = 1 ] && [ "$v_env" = 0 ] \
  && pass "(f) WAVE_ROLLING defaults off, [mega].wave_rolling = true turns it on, the env var wins" \
  || fail "(f) default='$v_def' config='$v_cfg' env-over-config='$v_env'"

# ============ (g) convergence runs per landed member, fail-closed ============
# Merge hook records into the timeline; gh reports every PR merged.
printf '#!/usr/bin/env bash\necho "merge PR $1" >> "$EVENTS"\n' > "$TMP/merge-rec"; chmod +x "$TMP/merge-rec"
printf '#!/usr/bin/env bash\necho MERGED\n' > "$TMP/gh-merged"; chmod +x "$TMP/gh-merged"
FIX_G='- [ ] SG-01 fast , auto , PR #11
- [ ] SG-02 slow , auto , PR #12
- [ ] SG-03 needs fast , auto , depends SG-01 , PR #13'
# g1: SG-03 edits the same file SG-01 did, but ran strictly after it (a dependent): no false halt, either
# when SG-03 converges (SG-01 is not its peer) or when SG-02 converges last with BOTH as peers (peers are
# never compared with each other). SG-02 waits for SG-03 to END, so it lands last.
MG1=$(mk_mega roll-g1 "$FIX_G")
goal "$MG1" SG-01 'lib/a/**'; goal "$MG1" SG-02 'lib/b/**'; goal "$MG1" SG-03 'lib/c/**'
run_case "$MG1" "$TMP/g1.out" WAVE_CAP=2 WAVE_ROLLING=1 AFTER_SG_02=SG-03 WAIT_SECS=8 \
  WAVE_MERGE_CMD="$TMP/merge-rec" MEGA_MERGE_GH="$TMP/gh-merged" COMMIT_SG_01=a.txt COMMIT_SG_03=a.txt
if [ "$RC" = 0 ] && [ "$(boxes "$MG1")" = 3 ] && before "$MG1/.events" "merge PR 11" "start SG-03" \
   && [ "$(grep -c '^merge PR' "$MG1/.events")" = 3 ] && [ "$(grep -c '^merge PR 11$' "$MG1/.events")" = 1 ] \
   && [ "$(grep -c 'merged	converge' "$MG1/.orchestrate/events.log")" = 3 ] \
   && [ "$(git -C "$TMP/roll-g1" show feat/roll-sg-01:a.txt 2>/dev/null)" = SG-01 ] \
   && [ "$(git -C "$TMP/roll-g1" show feat/roll-sg-03:a.txt 2>/dev/null)" = SG-03 ]; then
  pass "(g1) SG-01 merged before its dependent took the slot; each PR merged exactly once; a dependent editing its parent's file is not flagged"
else
  fail "(g1) rc=$RC boxes=$(boxes "$MG1") timeline: $(tr '\n' ' ' < "$MG1/.events")"; tail -20 "$TMP/g1.out"
fi
# g2: SG-01 and SG-02 ran at the same time and both edited same.txt: the guard refuses SG-02, admission
# stops. SG-03 (admitted into SG-01's slot) lands after SG-02, so its freed slot must NOT admit SG-04.
MG2=$(mk_mega roll-g2 '- [ ] SG-01 fast , auto , PR #21
- [ ] SG-02 slow , auto , PR #22
- [ ] SG-03 independent, over cap , auto , PR #23
- [ ] SG-04 independent, over cap , auto , PR #24')
goal "$MG2" SG-01 'lib/a/**'; goal "$MG2" SG-02 'lib/b/**'; goal "$MG2" SG-03 'lib/c/**'; goal "$MG2" SG-04 'lib/d/**'
run_case "$MG2" "$TMP/g2.out" WAVE_CAP=2 WAVE_ROLLING=1 WAITFOR_SG_02=SG-03 AFTER_SG_03=SG-02 WAIT_SECS=8 \
  WAVE_MERGE_CMD="$TMP/merge-rec" MEGA_MERGE_GH="$TMP/gh-merged" COMMIT_SG_01=same.txt COMMIT_SG_02=same.txt
if [ "$RC" != 0 ] && grep -q 'SAME-FILE cross-wave edit' "$TMP/g2.out" && grep -q '^    same.txt' "$TMP/g2.out" \
   && ! grep -q '^merge PR 22$' "$MG2/.events" && ! grep -q 'start SG-04' "$MG2/.events" \
   && before "$MG2/.events" "end SG-02" "end SG-03" && ! grep -q '^merge PR 23$' "$MG2/.events" \
   && grep -q 'convergence flagged a same-file cross-wave conflict' "$TMP/g2.out"; then
  pass "(g2) two members that ran together both edited same.txt: SG-02 is refused (not merged); SG-03 landing after it is not converged and its slot is not refilled; the run halts"
else
  fail "(g2) rc=$RC timeline: $(tr '\n' ' ' < "$MG2/.events")"; tail -20 "$TMP/g2.out"
fi

# ============ (h) a flipped box is not completion ============
# h1: SG-01 flips, then keeps running; SG-02 lands. SG-03 (depends SG-01) must wait for SG-01 to exit and
# converge. SG-01 lingers until SG-03 starts (the thing that must not happen) or 3s pass.
MH1=$(mk_mega roll-h1 '- [ ] SG-01 parent lingers , auto , PR #11
- [ ] SG-02 fast , auto , PR #12
- [ ] SG-03 child , auto , depends SG-01 , PR #13')
goal "$MH1" SG-01 'lib/a/**'; goal "$MH1" SG-02 'lib/b/**'; goal "$MH1" SG-03 'lib/c/**'
run_case "$MH1" "$TMP/h1.out" WAVE_CAP=2 WAVE_ROLLING=1 FLIPFIRST_SG_01=SG-03 WAIT_SECS=3 \
  WAVE_MERGE_CMD="$TMP/merge-rec" MEGA_MERGE_GH="$TMP/gh-merged"
if [ "$RC" = 0 ] && [ "$(boxes "$MH1")" = 3 ] && before "$MH1/.events" "end SG-01" "start SG-03" \
   && before "$MH1/.events" "merge PR 11" "start SG-03"; then
  pass "(h1) SG-01 flipped but was still running: its dependent SG-03 started only after SG-01 exited and merged"
else
  fail "(h1) rc=$RC boxes=$(boxes "$MH1") timeline: $(tr '\n' ' ' < "$MH1/.events")"; tail -15 "$TMP/h1.out"
fi
# h2: SG-02 flips, lingers, exits 1. SG-01 lands meanwhile. SG-03 (depends SG-02) must never run.
MH2=$(mk_mega roll-h2 '- [ ] SG-01 lands while SG-02 lingers , auto , PR #__
- [ ] SG-02 flips then fails , auto , PR #__
- [ ] SG-03 needs SG-02 , auto , depends SG-02 , PR #__')
goal "$MH2" SG-01 'lib/a/**'; goal "$MH2" SG-02 'lib/b/**'; goal "$MH2" SG-03 'lib/c/**'
run_case "$MH2" "$TMP/h2.out" WAVE_CAP=2 WAVE_ROLLING=1 FLIPFIRST_SG_02=SG-03 FLIPRC_SG_02=1 WAIT_SECS=3
if [ "$RC" != 0 ] && ! grep -q 'start SG-03' "$MH2/.events" && before "$MH2/.events" "end SG-01" "end SG-02" \
   && grep -q 'SG-02	blocked	wave session exited nonzero (1)' "$MH2/.orchestrate/events.log"; then
  pass "(h2) SG-02 flipped then exited 1: SG-03 never ran on the failed, unconverged parent; the run halted"
else
  fail "(h2) rc=$RC timeline: $(tr '\n' ' ' < "$MH2/.events")"; tail -15 "$TMP/h2.out"
fi

# ============ (i) aborts ============
# i1: TERM to the driver from inside the merge hook of the LAST member to land (SG-02). SG-03 must not run.
printf '#!/usr/bin/env bash\necho "merge PR $1" >> "$EVENTS"\n[ "$1" = 12 ] && kill -TERM $PPID\nexit 0\n' > "$TMP/merge-kill"; chmod +x "$TMP/merge-kill"
MI1=$(mk_mega roll-i1 '- [ ] SG-01 a , auto , PR #11
- [ ] SG-02 b lands last , auto , PR #12
- [ ] SG-03 after both , auto , depends SG-01 SG-02 , PR #13')
goal "$MI1" SG-01 'lib/a/**'; goal "$MI1" SG-02 'lib/b/**'; goal "$MI1" SG-03 'lib/c/**'
run_case "$MI1" "$TMP/i1.out" WAVE_CAP=2 WAVE_ROLLING=1 AFTER_SG_02=SG-01 WAIT_SECS=4 \
  WAVE_MERGE_CMD="$TMP/merge-kill" MEGA_MERGE_GH="$TMP/gh-merged"
if [ "$RC" != 0 ] && grep -q '^merge PR 12$' "$MI1/.events" && ! grep -q 'start SG-03' "$MI1/.events" \
   && grep -q 'aborted' "$TMP/i1.out"; then
  pass "(i1) TERM during the last member's converge: the run halts (rc $RC), the next cycle never starts SG-03"
else
  fail "(i1) rc=$RC timeline: $(tr '\n' ' ' < "$MI1/.events")"; tail -15 "$TMP/i1.out"
fi
# i2: TERM fires from inside the SPEC reserve hook while the refill for SG-03 is being spawned (third
# reserve call: SG-01, SG-02, then SG-03). Nothing may spawn after the abort, and the driver must exit.
MI2=$(mk_mega roll-i2 '- [ ] SG-01 fast , auto , PR #__
- [ ] SG-02 hangs , auto , PR #__
- [ ] SG-03 child hangs , auto , depends SG-01 , PR #__')
goal "$MI2" SG-01 'lib/a/**'; goal "$MI2" SG-02 'lib/b/**'; goal "$MI2" SG-03 'lib/c/**'
cat > "$TMP/spec-kill" <<'K'
#!/usr/bin/env bash
n=$(( $(cat "$TMP/i2.calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$TMP/i2.calls"
[ "$n" = 3 ] && kill -TERM "$(cat "$TMP/i2.pid")"
echo 900
K
chmod +x "$TMP/spec-kill"
mkdir -p "$MI2/.prompts"; : > "$MI2/.events"; rm -f "$TMP/i2.calls" "$TMP/hang.SG-02" "$TMP/hang.SG-03"
env ORCH="$ORCH" TMP="$TMP" MEGADIR="$MI2" EVENTS="$MI2/.events" PROMPTS="$MI2/.prompts" CLAUDE_CMD="$TMP/claude" \
  SPEC_NEXT_CMD="$TMP/spec-kill" WAVE_CAP=2 WAVE_ROLLING=1 HANG_IDS="SG-02 SG-03" bash "$ORCH" run "$MI2" > "$TMP/i2.out" 2>&1 < /dev/null &
opid=$!; echo "$opid" > "$TMP/i2.pid"
k=0; while alive "$opid" && [ "$k" -lt 200 ]; do sleep 0.1; k=$((k + 1)); done
if alive "$opid"; then
  fail "(i2) the driver is still alive 20s after the abort (waiting on a session spawned after it?) timeline: $(tr '\n' ' ' < "$MI2/.events")"
  kill -TERM "$opid" 2>/dev/null; sleep 1
else
  wait "$opid" 2>/dev/null; irc=$?
  m2=""; [ -s "$TMP/hang.SG-02" ] && read -r m2 g2 < "$TMP/hang.SG-02"
  if [ "$irc" != 0 ] && ! grep -q 'start SG-03' "$MI2/.events" && [ ! -e "$TMP/hang.SG-03" ] \
     && [ -n "$m2" ] && ! alive "$m2" && ! alive "$g2" && [ "$(cat "$TMP/i2.calls")" = 3 ]; then
    pass "(i2) TERM mid refill spawn: SG-03 was never started, SG-02 killed with its grandchild, the driver exited rc $irc"
  else
    fail "(i2) rc=$irc calls=$(cat "$TMP/i2.calls" 2>/dev/null) timeline: $(tr '\n' ' ' < "$MI2/.events")"; tail -15 "$TMP/i2.out"
  fi
fi
for f in "$TMP/hang.SG-02" "$TMP/hang.SG-03"; do [ -s "$f" ] && { read -r a b < "$f"; kill -KILL "$a" "$b" 2>/dev/null; }; done

# ============ (j) rolling-only branches ============
# j1: the refill candidate is refused pre-flight (off-allowlist Model:): admission halts, SG-02 drains.
MJ1=$(mk_mega roll-j1 '- [ ] SG-01 fast , auto , PR #__
- [ ] SG-02 slow , auto , PR #__
- [ ] SG-03 bad model , auto , depends SG-01 , PR #__
- [ ] SG-04 also ready , auto , depends SG-01 , PR #__')
goal "$MJ1" SG-01 'lib/a/**'; goal "$MJ1" SG-02 'lib/b/**'; goal "$MJ1" SG-03 'lib/c/**'; goal "$MJ1" SG-04 'lib/d/**'
printf 'Model: sonet\n' >> "$MJ1/goals/03-SG-03.md"
run_case "$MJ1" "$TMP/j1.out" WAVE_CAP=2 WAVE_ROLLING=1 WAITFOR_SG_02=SG-04 WAIT_SECS=3
if [ "$RC" != 0 ] && ! grep -qE 'start SG-0[34]' "$MJ1/.events" && grep -q '^- \[x\] SG-02' "$MJ1/ROADMAP.md" \
   && grep -q 'SG-03	blocked	wave: rejected pre-flight by routing' "$MJ1/.orchestrate/events.log"; then
  pass "(j1) refill spawn refused (bad Model:): nothing else admitted, SG-02 drained, the run halted"
else
  fail "(j1) rc=$RC timeline: $(tr '\n' ' ' < "$MJ1/.events")"; tail -15 "$TMP/j1.out"
fi
# j2: a gate! becomes ready when SG-01 lands: SG-04 (also ready, a free slot) must not be admitted.
MJ2=$(mk_mega roll-j2 '- [ ] SG-01 fast , auto , PR #__
- [ ] SG-02 slow , auto , PR #__
- [ ] SG-03 review all , gate! , depends SG-01 , PR #__
- [ ] SG-04 ready too , auto , depends SG-01 , PR #__')
goal "$MJ2" SG-01 'lib/a/**'; goal "$MJ2" SG-02 'lib/b/**'; goal "$MJ2" SG-03 'lib/c/**'; goal "$MJ2" SG-04 'lib/d/**'
run_case "$MJ2" "$TMP/j2.out" WAVE_CAP=2 WAVE_ROLLING=1 MEGA_GATE_DISPATCH=0 WAITFOR_SG_02=SG-04 WAIT_SECS=3
if [ "$RC" = 0 ] && ! grep -qE 'start SG-0[34]' "$MJ2/.events" && grep -q '\[rolling\] a gate! sub-goal is ready' "$TMP/j2.out" \
   && grep -q 'STOP (gate!)' "$TMP/j2.out" && grep -q '^- \[x\] SG-02' "$MJ2/ROADMAP.md"; then
  pass "(j2) gate! became ready mid-wave: SG-04 not admitted into the free slot, SG-02 drained, the loop stopped for the human"
else
  fail "(j2) rc=$RC timeline: $(tr '\n' ' ' < "$MJ2/.events")"; tail -15 "$TMP/j2.out"
fi
# j3: WAVE_CAP=3. SG-01 lands with only SG-02 running: two slots free, three candidates. SG-03 and SG-04
# are admitted in one pass, SG-05 only when a slot frees. SG-02/SG-03 linger until SG-05 starts, so an
# overshoot shows as 4 sessions alive at once.
MJ3=$(mk_mega roll-j3 '- [ ] SG-01 fast , auto , PR #__
- [ ] SG-02 slow , auto , PR #__
- [ ] SG-03 c , auto , depends SG-01 , PR #__
- [ ] SG-04 d fast , auto , depends SG-01 , PR #__
- [ ] SG-05 e , auto , depends SG-01 , PR #__')
goal "$MJ3" SG-01 'lib/a/**'; goal "$MJ3" SG-02 'lib/b/**'; goal "$MJ3" SG-03 'lib/c/**'; goal "$MJ3" SG-04 'lib/d/**'; goal "$MJ3" SG-05 'lib/e/**'
run_case "$MJ3" "$TMP/j3.out" WAVE_CAP=3 WAVE_ROLLING=1 WAITFOR_SG_02=SG-05 WAITFOR_SG_03=SG-05 WAIT_SECS=6
peak=$(awk '/^start /{n++; if(n>m)m=n} /^end /{n--} END{print m+0}' "$MJ3/.events")
if [ "$RC" = 0 ] && [ "$(boxes "$MJ3")" = 5 ] && [ "$peak" -le 3 ] \
   && grep -q '\[rolling\] SG-03 admitted into a freed slot (still running: SG-02)' "$TMP/j3.out" \
   && grep -q '\[rolling\] SG-04 admitted into a freed slot (still running: SG-02)' "$TMP/j3.out" \
   && before "$MJ3/.events" "end SG-04" "start SG-05"; then
  pass "(j3) WAVE_CAP=3: one landing refilled two slots in one pass, SG-05 waited for a free slot, peak $peak sessions"
else
  fail "(j3) rc=$RC boxes=$(boxes "$MJ3") peak=$peak timeline: $(tr '\n' ' ' < "$MJ3/.events")"; tail -15 "$TMP/j3.out"
fi

echo "---"
[ "$fails" = 0 ] && { echo "all passed"; exit 0; } || { echo "$fails failed"; exit 1; }

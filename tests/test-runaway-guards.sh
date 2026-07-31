#!/usr/bin/env bash
# test-runaway-guards.sh -- SPEC-221 (board row ID-460), the three runaway guards on the
# autonomous run queue.
#
# All three are real bash logic, so all three are asserted directly. Nothing here is a prose
# contract. Three sections, one per mechanism, and EVERY section carries its own negative
# control (the healthy case that must NOT trip the guard):
#
#   A) the stale-window watchdog   NC: a FRESH heartbeat writes no verdict and blocks no plan
#   B) the circuit breaker         NC: a run with progress evidence resets and never trips
#   C) the dual-condition exit gate NC: a malformed EXIT_SIGNAL never yields `done`
#
# Isolation: every run points KIT_LEDGER_DIR at a temp dir, so the sidecars and the journal land
# under it and the real machine state is never read or written. The queue is driven through the
# same stub mux tests/test-queue.bats uses (MUX_CMD), so no real UI and no real `claude`.
#
# Run: bash tests/test-runaway-guards.sh   (exit 0 = all checks green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE="$KIT_DIR/lib/queue/queue.sh"
WATCH="$KIT_DIR/lib/queue/watch-board.sh"
FIX="$KIT_DIR/tests/fixtures/queue"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
assert_eq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

chmod +x "$FIX/fake-mux" 2>/dev/null || true

# ---- shared environment ------------------------------------------------------------------------
# Fast timings everywhere: no real sleeps, and a 1-second per-row ceiling so a `stalled` verdict
# takes a second rather than two hours.
WORK=""; RUNDIR=""; JOURNAL=""; QSTUB=""; QLOG=""; REPO=""
new_env() {
  WORK="$(_mk)"
  QSTUB="$WORK/stub"; mkdir -p "$QSTUB"; QLOG="$QSTUB/verbs.log"; : > "$QLOG"
  export KIT_LEDGER_DIR="$WORK/ledger"; mkdir -p "$KIT_LEDGER_DIR"
  RUNDIR="$KIT_LEDGER_DIR/queue-runs"; mkdir -p "$RUNDIR"
  JOURNAL="$WORK/queue-journal.tsv"; : > "$JOURNAL"
  # The stub mux WRAPPER (see below), not the bare fixture: the conductor deliberately deletes a
  # stale status file at launch, so a test that pre-seeds one would be seeding a file the code is
  # right to throw away. The wrapper instead runs a per-slug side-effect script DURING the run,
  # which is when a real session writes its status file.
  _write_stub_wrapper
  export MUX_CMD="$WORK/mux" TERMINAL_MUX=tmux QSTUB QLOG
  export QUEUE_JOURNAL="$JOURNAL"
  export QUEUE_POLL_SECS=1 QUEUE_TIMEOUT_SECS=1 QUEUE_RETRY_SLEEP_SECS=0
  export QUEUE_STARTUP_SECS=0 QUEUE_SUBMIT_SETTLE_SECS=0
  unset QUEUE_BEAT_STALE_SECS QUEUE_BEAT_DEAD_SECS QUEUE_MAX_STALLS \
        QUEUE_COOLDOWN_SECS QUEUE_NOPROGRESS_TRIP QUEUE_SAMEERROR_TRIP 2>/dev/null || true
}

# A thin wrapper over the shipped fixture stub. On capture-pane it first sources
# $QSTUB/<slug>.during (if present), which is how a test simulates the SESSION acting: writing its
# status file, or touching a file in the repo. The shipped fixture is left untouched.
_write_stub_wrapper() {
  cat > "$WORK/mux" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = capture-pane ]; then
  for a in "\$@"; do case "\$a" in *:*) s="\${a##*:}" ;; esac; done
  [ -n "\${s:-}" ] && [ -f "\$QSTUB/\$s.during" ] && . "\$QSTUB/\$s.during"
fi
exec "$FIX/fake-mux" "\$@"
EOF
  chmod +x "$WORK/mux"
}

# during <slug> <shell-snippet> -- what the simulated session does while the conductor polls.
during() { printf '%s\n' "$2" > "$QSTUB/$1.during"; }
# status_during <slug> <status-body> -- the common case: the run writes its own status file.
status_during() {
  printf '%b' "$2" > "$QSTUB/$1.status-src"
  during "$1" "cp \"\$QSTUB/$1.status-src\" \"\$KIT_LEDGER_DIR/queue-runs/$1.status\""
}

mkrepo() {  # dir -> a clean git repo on default branch `main`
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester
  echo x > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm init
}
seed_transcript() { printf '%s\n' "$2" > "$QSTUB/$1.transcript"; }
jverdict() { awk -F'\t' -v s="$1" '$2==s {v=$3} END{print v}' "$JOURNAL"; }
jreason()  { awk -F'\t' -v s="$1" '$2==s {v=$4} END{print v}' "$JOURNAL"; }
jrows()    { awk -F'\t' -v s="$1" '$2==s {n++} END{print n+0}' "$JOURNAL"; }
guard()    { awk -F= -v k="$2" '$1==k {v=substr($0,length(k)+2)} END{print v}' "$RUNDIR/$1.guard" 2>/dev/null; }
# A counter as the CODE reads it: an absent key is zero. A freeze deliberately writes nothing, so
# asserting on the raw file would demand a key the design never sets.
guard_num() { local v; v="$(guard "$1" "$2")"; case "$v" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac; }

# Run one row through the queue.
run_row() {  # slug repo pointer
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$WORK/q.tsv"
  bash "$QUEUE" run "$WORK/q.tsv" 2>&1
}

# ---- fixture board for the watcher half --------------------------------------------------------
BOARD_REPO=""
new_board_repo() {
  local base; base="$(_mk)"
  BOARD_REPO="$base/fixboard"
  mkdir -p "$BOARD_REPO/_meta/megagoals/pilot"
  printf 'pointer body\n' > "$BOARD_REPO/_meta/megagoals/pilot/POINTER_PROMPT.md"
  cat > "$BOARD_REPO/_meta/BACKLOG.md" <<'EOF'
# Backlog

| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | auto + pointer | pilot row #auto #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |
EOF
}
watch() {  # extra args
  WATCH_QUEUE_CMD="true" bash "$WATCH" --board "$BOARD_REPO/_meta/BACKLOG.md" \
    --repo-root "$BOARD_REPO" --repo-name fixboard --journal "$JOURNAL" "$@" 2>&1
}

echo "=== SPEC-221 runaway guards ==="
echo
echo "--- Section A: the stale-window watchdog ---"

# A1 the conductor beats while it runs, and clears the beat when the run ends.
new_env; REPO="$WORK/r1"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
seed_transcript a1 "  RUNNER_DONE"
run_row a1 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "A1: a completed run journals done" "$(jverdict a1)" "done"
[ ! -f "$RUNDIR/a1.beat" ]
assert "A1: a terminal verdict clears the beat (no leaked in-flight claim)" $?

# A2 NEGATIVE CONTROL: a FRESH beat is left completely alone. No verdict, and the slug is not
# planned (a second window for a live run is the thing this prevents).
new_env; new_board_repo
: > "$RUNDIR/fixboard__ID-001.beat"          # mtime = now => fresh
OUT="$(watch)"
assert_eq "A2 NC: a fresh beat writes NO journal row" "$(jrows fixboard__ID-001)" "0"
case "$OUT" in *"a run is in flight"*) R=0 ;; *) R=1 ;; esac
assert "A2 NC: a fresh beat blocks the plan (in-flight claim)" $R "-- got: $OUT"
case "$OUT" in *"0 rows to enqueue"*) R=0 ;; *) R=1 ;; esac
assert "A2 NC: nothing is enqueued while a run is in flight" $R

# A3 a beat between STALE and DEAD warns but writes nothing (the conductor may be merely paused).
new_env; new_board_repo
: > "$RUNDIR/fixboard__ID-001.beat"
OUT="$(QUEUE_BEAT_STALE_SECS=0 QUEUE_BEAT_DEAD_SECS=9999 watch)"
assert_eq "A3: a stale-but-not-dead beat writes NO verdict" "$(jrows fixboard__ID-001)" "0"
case "$OUT" in *"orphan: fixboard__ID-001"*) R=0 ;; *) R=1 ;; esac
assert "A3: a stale-but-not-dead beat warns about the orphan" $R "-- got: $OUT"

# A4 a DEAD beat writes `stalled` plus a jittered retry_after. This is the gap the row named:
# before this, a dead conductor left no verdict at all. `dead` is forced by zeroing the two
# thresholds; the defaults (600/3600) are asserted for their arithmetic in A5, not by waiting.
new_env; new_board_repo
export QUEUE_BEAT_STALE_SECS=0 QUEUE_BEAT_DEAD_SECS=0
: > "$RUNDIR/fixboard__ID-001.beat"
NOW="$(date +%s)"
watch --apply >/dev/null
assert_eq "A4: a dead beat writes a stalled verdict" "$(jverdict fixboard__ID-001)" "stalled"
assert_eq "A4: the stall counter incremented" "$(guard fixboard__ID-001 stalls)" "1"
[ ! -f "$RUNDIR/fixboard__ID-001.beat" ]
assert "A4: the reaper clears the beat it consumed" $?

# A5 the retry_after lands inside the 5..15 minute jitter window. Asserted as a RANGE, never as a
# value: the jitter is the feature (one sleeping host stalls many rows at once).
RA="$(guard fixboard__ID-001 retry_after)"
LO=$((NOW + 300)); HI=$((NOW + 900 + 5))
{ [ -n "$RA" ] && [ "$RA" -ge "$LO" ] && [ "$RA" -le "$HI" ]; }
assert "A5: retry_after is inside now+5min .. now+15min" $? "-- got $RA, window $LO..$HI"

# A6 a slug inside its retry_after is not planned.
OUT="$(watch)"
case "$OUT" in *"backing off until"*) R=0 ;; *) R=1 ;; esac
assert "A6: a slug inside its backoff is skipped" $R "-- got: $OUT"

# A7 the third stall writes an EMPTY retry_after, and that empty field IS the quarantine.
new_env; new_board_repo
export QUEUE_BEAT_STALE_SECS=0 QUEUE_BEAT_DEAD_SECS=0
for i in 1 2 3; do
  : > "$RUNDIR/fixboard__ID-001.beat"
  watch >/dev/null
done
assert_eq "A7: three dead beats accumulate three stalls" "$(guard fixboard__ID-001 stalls)" "3"
# Guarded against a false pass: the guard FILE must exist, or an empty read would look like
# quarantine for a slug that simply never ran.
[ -f "$RUNDIR/fixboard__ID-001.guard" ]
assert "A7: the guard file exists (so the empty read below is real)" $?
assert_eq "A7: the third stall writes an EMPTY retry_after (quarantine)" "$(guard fixboard__ID-001 retry_after)" ""
OUT="$(watch)"
case "$OUT" in *quarantined*) R=0 ;; *) R=1 ;; esac
assert "A7: a quarantined slug is never planned again" $R "-- got: $OUT"

# A8 a dead beat whose run DID finish is honored, not relabelled. Real finished work must not be
# thrown away just because its conductor died before it could journal.
new_env; new_board_repo
export QUEUE_BEAT_STALE_SECS=0 QUEUE_BEAT_DEAD_SECS=0
: > "$RUNDIR/fixboard__ID-001.beat"
printf 'EXIT_SIGNAL: true\n' > "$RUNDIR/fixboard__ID-001.status"
watch >/dev/null
assert_eq "A8: a dead beat with EXIT_SIGNAL true journals done, not stalled" "$(jverdict fixboard__ID-001)" "done"

# A9 a slug carrying a path separator is refused before any sidecar file is opened.
new_env
bash -c '. "'"$QUEUE"'" >/dev/null 2>&1; _run_file "evil/../../etc/x" beat' >/dev/null 2>&1
[ $? -ne 0 ]
assert "A9: a slug containing a path separator is refused a sidecar path" $?

echo
echo "--- Section B: the circuit breaker ---"

# B1 three consecutive no-progress runs trip the breaker to `error` reason stagnation_detected.
new_env; REPO="$WORK/rb"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
export QUEUE_NOPROGRESS_TRIP=3
for i in 1 2 3; do run_row b1 "$REPO" "$WORK/p.txt" >/dev/null; done   # no transcript -> stalled
assert_eq "B1: the third no-progress run trips to error" "$(jverdict b1)" "error"
assert_eq "B1: the trip names stagnation_detected" "$(jreason b1)" "stagnation_detected"

# B2 the trip opens a cooldown, and a slug inside it is not planned.
CU="$(guard b1 cooldown_until)"
{ [ -n "$CU" ] && [ "$CU" -gt "$(date +%s)" ]; }
assert "B2: the trip sets a future cooldown_until" $? "-- got $CU"
new_board_repo
# ONLY the cooldown key: copying b1's whole guard would carry its stall count too, and quarantine
# is checked before cooldown, so the test would pass for the wrong reason.
printf 'cooldown_until=%s\n' "$CU" > "$RUNDIR/fixboard__ID-001.guard"
OUT="$(watch)"
case "$OUT" in *"breaker cooldown until"*) R=0 ;; *) R=1 ;; esac
assert "B2: a slug inside its breaker cooldown is skipped" $R "-- got: $OUT"

# B3 NEGATIVE CONTROL, hatch 2: a run that self-reports files changed resets the counters and
# never trips, however many times it comes back non-terminal.
new_env; REPO="$WORK/rb3"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
export QUEUE_NOPROGRESS_TRIP=3
status_during b3 'EXIT_SIGNAL: false\nFILES_CHANGED: 3\n'
for i in 1 2 3 4; do run_row b3 "$REPO" "$WORK/p.txt" >/dev/null; done
assert_eq "B3 NC: a run reporting FILES_CHANGED never trips the breaker" "$(jverdict b3)" "stalled"
assert_eq "B3 NC: its no-progress counter stayed at zero" "$(guard_num b3 noprogress)" "0"

# B7 THE ANTI-SELF-ATTESTATION RULE (security + architecture review, HIGH). A self-report calms
# the BREAKER, but it must never clear the STALL ladder. Otherwise a run that writes
# `FILES_CHANGED: 1` on every attempt is permanently exempt from quarantine, which is the one
# promise this whole feature exists to keep. Same scenario as B3, asserting the OTHER axis.
assert_eq "B7: a self-reporting run STILL climbs the stall ladder" "$(guard_num b3 stalls)" "4"
new_env; new_board_repo
export QUEUE_BEAT_STALE_SECS=0 QUEUE_BEAT_DEAD_SECS=0
for i in 1 2 3; do
  : > "$RUNDIR/fixboard__ID-001.beat"
  printf 'EXIT_SIGNAL: false\nFILES_CHANGED: 9\nQUESTION: true\n' > "$RUNDIR/fixboard__ID-001.status"
  watch >/dev/null
done
assert_eq "B7: a self-reporting run is quarantined on the third stall anyway" \
  "$(guard fixboard__ID-001 retry_after)" ""
OUT="$(watch)"
case "$OUT" in *quarantined*) R=0 ;; *) R=1 ;; esac
assert "B7: self-attested progress cannot buy an exemption from quarantine" $R "-- got: $OUT"

# B8 the other half of the split: VERIFIED evidence (a real repo delta) DOES clear the stall
# ladder, so a genuinely productive-but-slow row still escapes quarantine.
new_env; REPO="$WORK/rb8"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
run_row b8 "$REPO" "$WORK/p.txt" >/dev/null                 # no evidence -> stalls climbs
assert_eq "B8: a no-evidence run climbs the ladder" "$(guard_num b8 stalls)" "1"
during b8 "echo real-work >> \"$REPO/f\""                    # now the session touches the repo
run_row b8 "$REPO" "$WORK/p.txt" >/dev/null
git -C "$REPO" checkout -q -- f
assert_eq "B8: a VERIFIED repo delta resets the stall ladder to zero" "$(guard_num b8 stalls)" "0"
assert_eq "B8: and clears the backoff alarm" "$(guard b8 retry_after)" ""

# B4 NEGATIVE CONTROL, hatch 1: a run that actually touches the repo is progress. The session
# dirties the tree DURING the run, which is the only moment hatch 1 can observe (a repo already
# dirty at launch is skipped by the shipped preflight and never reaches the breaker).
new_env; REPO="$WORK/rb4"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
export QUEUE_NOPROGRESS_TRIP=2
during b4 "echo real-work >> \"$REPO/f\""
for i in 1 2 3; do
  run_row b4 "$REPO" "$WORK/p.txt" >/dev/null
  git -C "$REPO" checkout -q -- f     # the operator/session commits or reverts between rows
done
assert_eq "B4 NC: a run that touched the repo never trips" "$(jverdict b4)" "stalled"
assert_eq "B4 NC: its no-progress counter stayed at zero" "$(guard_num b4 noprogress)" "0"

# B5 hatch 4: a run that stopped to ASK freezes the counters. Counting a question as stagnation
# would quarantine exactly the rows most worth a human's attention.
new_env; REPO="$WORK/rb5"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
export QUEUE_NOPROGRESS_TRIP=2
status_during b5 'EXIT_SIGNAL: false\nQUESTION: true\n'
for i in 1 2 3; do run_row b5 "$REPO" "$WORK/p.txt" >/dev/null; done
assert_eq "B5: a question freezes the counters, no trip" "$(jverdict b5)" "stalled"
assert_eq "B5: the no-progress counter never advanced" "$(guard_num b5 noprogress)" "0"

# B6 the breaker never rewrites a TERMINAL verdict. An investigate-and-report row changes no
# files and must not be called stagnation for it.
new_env; REPO="$WORK/rb6"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
export QUEUE_NOPROGRESS_TRIP=1
seed_transcript b6 "  RUNNER_DONE"
run_row b6 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "B6: a done run is never rewritten to error" "$(jverdict b6)" "done"

echo
echo "--- Section C: the dual-condition exit gate ---"

# C1 an explicit EXIT_SIGNAL true ends the run `done` with a completely EMPTY pane. The explicit
# channel does not need prose to agree with it.
new_env; REPO="$WORK/rc1"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
status_during c1 'EXIT_SIGNAL: true\n'
run_row c1 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "C1: explicit EXIT_SIGNAL true yields done with no pane marker" "$(jverdict c1)" "done"

# C2 a REASON alongside an explicit completion maps onto the journal's existing `gated`.
new_env; REPO="$WORK/rc2"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
status_during c2 'EXIT_SIGNAL: true\nREASON: needs a human\n'
run_row c2 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "C2: EXIT_SIGNAL true + REASON yields gated" "$(jverdict c2)" "gated"
assert_eq "C2: the reason is carried through" "$(jreason c2)" "needs a human"

# C3 THE ANTI-FALSE-COMPLETION RULE: an explicit `false` outranks a pane that says RUNNER_DONE.
new_env; REPO="$WORK/rc3"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
seed_transcript c3 "  RUNNER_DONE"
status_during c3 'EXIT_SIGNAL: false\n'
run_row c3 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "C3: explicit false beats a RUNNER_DONE pane (never done)" "$(jverdict c3)" "stalled"

# C4 NEGATIVE CONTROL: a malformed status file is NEVER a completion, even against a done pane.
new_env; REPO="$WORK/rc4"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
seed_transcript c4 "  RUNNER_DONE"
status_during c4 'EXIT_SIGNAL: mayb\ngarbage\n'
run_row c4 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "C4 NC: a malformed EXIT_SIGNAL never yields done" "$(jverdict c4)" "stalled"
assert_eq "C4 NC: the verdict names the malformed signal" "$(jreason c4)" "malformed_exit_signal"

# C5 BACKWARD COMPATIBILITY: with no status file at all the shipped pane path is untouched.
new_env; REPO="$WORK/rc5"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
seed_transcript c5 "  RUNNER_DONE"
run_row c5 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "C5: no status file -> the pane marker still yields done" "$(jverdict c5)" "done"

# C6 the run is TOLD where to write its signal, otherwise the contract is dead code.
new_env; REPO="$WORK/rc6"; mkrepo "$REPO"; echo "p" > "$WORK/p.txt"
seed_transcript c6 "  RUNNER_DONE"
run_row c6 "$REPO" "$WORK/p.txt" >/dev/null
grep -q "EXIT_SIGNAL: true" "$QLOG"
assert "C6: the typed /goal line names the EXIT_SIGNAL contract" $?
grep -q "c6.status" "$QLOG"
assert "C6: the typed /goal line names the slug's status path" $?

echo
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

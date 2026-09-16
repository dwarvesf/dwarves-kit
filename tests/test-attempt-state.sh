#!/usr/bin/env bash
# Contract tests for lib/goal/attempt-state.sh, the dispatch Attempt state machine.
#
# Why this suite exists: the kit read worker silence as FAILED and re-dispatched. A
# resumed agent and its replacement could then both land the same work. The machine
# under test separates the TASK state from the ATTEMPT state, holds a disconnected
# attempt in a grace window, and makes result commit idempotent on the task id.
#
# The clock is pinned through ATTEMPT_NOW so grace expiry is tested without sleeping.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AS="$KIT_DIR/lib/goal/attempt-state.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ATTEMPT_REGISTRY_DIR="$TMP/store"

# Run the machine with a pinned clock. Usage: at <epoch> <verb> ...
at() { local now="$1"; shift; ATTEMPT_NOW="$now" bash "$AS" "$@"; }

# Capture status into a variable and match with `case`. A `| grep -q` here would
# kill the producer with SIGPIPE, and under `set -o pipefail` a MATCHING grep then
# still reports non-zero. Three cases failed that way before this note existed.
status_of() {  # <epoch> <task> -> the whole status block
  at "$1" status "$2" 2>/dev/null
}
has() {  # <text> <substring>
  case "$1" in *"$2"*) return 0;; esac
  return 1
}

state_of() {  # <task> -> the task state
  at 1000 status "$1" 2>/dev/null | awk -F'state=' '/^task=/ {print $2; exit}'
}
attempt_state() {  # <task> <attempt> -> that attempt's state
  at 1000 status "$1" 2>/dev/null \
    | awk -v a="attempt=$2" '$1==a { for (i=1;i<=NF;i++) if ($i ~ /^state=/) { sub(/^state=/,"",$i); print $i; exit } }'
}

# ---- 1. every legal transition, walked end to end ----
# queued -> dispatched -> (running -> disconnected -> running) -> committed -> done
at 1000 dispatch t-legal w1 a1 >/dev/null 2>&1
ok=1
[ "$(state_of t-legal)" = dispatched ] || ok=0
[ "$(attempt_state t-legal a1)" = running ] || ok=0
at 1000 mark-disconnected t-legal --grace 60 >/dev/null 2>&1 || ok=0
[ "$(attempt_state t-legal a1)" = disconnected ] || ok=0
[ "$(state_of t-legal)" = dispatched ] || ok=0   # the TASK never left dispatched
at 1010 resume t-legal >/dev/null 2>&1 || ok=0
[ "$(attempt_state t-legal a1)" = running ] || ok=0
at 1020 commit-result t-legal a1 sha-abc >/dev/null 2>&1 || ok=0
[ "$(state_of t-legal)" = done ] || ok=0
[ "$(attempt_state t-legal a1)" = committed ] || ok=0
if [ "$ok" = 1 ]; then
  pass "the legal walk runs: dispatch, disconnect, resume, commit, and the task stays dispatched throughout"
else
  fail "the legal walk broke; status was: $(at 1000 status t-legal 2>&1 | tr '\n' ' ')"
fi

# The other legal task leg: dispatched -> queued via a lost attempt (case 5 below)
# and dispatched -> lost via abandon.
at 2000 dispatch t-abandon w1 a1 >/dev/null 2>&1
if at 2000 abandon t-abandon "no worker left" >/dev/null 2>&1 && [ "$(state_of t-abandon)" = lost ]; then
  pass "abandon takes the task to lost"
else
  fail "abandon should take the task to lost, got: $(state_of t-abandon)"
fi

# ---- 2. illegal: commit on a task already done (task done -> done is refused as a no-op path) ----
# A terminal attempt cannot move again.
at 3000 dispatch t-illegal1 w1 a1 >/dev/null 2>&1
at 3000 commit-result t-illegal1 a1 sha-1 >/dev/null 2>&1
out=$(at 3000 resume t-illegal1 a1 2>&1)
case "$out" in
  *"illegal attempt transition committed -> running"*) pass "illegal: committed -> running refused" ;;
  *) fail "committed -> running should be refused, got: $out" ;;
esac

# ---- 3. illegal: resume an attempt that never disconnected ----
at 3100 dispatch t-illegal2 w1 a1 >/dev/null 2>&1
at 3100 mark-disconnected t-illegal2 --grace 10 >/dev/null 2>&1
at 3200 lose-attempt t-illegal2 >/dev/null 2>&1      # grace expired, now lost
out=$(at 3200 resume t-illegal2 a1 2>&1)
case "$out" in
  *"illegal attempt transition lost -> running"*) pass "illegal: lost -> running refused" ;;
  *) fail "lost -> running should be refused, got: $out" ;;
esac

# ---- 4. illegal: a second dispatch while an attempt is live ----
# This is the duplicate-work bug in one command. It must be refused outright.
at 3300 dispatch t-illegal3 w1 a1 >/dev/null 2>&1
at 3300 mark-disconnected t-illegal3 --grace 300 >/dev/null 2>&1
out=$(at 3310 dispatch t-illegal3 w2 a2 2>&1)
case "$out" in
  *"already has a live attempt"*) pass "illegal: a second dispatch inside the grace window is refused" ;;
  *) fail "a second dispatch during grace should be refused, got: $out" ;;
esac

# ---- 5. grace NOT expired -> lose-attempt refused ----
at 4000 dispatch t-grace w1 a1 >/dev/null 2>&1
at 4000 mark-disconnected t-grace --grace 120 >/dev/null 2>&1
out=$(at 4060 lose-attempt t-grace 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && [ "$(attempt_state t-grace a1)" = disconnected ]; then
  case "$out" in
    *"grace window has 60s left"*) pass "grace not expired: lose-attempt refused and names the remaining time" ;;
    *) fail "refusal should name the remaining grace, got: $out" ;;
  esac
else
  fail "lose-attempt inside the window should refuse and leave the attempt disconnected (rc=$rc)"
fi

# ---- 6. grace expired -> lose-attempt allowed, worker excluded, task freed ----
out=$(at 4121 lose-attempt t-grace 2>&1)
ok=1
[ "$(attempt_state t-grace a1)" = lost ] || ok=0
[ "$(state_of t-grace)" = queued ] || ok=0
has "$(status_of 4121 t-grace)" 'excluded=w1' || ok=0
if [ "$ok" = 1 ]; then
  pass "grace expired: attempt lost, task freed to queued, worker excluded"
else
  fail "grace expiry path wrong: $(at 4121 status t-grace 2>&1 | tr '\n' ' ') / $out"
fi

# The exclusion is enforced, not just recorded.
out=$(at 4130 dispatch t-grace w1 a2 2>&1)
case "$out" in
  *"is excluded from task"*) pass "an excluded worker cannot be re-dispatched the same task" ;;
  *) fail "re-dispatch to the excluded worker should be refused, got: $out" ;;
esac
# A different worker can take it.
if at 4140 dispatch t-grace w2 a2 >/dev/null 2>&1 && [ "$(state_of t-grace)" = dispatched ]; then
  pass "a different worker picks the freed task back up"
else
  fail "a non-excluded worker should be able to take the freed task"
fi

# ---- 7. commit-result twice -> the second is a no-op naming the first attempt ----
at 5000 dispatch t-once w1 a1 >/dev/null 2>&1
at 5000 commit-result t-once a1 sha-first >/dev/null 2>&1
out=$(at 5010 commit-result t-once a1 sha-second 2>&1)
rc=$?
ok=1
[ "$rc" -eq 0 ] || ok=0                                        # a no-op, not an error
case "$out" in *"NOOP"*"attempt=a1"*) : ;; *) ok=0 ;; esac      # names the winner
has "$(status_of 5010 t-once)" 'ref=sha-first' || ok=0   # first ref survives
if [ "$ok" = 1 ]; then
  pass "a second commit for the same task is a no-op that names the winning attempt"
else
  fail "second commit wrong (rc=$rc): $out / $(at 5010 status t-once 2>&1 | tr '\n' ' ')"
fi

# ---- 8. resume inside the window, then a late replacement: exactly ONE committed result ----
# The whole incident, replayed. The worker drops; the lead waits instead of
# re-dispatching; the worker comes back and commits; a late replacement attempt
# reports afterwards and must be superseded, not committed.
at 6000 dispatch t-race w1 a1 >/dev/null 2>&1
at 6000 mark-disconnected t-race --grace 120 >/dev/null 2>&1
at 6030 resume t-race a1 >/dev/null 2>&1
at 6040 commit-result t-race a1 sha-real >/dev/null 2>&1
# A replacement that a careless lead had already started reports late. It is not
# in the record, so it cannot even be named: the machine refuses to know it.
out=$(at 6050 commit-result t-race a-ghost sha-dup 2>&1)
case "$out" in
  *"unknown attempt 'a-ghost'"*) : ;;
  *) fail "an unrecorded replacement should be refused, got: $out" ;;
esac
race_status="$(status_of 6060 t-race)"
committed=$(printf '%s\n' "$race_status" | grep -c 'state=committed')
ok=1
[ "$committed" -eq 1 ] || ok=0
has "$race_status" 'ref=sha-real' || ok=0
[ "$(state_of t-race)" = done ] || ok=0
if [ "$ok" = 1 ]; then
  pass "resume inside the window then a late replacement: exactly one committed result, the real one"
else
  fail "race produced $committed committed attempts: $(at 6060 status t-race 2>&1 | tr '\n' ' ')"
fi

# A RECORDED sibling that reports late is superseded, never a second commit.
at 7000 dispatch t-sib w1 a1 >/dev/null 2>&1
at 7000 commit-result t-sib a1 sha-win >/dev/null 2>&1
# Forge a second recorded attempt the way a duplicate dispatch would have.
printf 'attempt|a2|w2|running|\n' >> "$ATTEMPT_REGISTRY_DIR/t-sib.task"
at 7010 commit-result t-sib a2 sha-lose >/dev/null 2>&1
if [ "$(attempt_state t-sib a2)" = superseded ] && [ "$(attempt_state t-sib a1)" = committed ]; then
  pass "a recorded sibling committing late is superseded, the first commit stands"
else
  fail "sibling should be superseded: $(at 7010 status t-sib 2>&1 | tr '\n' ' ')"
fi

# ---- 9. status reports the grace remaining ----
at 8000 dispatch t-status w1 a1 >/dev/null 2>&1
at 8000 mark-disconnected t-status --grace 90 >/dev/null 2>&1
if has "$(status_of 8030 t-status)" 'grace=60s'; then
  pass "status reports the grace remaining"
else
  fail "status should report grace=60s, got: $(at 8030 status t-status 2>&1 | tr '\n' ' ')"
fi
if has "$(status_of 8200 t-status)" 'grace=expired'; then
  pass "status reports an expired grace window"
else
  fail "status should report grace=expired, got: $(at 8200 status t-status 2>&1 | tr '\n' ' ')"
fi

# ---- 10. the grace window is a flag, not a hardcoded constant ----
at 9000 dispatch t-flag w1 a1 >/dev/null 2>&1
at 9000 mark-disconnected t-flag --grace 5 >/dev/null 2>&1
if at 9006 lose-attempt t-flag >/dev/null 2>&1; then
  pass "--grace sets the window (5s expired at +6s)"
else
  fail "--grace 5 should have expired by +6s"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "test-attempt-state: all cases passed"
else
  echo "test-attempt-state: $FAILED case(s) failed"
fi
exit "$FAILED"

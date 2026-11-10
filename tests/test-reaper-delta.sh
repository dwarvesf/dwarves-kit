#!/usr/bin/env bash
# test-reaper-delta.sh -- a dead beat can reach `done`: the stale-window reaper (watch-board.sh) reuses
# the conductor's `_run_delta`. A dead beat whose run wrote EXIT_SIGNAL: true AND left a real delta
# (HEAD or a branch tip moved, or a PR was opened) since the window opened records `done`; every other
# dead beat keeps today's verdict. The conductor records the launch snapshot the reaper needs
# (`<slug>.launch`), and the reaper checks protected paths itself (fail closed).
#
# Isolation: KIT_LEDGER_DIR points at a temp dir, so journal and sidecars never touch machine state.
#
# Run: bash tests/test-reaper-delta.sh   (exit 0 = all checks green)

set -uo pipefail
# Fence off the host operator kit.toml: a real operator file must not change what this suite asserts.
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE="$KIT_DIR/lib/queue/queue.sh"
WATCH="$KIT_DIR/lib/queue/watch-board.sh"
FIX="$KIT_DIR/tests/fixtures/queue"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
assert_eq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

TMPS=()
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

chmod +x "$FIX/fake-mux" 2>/dev/null || true

WORK=""; RUNDIR=""; JOURNAL=""; QSTUB=""; QLOG=""; REPO=""
new_env() {
  WORK="$(_mk)"
  QSTUB="$WORK/stub"; mkdir -p "$QSTUB"; QLOG="$QSTUB/verbs.log"; : > "$QLOG"
  export KIT_LEDGER_DIR="$WORK/ledger"; mkdir -p "$KIT_LEDGER_DIR"
  RUNDIR="$KIT_LEDGER_DIR/queue-runs"; mkdir -p "$RUNDIR"
  JOURNAL="$WORK/queue-journal.tsv"; : > "$JOURNAL"
  export MUX_CMD="$FIX/fake-mux" TERMINAL_MUX=tmux QSTUB QLOG
  export QUEUE_JOURNAL="$JOURNAL"
  export QUEUE_POLL_SECS=0 QUEUE_TIMEOUT_SECS=1 QUEUE_RETRY_SLEEP_SECS=0
  export QUEUE_STARTUP_SECS=0 QUEUE_SUBMIT_SETTLE_SECS=0
  unset QUEUE_BEAT_STALE_SECS QUEUE_BEAT_DEAD_SECS QUEUE_MAX_STALLS QUEUE_COOLDOWN_SECS \
        QUEUE_NOPROGRESS_TRIP QUEUE_SAMEERROR_TRIP 2>/dev/null || true
}

# A clean git repo whose committed board carries ID-001 and ID-002, both queued.
mkrepo() {  # dir
  local d="$1"; mkdir -p "$d/_meta"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester
  cat > "$d/_meta/BACKLOG.md" <<'EOF'
# Backlog

| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | first row | a note | queued |
| ID-002 | second row | a note | queued |
EOF
  echo x > "$d/f"; git -C "$d" add -A; git -C "$d" commit -qm init
}
seed_transcript() { printf '%s\n' "$2" > "$QSTUB/$1.transcript"; }
seed_work() { : > "$QSTUB/$1.work"; }
jverdict() { awk -F'\t' -v s="$1" '$2==s {v=$3} END{print v}' "$JOURNAL"; }
jreason()  { awk -F'\t' -v s="$1" '$2==s {v=$4} END{print v}' "$JOURNAL"; }
jrows()    { awk -F'\t' -v s="$1" '$2==s {n++} END{print n+0}' "$JOURNAL"; }
# The full status cell of a board row (the last cell), e.g. "executing [queue ...]".
rowstatus() {  # repo id
  BACKLOG_FILE="$1/_meta/BACKLOG.md" bash "$KIT_DIR/lib/board/backlog.sh" get "$2" 2>&1
}
lead() { local s; s="$(rowstatus "$1" "$2")"; printf '%s' "${s%%[ \[(]*}"; }

run_rows() {  # tsv-file [extra flags...]
  local tsv="$1"; shift
  bash "$QUEUE" run "$tsv" "$@" 2>&1
}
one_row() {  # slug repo pointer -> tsv path
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$WORK/q.tsv"; printf '%s' "$WORK/q.tsv"
}

echo "=== reaper delta ==="

# A fixture board for the watcher half (the reaper runs before any planning).
BOARD_REPO=""
new_board_repo() {
  local base; base="$(_mk)"
  BOARD_REPO="$base/fixrepo"; mkrepo "$BOARD_REPO"
  mkdir -p "$BOARD_REPO/_meta/megagoals/pilot"
  printf 'pointer body\n' > "$BOARD_REPO/_meta/megagoals/pilot/POINTER_PROMPT.md"
  git -C "$BOARD_REPO" add -A; git -C "$BOARD_REPO" commit -qm "chore: pointer"
}
watch() {
  WATCH_QUEUE_CMD="true" bash "$WATCH" --board "$BOARD_REPO/_meta/BACKLOG.md" \
    --repo-root "$BOARD_REPO" --repo-name fixrepo --journal "$JOURNAL" "$@" 2>&1
}
# snapshot <slug> <repo>: what the conductor records at launch, written by the conductor's own helper.
snapshot() {
  ( . "$QUEUE" >/dev/null 2>&1
    _launch_snapshot_write "$1" "$2" "$(git -C "$2" rev-parse HEAD)" "$(_branch_tips "$2")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" )
}
dead_beat() { : > "$RUNDIR/$1.beat"; export QUEUE_BEAT_STALE_SECS=0 QUEUE_BEAT_DEAD_SECS=0; }

# R1 the headline: a dead beat, EXIT_SIGNAL true, a real delta -> done, and the board row follows.
new_env; new_board_repo; S=fixrepo__ID-001
snapshot "$S" "$BOARD_REPO"
git -C "$BOARD_REPO" commit -q --allow-empty -m "feat: the run's work"
dead_beat "$S"; printf 'EXIT_SIGNAL: true\n' > "$RUNDIR/$S.status"
OUT="$(watch)"
assert_eq "R1: dead beat + EXIT_SIGNAL true + real delta journals done" "$(jverdict $S)" "done"
assert_eq "R1: the board row follows to executing" "$(lead "$BOARD_REPO" ID-001)" "executing"
[ ! -f "$RUNDIR/$S.beat" ] && [ ! -f "$RUNDIR/$S.launch" ]
assert "R1: the reaper clears the beat and the launch record" $?

# R2 NEGATIVE CONTROL: the same dead beat with NO delta keeps today's verdict.
new_env; new_board_repo; S=fixrepo__ID-001
snapshot "$S" "$BOARD_REPO"
dead_beat "$S"; printf 'EXIT_SIGNAL: true\n' > "$RUNDIR/$S.status"
OUT="$(watch)"
assert_eq "R2 NC: EXIT_SIGNAL true with no delta stays gated" "$(jverdict $S)" "gated"
assert_eq "R2 NC: reason stays unverified" "$(jreason $S | cut -c1-10)" "unverified"
assert_eq "R2 NC: a gated reap parks the row" "$(lead "$BOARD_REPO" ID-001)" "parked"

# R3 NEGATIVE CONTROL: EXIT_SIGNAL true, a delta, but NO launch record (a pre-upgrade run): today's gated.
new_env; new_board_repo; S=fixrepo__ID-001
git -C "$BOARD_REPO" commit -q --allow-empty -m "feat: the run's work"
dead_beat "$S"; printf 'EXIT_SIGNAL: true\n' > "$RUNDIR/$S.status"
OUT="$(watch)"
assert_eq "R3 NC: no launch record, no verification: gated" "$(jverdict $S)" "gated"
assert_eq "R3 NC: reason stays unverified" "$(jreason $S | cut -c1-10)" "unverified"

# R4 NEGATIVE CONTROL: a REASON beside the completion still means a human looks, delta or not.
new_env; new_board_repo; S=fixrepo__ID-001
snapshot "$S" "$BOARD_REPO"
git -C "$BOARD_REPO" commit -q --allow-empty -m "feat: the run's work"
dead_beat "$S"; printf 'EXIT_SIGNAL: true\nREASON: needs a look\n' > "$RUNDIR/$S.status"
OUT="$(watch)"
assert_eq "R4 NC: EXIT_SIGNAL true + REASON stays gated" "$(jverdict $S)" "gated"
assert_eq "R4 NC: the run's own reason is kept" "$(jreason $S)" "needs a look"

# R5 NEGATIVE CONTROL: a dead beat WITHOUT EXIT_SIGNAL stays stalled even with a delta, and climbs the ladder.
new_env; new_board_repo; S=fixrepo__ID-001
snapshot "$S" "$BOARD_REPO"
git -C "$BOARD_REPO" commit -q --allow-empty -m "feat: the run's work"
dead_beat "$S"
OUT="$(watch)"
assert_eq "R5 NC: no EXIT_SIGNAL -> stalled" "$(jverdict $S)" "stalled"
assert_eq "R5 NC: the stall ladder still climbs" "$(awk -F= '$1=="stalls"{print $2}' "$RUNDIR/$S.guard")" "1"
assert_eq "R5 NC: a stalled reap leaves the row queued" "$(lead "$BOARD_REPO" ID-001)" "queued"

# R6 the fail-closed rule: a delta that wrote a protected path is gated, never done.
new_env; new_board_repo; S=fixrepo__ID-001
snapshot "$S" "$BOARD_REPO"
echo "x" > "$BOARD_REPO/CLAUDE.md"; git -C "$BOARD_REPO" add CLAUDE.md; git -C "$BOARD_REPO" commit -qm "feat: touches a protected path"
dead_beat "$S"; printf 'EXIT_SIGNAL: true\n' > "$RUNDIR/$S.status"
OUT="$(watch)"
assert_eq "R6: a protected-path delta is gated, not done" "$(jverdict $S)" "gated"
contains "$(jreason $S)" "protected path written"
assert "R6: ... with the protected-path reason" $? "-- got: $(jreason $S)"

# C1 the conductor really writes the launch record before the window opens, and removes it after.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
cat > "$WORK/mux" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = capture-pane ]; then cp "$RUNDIR/fixrepo__ID-001.launch" "$WORK/launch.seen" 2>/dev/null; fi
exec "$FIX/fake-mux" "\$@"
EOF
chmod +x "$WORK/mux"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
OUT="$(MUX_CMD="$WORK/mux" run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
grep -q "^repo=$REPO\$" "$WORK/launch.seen" 2>/dev/null
assert "C1: the launch record names the repo while the run is live" $?
grep -q "^head=" "$WORK/launch.seen" 2>/dev/null && grep -q "^since=" "$WORK/launch.seen" 2>/dev/null
assert "C1: ... and the head and window-open time" $?
[ ! -f "$RUNDIR/fixrepo__ID-001.launch" ]
assert "C1: the conductor removes the launch record when the run ends" $?

echo
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

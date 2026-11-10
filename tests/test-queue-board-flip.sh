#!/usr/bin/env bash
# test-queue-board-flip.sh -- a queue run that ends done or gated moves its board row.
#
# At a TERMINAL verdict (`done` or any `gated`) `queue run` flips the row's BACKLOG status through
# `lib/board/backlog.sh set`: done -> executing, gated -> parked. Only a row still `queued` moves (a
# human's move is never clobbered); stalled/error/skipped leave the row alone; a failed flip is loud
# and never changes the journal verdict; the flip's own board edit is not the next row's
# protected-path write or progress evidence.
#
# Isolation: KIT_LEDGER_DIR points at a temp dir, so journal and sidecars never touch machine state.
# The queue is driven through tests/fixtures/queue/fake-mux (MUX_CMD): no real UI, no real `claude`.
#
# Run: bash tests/test-queue-board-flip.sh   (exit 0 = all checks green)

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

echo "=== queue verdict -> board row ==="
echo

# F1 done -> executing, the note names the slug.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F1: the journal says done" "$(jverdict fixrepo__ID-001)" "done"
assert_eq "F1: a done run moves the queued row to executing" "$(lead "$REPO" ID-001)" "executing"
contains "$(rowstatus "$REPO" ID-001)" "fixrepo__ID-001"
assert "F1: the row note names the slug" $?
contains "$(rowstatus "$REPO" ID-001)" "done"
assert "F1: the row note names the verdict" $?
assert_eq "F1: the other row is untouched" "$(lead "$REPO" ID-002)" "queued"

# F2 gated -> parked, the note carries the verdict reason.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript fixrepo__ID-001 "  RUNNER_GATED: held for human review"
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F2: the journal says gated" "$(jverdict fixrepo__ID-001)" "gated"
assert_eq "F2: a gated run moves the queued row to parked" "$(lead "$REPO" ID-001)" "parked"
contains "$(rowstatus "$REPO" ID-001)" "held for human review"
assert "F2: the row note carries the gated reason" $?

# F3 a `done` the conductor demotes to gated (no delta) also parks the row.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"      # no seed_work: a claim with no delta
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F3: a no-delta claim journals gated" "$(jverdict fixrepo__ID-001)" "gated"
assert_eq "F3: ... and parks the row" "$(lead "$REPO" ID-001)" "parked"

# F4 NEGATIVE CONTROL: a row a human already moved to claimed is left alone, said out loud.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
BACKLOG_FILE="$REPO/_meta/BACKLOG.md" bash "$KIT_DIR/lib/board/backlog.sh" set ID-001 claimed >/dev/null 2>&1
git -C "$REPO" commit -qam "chore: human claims the row"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F4 NC: the journal still says done" "$(jverdict fixrepo__ID-001)" "done"
assert_eq "F4 NC: a claimed row is NOT clobbered" "$(lead "$REPO" ID-001)" "claimed"
contains "$OUT" "not queued"
assert "F4 NC: the skip is reported" $? "-- got: $OUT"

# F5 NEGATIVE CONTROL: stalled leaves the row queued so the retry stays possible.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
# no transcript marker and a 1s ceiling: the run stalls
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F5 NC: the journal says stalled" "$(jverdict fixrepo__ID-001)" "stalled"
assert_eq "F5 NC: a stalled run leaves the row queued" "$(lead "$REPO" ID-001)" "queued"

# F6 NEGATIVE CONTROL: skipped (preflight) leaves the row queued.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
echo dirt >> "$REPO/f"      # a dirty repo is skipped by the preflight
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F6 NC: the journal says skipped" "$(jverdict fixrepo__ID-001)" "skipped"
assert_eq "F6 NC: a skipped run leaves the row queued" "$(lead "$REPO" ID-001)" "queued"

# F7 NEGATIVE CONTROL: a slug that is not `<repo>__<ID>` names no board row; nothing moves, no noise.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript plain "  RUNNER_DONE"; seed_work plain
OUT="$(run_rows "$(one_row plain "$REPO" "$WORK/p.txt")")"
assert_eq "F7 NC: a hand-authored slug still journals done" "$(jverdict plain)" "done"
assert_eq "F7 NC: no board row moves" "$(lead "$REPO" ID-001)" "queued"
contains "$OUT" "BOARD FLIP"
[ $? -ne 0 ]
assert "F7 NC: no flip noise for a non-board slug" $? "-- got: $OUT"

# F8 a failed flip is loud and never changes the journal verdict (a duplicate id makes `set` refuse).
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
printf '| ID-001 | union-merge duplicate | a note | queued |\n' >> "$REPO/_meta/BACKLOG.md"
git -C "$REPO" commit -qam "chore: duplicate row"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F8: the journal verdict stands" "$(jverdict fixrepo__ID-001)" "done"
contains "$OUT" "BOARD FLIP FAILED"
assert "F8: the failure is loud" $? "-- got: $OUT"
assert_eq "F8: exactly one journal row" "$(jrows fixrepo__ID-001)" "1"

# F9 a missing board is a loud failure too, not a silent skip.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
git -C "$REPO" rm -q _meta/BACKLOG.md; git -C "$REPO" commit -qm "chore: no board"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F9: the journal verdict stands" "$(jverdict fixrepo__ID-001)" "done"
contains "$OUT" "BOARD FLIP FAILED"
assert "F9: a missing board is reported" $? "-- got: $OUT"

# F10 a reason with table characters cannot corrupt the board row.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript fixrepo__ID-001 "  RUNNER_GATED: a | b [c] d"
OUT="$(run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")")"
assert_eq "F10: the row is still a 4-cell row after a reason with | and []" \
  "$(grep '^| ID-001 ' "$REPO/_meta/BACKLOG.md" | awk -F'|' '{print NF-2}')" "4"
assert_eq "F10: the row still parked" "$(lead "$REPO" ID-001)" "parked"

# F11 the flip's own board edit is not the NEXT row's protected-path write or progress evidence.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
printf '%s\t%s\t%s\n%s\t%s\t%s\n' fixrepo__ID-001 "$REPO" "$WORK/p.txt" fixrepo__ID-002 "$REPO" "$WORK/p.txt" > "$WORK/q.tsv"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
seed_transcript fixrepo__ID-002 "  RUNNER_DONE"; seed_work fixrepo__ID-002
OUT="$(run_rows "$WORK/q.tsv" --sanitize-prompt)"
assert_eq "F11: row 1 done" "$(jverdict fixrepo__ID-001)" "done"
assert_eq "F11: row 2 is NOT gated by row 1's board edit" "$(jverdict fixrepo__ID-002)" "done"
assert_eq "F11: both rows flipped" "$(lead "$REPO" ID-001)/$(lead "$REPO" ID-002)" "executing/executing"

# F12 NEGATIVE CONTROL for F11: a run that edits the board ITSELF is still a protected-path write.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
printf '%s\t%s\t%s\n%s\t%s\t%s\n' fixrepo__ID-001 "$REPO" "$WORK/p.txt" fixrepo__ID-002 "$REPO" "$WORK/p.txt" > "$WORK/q.tsv"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
seed_transcript fixrepo__ID-002 "  RUNNER_DONE"; seed_work fixrepo__ID-002
cat > "$WORK/mux" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = new-window ] && [[ "\$*" == *fixrepo__ID-002* ]]; then echo "| ID-003 | injected | n | queued |" >> "$REPO/_meta/BACKLOG.md"; fi
exec "$FIX/fake-mux" "\$@"
EOF
chmod +x "$WORK/mux"
OUT="$(MUX_CMD="$WORK/mux" run_rows "$WORK/q.tsv" --sanitize-prompt)"
assert_eq "F12 NC: a run that writes the board itself is gated" "$(jverdict fixrepo__ID-002)" "gated"
contains "$(jreason fixrepo__ID-002)" "protected path written"
assert "F12 NC: with the protected-path reason" $? "-- got: $(jreason fixrepo__ID-002)"

# F13 the exemption survives the process: a LATER `queue run` (the next watcher tick) is not skipped
# as a dirty tree because of the earlier flip, but a human's own board edit still is.
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")" >/dev/null
seed_transcript fixrepo__ID-002 "  RUNNER_DONE"; seed_work fixrepo__ID-002
OUT="$(run_rows "$(one_row fixrepo__ID-002 "$REPO" "$WORK/p.txt")")"
assert_eq "F13: a later run is not skipped by the earlier flip's dirty board" "$(jverdict fixrepo__ID-002)" "done"
new_env; REPO="$WORK/fixrepo"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
seed_transcript fixrepo__ID-001 "  RUNNER_DONE"; seed_work fixrepo__ID-001
run_rows "$(one_row fixrepo__ID-001 "$REPO" "$WORK/p.txt")" >/dev/null
echo "| ID-009 | human edit | n | queued |" >> "$REPO/_meta/BACKLOG.md"
OUT="$(run_rows "$(one_row fixrepo__ID-002 "$REPO" "$WORK/p.txt")")"
assert_eq "F13 NC: a human edit on top of the flip is still a dirty tree" "$(jverdict fixrepo__ID-002)" "skipped"

echo
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

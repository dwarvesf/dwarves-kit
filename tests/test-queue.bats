#!/usr/bin/env bats
# test-queue.bats -- pins lib/queue.sh (SPEC-146, runner-fastpath sub-goal 03K): the overnight
# queue LAUNCHER. Driven ENTIRELY by a STUB mux (tests/fixtures/queue/fake-mux via MUX_CMD) whose
# capture-pane returns a canned transcript -- NO real UI, NO real `claude`. Five named negative
# controls plus happy/dry-run/from-boards cases.

setup() {
  KIT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  QUEUE="$KIT/lib/queue.sh"
  FIX="$KIT/tests/fixtures/queue"
  WORK="$(mktemp -d)"
  QSTUB="$WORK/stub"; mkdir -p "$QSTUB"
  QLOG="$QSTUB/verbs.log"; : > "$QLOG"
  JOURNAL="$WORK/queue-journal.tsv"

  # Shared launcher env: the stub mux, fast timings, no real sleeps.
  export MUX_CMD="$FIX/fake-mux" TERMINAL_MUX=tmux
  export QSTUB QLOG
  export QUEUE_JOURNAL="$JOURNAL"
  export QUEUE_POLL_SECS=0 QUEUE_TIMEOUT_SECS=2 QUEUE_RETRY_SLEEP_SECS=0
  export QUEUE_STARTUP_SECS=0 QUEUE_SUBMIT_SETTLE_SECS=0
  chmod +x "$FIX/fake-mux" "$FIX/fake-board" 2>/dev/null || true
}

teardown() { [ -n "${WORK:-}" ] && mv "$WORK" "$WORK.done" 2>/dev/null || true; }

# --- helpers ---------------------------------------------------------------------------------
mkrepo() {  # dir -> a clean git repo on default branch `main`
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester
  echo x > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm init
}
seed_transcript() { printf '%s\n' "$2" > "$QSTUB/$1.transcript"; }   # slug last-line
seed_dead()       { : > "$QSTUB/$1.dead"; }                          # slug
row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }                     # slug repo pointer
jverdict() { awk -F'\t' -v s="$1" '$2==s{print $3}' "$JOURNAL"; }    # slug -> verdict col

# =============================================================================================
# T1 happy: a clean row whose transcript ends RUNNER_DONE -> journal `done`, window opened+killed
@test "T1 happy: RUNNER_DONE -> done, window opened and killed" {
  local repo="$WORK/r1"; mkrepo "$repo"
  echo "report HEAD then end" > "$WORK/p1.txt"
  # INDENTED marker: the real Claude Code TUI renders the final line inside its message block,
  # so the pane shows leading spaces. The live smoke proved a strict ^RUNNER_DONE$ misses this.
  seed_transcript ok1 "  RUNNER_DONE"
  row ok1 "$repo" "$WORK/p1.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict ok1)" = "done" ]
  grep -q "new-window slug=ok1" "$QLOG"
  grep -q "kill-window slug=ok1" "$QLOG"
}

# T2 happy: RUNNER_GATED -> journal `gated`, moves on
@test "T2 happy: RUNNER_GATED -> gated, moves on" {
  local repo="$WORK/r2"; mkrepo "$repo"
  echo "do the thing" > "$WORK/p2.txt"
  seed_transcript g2 "  RUNNER_GATED: held for human review"
  row g2 "$repo" "$WORK/p2.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict g2)" = "gated" ]
  awk -F'\t' '$2=="g2"{print $4}' "$JOURNAL" | grep -q "held for human review"
}

# T3 dry-run: prints WOULD LAUNCH, NO send-keys, no journal run row
@test "T3 dry-run: lists would-launch, no send-keys, no journal" {
  local repo="$WORK/r3"; mkrepo "$repo"
  echo "x" > "$WORK/p3.txt"
  row d3 "$repo" "$WORK/p3.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "WOULD LAUNCH"
  [ ! -f "$JOURNAL" ] || [ -z "$(jverdict d3)" ]        # no run row for d3
  ! grep -q "type slug=d3" "$QLOG"                       # no send-keys happened
}

# T4 source: --from-boards consumes the stub `board queue` emit on the tsv contract
@test "T4 from-boards: rows consumed from stub board queue emit" {
  local repo="$WORK/r4"; mkrepo "$repo"
  echo "x" > "$WORK/p4.txt"
  row b4 "$repo" "$WORK/p4.txt" > "$WORK/board-rows.tsv"
  seed_transcript b4 "RUNNER_DONE"
  export QUEUE_BOARD_CMD="$FIX/fake-board" QBOARD_ROWS="$WORK/board-rows.tsv"

  run bash "$QUEUE" run "" --from-boards
  [ "$status" -eq 0 ]
  [ "$(jverdict b4)" = "done" ]
}

# =============================================================================================
# NC1 dirty-tree skip: a dirty repo -> journal `skipped`, NO window opened
@test "NC1 dirty-tree-skip: dirty repo skipped, no window opened" {
  local repo="$WORK/rd"; mkrepo "$repo"
  echo "uncommitted" > "$repo/f"          # make the tree dirty
  echo "x" > "$WORK/pd.txt"
  row dirty1 "$repo" "$WORK/pd.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict dirty1)" = "skipped" ]
  awk -F'\t' '$2=="dirty1"{print $4}' "$JOURNAL" | grep -q "dirty tree"
  ! grep -q "new-window slug=dirty1" "$QLOG"             # never opened a window
}

# NC2 prose-quotes-completion: prose quotes the marker mid-line, no anchored final marker
#     -> NOT done; keeps waiting -> stalled at the timeout
@test "NC2 prose-quotes-completion-no-false-done: mid-line marker never triggers done" {
  local repo="$WORK/rp"; mkrepo "$repo"
  echo "x" > "$WORK/pp.txt"
  # transcript quotes the token mid-prose but no line IS the marker
  printf '%s\n' "I will end my final message with the exact line RUNNER_DONE when finished." \
    > "$QSTUB/prose1.transcript"
  row prose1 "$repo" "$WORK/pp.txt" > "$WORK/q.tsv"

  QUEUE_POLL_SECS=1 QUEUE_TIMEOUT_SECS=1 run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict prose1)" = "stalled" ]                  # NOT done
}

# NC3 error-twice-stops-night: two rows whose window dies twice -> night stops; row 3 untouched
@test "NC3 error-twice-stops-night: 2 consecutive errors stop the night, later rows untouched" {
  local r1="$WORK/e1" r2="$WORK/e2" r3="$WORK/e3"; mkrepo "$r1"; mkrepo "$r2"; mkrepo "$r3"
  echo x > "$WORK/pe.txt"
  seed_dead err1; seed_dead err2               # both windows die (nonzero capture)
  seed_transcript err3 "RUNNER_DONE"           # row 3 WOULD succeed if reached
  { row err1 "$r1" "$WORK/pe.txt"; row err2 "$r2" "$WORK/pe.txt"; row err3 "$r3" "$WORK/pe.txt"; } > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict err1)" = "error" ]
  [ "$(jverdict err2)" = "error" ]
  [ -z "$(jverdict err3)" ]                     # row 3 never attempted -> no journal row
  echo "$output" | grep -q "STOP THE NIGHT"
}

# NC4 journal-done-idempotence: journal preseeded `slug done` -> row skipped, no window opened
@test "NC4 journal-done-idempotence: a done slug is skipped on re-run" {
  local repo="$WORK/ri"; mkrepo "$repo"
  echo x > "$WORK/pi.txt"
  printf '%s\tidem1\tdone\t\n' "2026-07-05T00:00:00Z" > "$JOURNAL"   # preseed
  seed_transcript idem1 "RUNNER_DONE"
  row idem1 "$repo" "$WORK/pi.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already done"
  ! grep -q "new-window slug=idem1" "$QLOG"             # never opened a window
  [ "$(grep -c 'idem1' "$JOURNAL")" -eq 1 ]             # no second row appended
}

# NC5 queue-metachar argv-safe: metachars in slug + pointer stay literal, never reach a shell
@test "NC5 queue-metachar-argv-safe: metachar fields are literal, no shell exec" {
  local repo="$WORK/rm"; mkrepo "$repo"
  local sentinel="$WORK/SENTINEL"; : > "$sentinel"
  # a pointer whose CONTENT is a shell-injection attempt; it is TYPED, never executed
  printf 'report; rm -f %s; $(touch %s.pwned) `id`\n' "$sentinel" "$sentinel" > "$WORK/pm.txt"
  local slug='ev;il&$(rm -rf x)|z'
  seed_transcript "$slug" "RUNNER_DONE"
  row "$slug" "$repo" "$WORK/pm.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ -f "$sentinel" ]                                    # injection did NOT delete the sentinel
  [ ! -f "$sentinel.pwned" ]                            # $(touch ...) never executed
  # the slug is journaled as an untouched literal field
  awk -F'\t' -v s="$slug" '$2==s && $3=="done"{f=1} END{exit !f}' "$JOURNAL"
  # the pointer metachars were typed verbatim (data), proving they went through argv, not a shell
  grep -F 'rm -f' "$QLOG"
  grep -F '$(touch' "$QLOG"
}

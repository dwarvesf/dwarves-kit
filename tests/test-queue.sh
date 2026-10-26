#!/usr/bin/env bash
# test-queue.sh -- pins lib/queue/queue.sh (SPEC-146, runner-fastpath sub-goal 03K): the overnight
# queue LAUNCHER. Driven ENTIRELY by a STUB mux (tests/fixtures/queue/fake-mux via MUX_CMD) whose
# capture-pane returns a canned transcript -- NO real UI, NO real `claude`. The five ORIGINALLY
# named negative controls (NC1-NC5) plus two ADDED after a 2026-07-05 security review found real
# gaps (NC6 marker-wrap false-positive, NC7 stalled-twice-stops-night), plus T5/T6 locking the
# allow-list fix from the same review.
#
# This was a bats file (tests/test-queue.bats) that no runner collected: bats is not a declared
# dependency, so run-all.sh and CI never ran it. Each case is now a plain function run by the small
# harness below, one subshell per case with `set -e` (a failed `[ ]` fails the case, as in bats).
# `run` keeps the bats contract: it sets $status and $output and never aborts the case.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- harness -------------------------------------------------------------------------------------
pass=0; fail=0; failed_names=""

run() {  # run <cmd...>: $status = exit code, $output = stdout+stderr
  status=0
  output="$( trap - ERR; set +e; "$@" 2>&1 )" || status=$?
}

run_case() {  # run_case <title> <function>
  local title="$1" fn="$2" out rc
  # No `|| rc=$?` after the substitution: an `||` list makes bash skip the ERR trap inside it.
  out="$( (
    set -eE
    trap 'echo "  failed at line $LINENO: $BASH_COMMAND" >&2' ERR
    trap teardown EXIT
    setup
    "$fn"
  ) 2>&1 )"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass=$((pass + 1)); echo "  ok   $title"
  else
    fail=$((fail + 1)); failed_names="$failed_names ${fn#case_}"
    echo "  FAIL $title"; printf '%s\n' "$out" | tail -20 | sed 's/^/       | /'
  fi
}

setup() {
  KIT="$(cd "$HERE/.." && pwd)"
  QUEUE="$KIT/lib/queue/queue.sh"
  FIX="$KIT/tests/fixtures/queue"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
  QSTUB="$WORK/stub"; mkdir -p "$QSTUB"
  QLOG="$QSTUB/verbs.log"; : > "$QLOG"
  JOURNAL="$WORK/queue-journal.tsv"

  # Shared launcher env: the stub mux, fast timings, no real sleeps.
  export MUX_CMD="$FIX/fake-mux" TERMINAL_MUX=tmux
  export QSTUB QLOG
  export QUEUE_JOURNAL="$JOURNAL"
  # Sandbox the WHOLE ledger root, not just the journal: run files (beat/status/guard) resolve
  # through kit_resolve_log_dir, and without this they land in the operator's REAL
  # ~/.local/state/dwarves-kit/logs/queue-runs/. The leaked guard counters accumulated across
  # local suite runs until the SPEC-221 breaker tripped (noprogress >= 3) and rewrote NC2/NC6/
  # NC7's expected `stalled` into `error stagnation_detected`, failing them forever on that
  # machine while staying green on fresh checkouts. The ID-463 class, state-dir edition.
  export KIT_LEDGER_DIR="$WORK/logs"; mkdir -p "$WORK/logs"
  export QUEUE_POLL_SECS=0 QUEUE_TIMEOUT_SECS=2 QUEUE_RETRY_SLEEP_SECS=0
  export QUEUE_STARTUP_SECS=0 QUEUE_SUBMIT_SETTLE_SECS=0
  chmod +x "$FIX/fake-mux" "$FIX/fake-board" 2>/dev/null || true
}

teardown() { [ -n "${WORK:-}" ] && mv "$WORK" "$WORK.done" 2>/dev/null || true; }

# --- helpers ---------------------------------------------------------------------------------
mkrepo() {  # dir -> a clean git repo on default branch `main`
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  [ -n "$d" ] && [ -d "$d" ] || { echo "fixture dir missing" >&2; exit 1; }
  git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester
  echo x > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm init
}
seed_transcript() { printf '%s\n' "$2" > "$QSTUB/$1.transcript"; }   # slug last-line
seed_dead()       { : > "$QSTUB/$1.dead"; }                          # slug
seed_work()       { : > "$QSTUB/$1.work"; }                          # slug: the window commits once in its repo
row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }                     # slug repo pointer
jverdict() { awk -F'\t' -v s="$1" '$2==s{print $3}' "$JOURNAL"; }    # slug -> verdict col

# =============================================================================================
# T1 happy: a clean row whose transcript ends RUNNER_DONE -> journal `done`, window opened+killed
case_T1() {
  local repo="$WORK/r1"; mkrepo "$repo"
  echo "report HEAD then end" > "$WORK/p1.txt"
  # INDENTED marker: the real Claude Code TUI renders the final line inside its message block,
  # so the pane shows leading spaces. The live smoke proved a strict ^RUNNER_DONE$ misses this.
  seed_transcript ok1 "  RUNNER_DONE"
  seed_work ok1
  row ok1 "$repo" "$WORK/p1.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict ok1)" = "done" ]
  grep -q "new-window slug=ok1" "$QLOG"
  grep -q "kill-window slug=ok1" "$QLOG"
}
run_case "T1 happy: RUNNER_DONE -> done, window opened and killed" case_T1

# T2 happy: RUNNER_GATED -> journal `gated`, moves on
case_T2() {
  local repo="$WORK/r2"; mkrepo "$repo"
  echo "do the thing" > "$WORK/p2.txt"
  seed_transcript g2 "  RUNNER_GATED: held for human review"
  row g2 "$repo" "$WORK/p2.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict g2)" = "gated" ]
  awk -F'\t' '$2=="g2"{print $4}' "$JOURNAL" | grep -q "held for human review"
}
run_case "T2 happy: RUNNER_GATED -> gated, moves on" case_T2

# T3 dry-run: prints WOULD LAUNCH, NO send-keys, no journal run row
case_T3() {
  local repo="$WORK/r3"; mkrepo "$repo"
  echo "x" > "$WORK/p3.txt"
  row d3 "$repo" "$WORK/p3.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv" --dry-run
  [ "$status" -eq 0 ]
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "WOULD LAUNCH"
  [ ! -f "$JOURNAL" ] || [ -z "$(jverdict d3)" ]        # no run row for d3
  ! grep -q "type slug=d3" "$QLOG"                       # no send-keys happened
}
run_case "T3 dry-run: lists would-launch, no send-keys, no journal" case_T3

# T4 source: --from-boards consumes the stub `board queue` emit on the tsv contract. The pointer
# must resolve under the allow-listed glob (_meta/megagoals/** or .claude/goals/**) since
# --from-boards rows get the defense-in-depth confinement check (T5/T6 below cover the boundary).
case_T4() {
  local repo="$WORK/r4"; mkrepo "$repo"
  mkdir -p "$repo/_meta/megagoals/fx/goals"
  echo "x" > "$repo/_meta/megagoals/fx/goals/p4.txt"
  git -C "$repo" add -A; git -C "$repo" commit -qm "chore: fixture pointer"   # keep the repo clean
  row b4 "$repo" "$repo/_meta/megagoals/fx/goals/p4.txt" > "$WORK/board-rows.tsv"
  seed_transcript b4 "  RUNNER_DONE"
  seed_work b4
  export QUEUE_BOARD_CMD="$FIX/fake-board" QBOARD_ROWS="$WORK/board-rows.tsv"

  run bash "$QUEUE" run "" --from-boards
  [ "$status" -eq 0 ]
  [ "$(jverdict b4)" = "done" ]
}
run_case "T4 from-boards: rows consumed from stub board queue emit, pointer allow-listed" case_T4

# T5 from-boards allow-list: a --from-boards pointer OUTSIDE the allow-listed globs is skipped, no
# window opened -- the CRITICAL security-review fix: defense-in-depth on top of sub-goal 04's own
# allow-list, since this launcher must not simply trust an upstream tool has no bugs when the
# destination is an unattended --dangerously-skip-permissions session.
case_T5() {
  local repo="$WORK/r5"; mkrepo "$repo"
  echo "x" > "$WORK/rogue-pointer.txt"          # OUTSIDE the repo, outside any allow-listed glob
  row rogue "$repo" "$WORK/rogue-pointer.txt" > "$WORK/board-rows2.tsv"
  export QUEUE_BOARD_CMD="$FIX/fake-board" QBOARD_ROWS="$WORK/board-rows2.tsv"

  run bash "$QUEUE" run "" --from-boards
  [ "$status" -eq 0 ]
  [ "$(jverdict rogue)" = "skipped" ]
  awk -F'\t' '$2=="rogue"{print $4}' "$JOURNAL" | grep -qi "not allow-listed"
  ! grep -q "new-window slug=rogue" "$QLOG"
}
run_case "T5 from-boards-pointer-allowlist: a non-allow-listed pointer is skipped, no window opened" case_T5

# T6 hand-authored tsv is allow-list-EXEMPT (operator authorship is the trust boundary for the
# plain tsv path; only --from-boards gets the defense-in-depth confinement).
case_T6() {
  local repo="$WORK/r6"; mkrepo "$repo"
  echo "x" > "$WORK/anywhere.txt"
  seed_transcript hand6 "  RUNNER_DONE"
  seed_work hand6
  row hand6 "$repo" "$WORK/anywhere.txt" > "$WORK/q6.tsv"

  run bash "$QUEUE" run "$WORK/q6.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict hand6)" = "done" ]
}
run_case "T6 hand-tsv-allowlist-exempt: a plain tsv pointer outside the glob still launches" case_T6

# T7 from-boards-symlink-escape: a SYMLINK planted INSIDE the allow-listed dir but pointing
# OUTSIDE the repo must be rejected too -- a rung-4 red-team probe found the first cut (resolving
# only the pointer's containing DIRECTORY, not the final path component) would have let such a
# symlink read arbitrary file content into the /goal prompt while still LOOKING allow-listed.
case_T7() {
  local repo="$WORK/r7"; mkrepo "$repo"
  mkdir -p "$repo/_meta/megagoals/fx"
  local outside="$WORK/OUTSIDE_SECRET.txt"; echo "secret" > "$outside"
  local link="$repo/_meta/megagoals/fx/link.txt"
  ln -sf "$outside" "$link"
  git -C "$repo" add -A; git -C "$repo" commit -qm "chore: fixture symlink" 2>/dev/null || true
  row esc7 "$repo" "$link" > "$WORK/board-rows7.tsv"
  export QUEUE_BOARD_CMD="$FIX/fake-board" QBOARD_ROWS="$WORK/board-rows7.tsv"

  run bash "$QUEUE" run "" --from-boards
  [ "$status" -eq 0 ]
  [ "$(jverdict esc7)" = "skipped" ]
  ! grep -q "new-window slug=esc7" "$QLOG"
}
run_case "T7 from-boards-symlink-escape: a symlink escaping the repo via the allow-listed dir is skipped" case_T7

# =============================================================================================
# NC1 dirty-tree skip: a dirty repo -> journal `skipped`, NO window opened
case_NC1() {
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
run_case "NC1 dirty-tree-skip: dirty repo skipped, no window opened" case_NC1

# NC2 prose-quotes-completion: prose quotes the marker mid-line, no anchored final marker
#     -> NOT done; keeps waiting -> stalled at the timeout
case_NC2() {
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
run_case "NC2 prose-quotes-completion-no-false-done: mid-line marker never triggers done" case_NC2

# NC3 error-twice-stops-night: two rows whose window dies twice -> night stops; row 3 untouched
case_NC3() {
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
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "STOP THE NIGHT"
}
run_case "NC3 error-twice-stops-night: 2 consecutive errors stop the night, later rows untouched" case_NC3

# NC4 journal-done-idempotence: journal preseeded `slug done` -> row skipped, no window opened
case_NC4() {
  local repo="$WORK/ri"; mkrepo "$repo"
  echo x > "$WORK/pi.txt"
  printf '%s\tidem1\tdone\t\n' "2026-07-05T00:00:00Z" > "$JOURNAL"   # preseed
  seed_transcript idem1 "RUNNER_DONE"
  row idem1 "$repo" "$WORK/pi.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "already done"
  ! grep -q "new-window slug=idem1" "$QLOG"             # never opened a window
  [ "$(grep -c 'idem1' "$JOURNAL")" -eq 1 ]             # no second row appended
}
run_case "NC4 journal-done-idempotence: a done slug is skipped on re-run" case_NC4

# NC5 queue-metachar argv-safe: metachars in slug + pointer stay literal, never reach a shell
case_NC5() {
  local repo="$WORK/rm"; mkrepo "$repo"
  local sentinel="$WORK/SENTINEL"; : > "$sentinel"
  # a pointer whose CONTENT is a shell-injection attempt; it is TYPED, never executed
  printf 'report; rm -f %s; $(touch %s.pwned) `id`\n' "$sentinel" "$sentinel" > "$WORK/pm.txt"
  local slug='ev;il&$(rm -rf x)|z'
  seed_transcript "$slug" "RUNNER_DONE"
  seed_work "$slug"
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
run_case "NC5 queue-metachar-argv-safe: metachar fields are literal, no shell exec" case_NC5

# NC6 marker-wrap false-positive (security review, CRITICAL #2): `_goal_line` flattens the whole
# pointer into ONE long typed line, and a pointer is DESIGNED to instruct printing RUNNER_DONE. A
# wide-enough pane soft-wraps that echoed line so the marker substring can land ALONE on its own
# rendered row -- indistinguishable from a real completion by line-anchoring alone. This transcript
# simulates exactly that: a wrapped echo whose last fragment IS "RUNNER_DONE", with NO blank line
# above it (a genuine wrap continuation never has one). Must NOT be marked done.
case_NC6() {
  local repo="$WORK/rw"; mkrepo "$repo"
  echo "x" > "$WORK/pw.txt"
  {
    printf '❯ /goal Do the thing. End your final message with the exact line\n'
    printf '  RUNNER_DONE\n'                     # wrap continuation, NO blank line above
  } > "$QSTUB/wrap1.transcript"
  row wrap1 "$repo" "$WORK/pw.txt" > "$WORK/q.tsv"

  QUEUE_POLL_SECS=1 QUEUE_TIMEOUT_SECS=1 run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict wrap1)" = "stalled" ]            # NOT done -- the wrap fragment is rejected
}
run_case "NC6 marker-wrap-false-positive: a wrapped echo fragment never triggers done" case_NC6

# NC7 stalled-twice-stops-night: two consecutive `stalled` verdicts ALSO stop the night (extended
# from the original error-only guard, security review MEDIUM: a hang, not just a crash, is an
# equally valid "the mechanism is dysfunctional" signal and must not silently burn the whole
# night's remaining queue).
case_NC7() {
  local r1="$WORK/s1n" r2="$WORK/s2n" r3="$WORK/s3n"; mkrepo "$r1"; mkrepo "$r2"; mkrepo "$r3"
  echo x > "$WORK/psn.txt"
  # no transcript seeded for s1n/s2n -> capture-pane returns empty, never matches -> stalled
  seed_transcript s3n "  RUNNER_DONE"
  { row s1n "$r1" "$WORK/psn.txt"; row s2n "$r2" "$WORK/psn.txt"; row s3n "$r3" "$WORK/psn.txt"; } > "$WORK/q.tsv"

  QUEUE_POLL_SECS=1 QUEUE_TIMEOUT_SECS=1 run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict s1n)" = "stalled" ]
  [ "$(jverdict s2n)" = "stalled" ]
  [ -z "$(jverdict s3n)" ]                       # row 3 never attempted -> no journal row
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "STOP THE NIGHT"
}
run_case "NC7 stalled-twice-stops-night: 2 consecutive stalls stop the night, later rows untouched" case_NC7

# =============================================================================================
# T9 submit-retry: a dropped Enter with the goal rendered TAIL-first (no `/goal` substring in
# the pane) is detected as still-pending and re-Entered until the input clears. Pins the fix
# for the 3-for-3 live stranding: the old `[>❯]\s*/goal` match saw the tail rendering, reported
# submitted after one dropped Enter, and the row sat idle with no journal entry.
case_T9() {
  . "$QUEUE"
  printf '2' > "$QSTUB/s7.pending"                # first 2 Enters drop; 3rd not needed
  # premise guard: the stuck rendering must NOT contain `/goal` (what broke the old regex)
  "$MUX_CMD" capture-pane -t "q:s7" | grep -vq '/goal'
  _mux_submit s7
  [ ! -f "$QSTUB/s7.pending" ]                    # input eventually cleared
  [ "$(grep -c 'enter slug=s7' "$QLOG")" -eq 2 ]  # exactly the 2 Enters needed, then stopped
}
run_case "T9 submit-retry: tail-rendered pending input is re-Entered until clear" case_T9

# T10 submit-bare-prompt: an already-clear (bare `❯`) prompt submits on the first Enter, no
# retry storm -- the empty-input rendering must not read as pending.
case_T10() {
  . "$QUEUE"
  printf '❯ \n' > "$QSTUB/s8.transcript"
  _mux_submit s8
  [ "$(grep -c 'enter slug=s8' "$QLOG")" -eq 1 ]
}
run_case "T10 submit-bare-prompt: bare prompt exits after one Enter" case_T10

# =============================================================================================
# T11 goal-over-budget: a pointer whose /goal line exceeds the interactive 4000-char cap fails
# fast to `error`, with NO window ever opened -- pins the fix for the silent-strand bug (an
# over-budget goal used to type into a real window and sit there forever, no journal entry,
# nothing but an idle pane an operator had to notice by hand across 3 live runs).
case_T11() {
  local repo="$WORK/r11"; mkrepo "$repo"
  python3 -c "print('x' * 4200)" > "$WORK/p11.txt"
  row big11 "$repo" "$WORK/p11.txt" > "$WORK/q.tsv"

  QUEUE_RETRY_SLEEP_SECS=0 run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict big11)" = "error" ]
  ! grep -q "new-window slug=big11" "$QLOG"
}
run_case "T11 goal-over-budget: fails fast to error, no window opened" case_T11

# T12 goal-under-budget: a normal-size pointer is unaffected by the new check (regression guard
# alongside T1, run through the SAME real `queue run` path with the length check now present).
case_T12() {
  local repo="$WORK/r12"; mkrepo "$repo"
  echo "report HEAD then end" > "$WORK/p12.txt"
  seed_transcript ok12 "  RUNNER_DONE"
  seed_work ok12
  row ok12 "$repo" "$WORK/p12.txt" > "$WORK/q.tsv"

  run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict ok12)" = "done" ]
  grep -q "new-window slug=ok12" "$QLOG"
}
run_case "T12 goal-under-budget: unaffected, window opens and completes" case_T12

# =============================================================================================
# T13 state-sandbox tripwire: with KIT_LEDGER_DIR exported (setup does), every run file the
# launcher writes resolves INSIDE the sandbox, never the operator's real state dir. Pins the
# ID-468 root cause: the suite sandboxed the journal but not beat/status/guard, leaking counter
# files into ~/.local/state until the breaker's noprogress trip flipped NC2/NC6/NC7 forever.
case_T13() {
  . "$QUEUE"
  [ "$(_run_dir)" = "$KIT_LEDGER_DIR/queue-runs" ]
  case "$(_run_dir)" in "$WORK"/*) : ;; *) false ;; esac
}
run_case "T13 state-sandbox tripwire: run files resolve under KIT_LEDGER_DIR" case_T13

# =============================================================================================
# wait verb (ID-470): block until a slug reaches a terminal state. Read-only over journal + mux.
# The fake-mux capture-pane exits nonzero iff $QSTUB/<slug>.dead exists (window gone), so these
# drive the alive/dead axis with a file.

# W1 already-terminal: a done row already present, window gone -> exit 0, prints the row.
case_W1() {
  printf '%s\tw1\tdone\tshipped\n' "2026-08-10T00:00:00Z" > "$JOURNAL"
  seed_dead w1
  QUEUE_WAIT_POLL_SECS=0 run bash "$QUEUE" wait w1
  [ "$status" -eq 0 ]
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "	w1	done	"
}
run_case "W1 wait already-terminal -> exit 0 prints the row" case_W1

# W2 new terminal row lands mid-wait (window alive) -> exit 0, prints the new row.
case_W2() {
  : > "$JOURNAL"                                   # empty: base count 0
  ( sleep 1; printf '%s\tw2\tgated\tneeds-human\n' "2026-08-10T00:00:01Z" >> "$JOURNAL" ) &
  QUEUE_WAIT_POLL_SECS=1 run bash "$QUEUE" wait w2 --timeout 10
  [ "$status" -eq 0 ]
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "	w2	gated	"
}
run_case "W2 wait new-row -> exit 0" case_W2

# W3 window dies with no terminal row -> exit 1, residue to stderr.
case_W3() {
  : > "$JOURNAL"
  seed_dead w3
  QUEUE_WAIT_POLL_SECS=0 run bash "$QUEUE" wait w3
  [ "$status" -eq 1 ]
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "gone with no terminal journal row"
}
run_case "W3 wait window-died-no-verdict -> exit 1" case_W3

# W4 timeout: window alive, no row ever -> exit 2.
case_W4() {
  : > "$JOURNAL"                                   # window alive (no .dead), never a row
  QUEUE_WAIT_POLL_SECS=1 run bash "$QUEUE" wait w4 --timeout 1
  [ "$status" -eq 2 ]
  { trap '' PIPE; echo "$output" 2>/dev/null || :; } | grep -q "timeout after 1s"
}
run_case "W4 wait timeout -> exit 2" case_W4

# W5 bad input: a slug with a tmux/path separator, and a missing slug -> usage exit 64.
case_W5() {
  run bash "$QUEUE" wait 'a:b'
  [ "$status" -eq 64 ]
  run bash "$QUEUE" wait
  [ "$status" -eq 64 ]
}
run_case "W5 wait bad-slug and missing-slug -> exit 64" case_W5

# =============================================================================================
# D1 done-needs-delta: a RUNNER_DONE claim with no HEAD move and no new PR is journaled `gated`,
# reason `no-delta`, never `done` (the negative control for "self-reported completion").
case_D1() {
  local repo="$WORK/rd1"; mkrepo "$repo"
  echo "report only" > "$WORK/pd1.txt"
  seed_transcript nd1 "  RUNNER_DONE"
  row nd1 "$repo" "$WORK/pd1.txt" > "$WORK/q.tsv"

  PATH="$WORK/nogh:$PATH" run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict nd1)" = "gated" ]
  awk -F'\t' '$2=="nd1"{print $4}' "$JOURNAL" | grep -q '^no-delta$'
}
run_case "D1 no-delta: RUNNER_DONE with no commit and no PR -> gated no-delta" case_D1

# D2 a PR of mine created since the window opened counts as delta even when HEAD did not move (the run
# worked in a worktree and pushed). The `gh` stub honours -q: it runs the real jq filter over a canned
# `pr list` payload, so the createdAt comparison and the author flag are exercised, not skipped.
mkgh() {  # createdAt-of-the-one-PR
  mkdir -p "$WORK/ghbin"
  cat > "$WORK/ghbin/gh" <<GHEOF
#!/usr/bin/env bash
case "\$*" in *"--author @me"*) ;; *) echo "gh stub: --author @me missing" >&2; exit 1 ;; esac
q=""; while [ \$# -gt 0 ]; do [ "\$1" = "-q" ] && q="\$2"; shift; done
printf '%s' '[{"createdAt":"$1"}]' | jq -r "\$q"
GHEOF
  chmod +x "$WORK/ghbin/gh"
}

case_D2() {
  local repo="$WORK/rd2"; mkrepo "$repo"
  echo "report only" > "$WORK/pd2.txt"
  seed_transcript nd2 "  RUNNER_DONE"
  row nd2 "$repo" "$WORK/pd2.txt" > "$WORK/q.tsv"
  mkgh "2099-01-01T00:00:00Z"

  PATH="$WORK/ghbin:$PATH" run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict nd2)" = "done" ]
}
run_case "D2 pr-delta: a PR created during the run -> done without a HEAD move" case_D2

# D3 a PR that predates the window is no evidence
case_D3() {
  local repo="$WORK/rd3"; mkrepo "$repo"
  echo "report only" > "$WORK/pd3.txt"
  seed_transcript nd3 "  RUNNER_DONE"
  row nd3 "$repo" "$WORK/pd3.txt" > "$WORK/q.tsv"
  mkgh "2000-01-01T00:00:00Z"

  PATH="$WORK/ghbin:$PATH" run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict nd3)" = "gated" ]
}
run_case "D3 pr-delta: a PR older than the window -> gated no-delta" case_D3

# D4 a worktree run that only creates a branch (no PR, no gh) still leaves a delta
case_D4() {
  local repo="$WORK/rd4"; mkrepo "$repo"
  echo "report only" > "$WORK/pd4.txt"
  seed_transcript nd4 "  RUNNER_DONE"
  : > "$QSTUB/nd4.branch"
  row nd4 "$repo" "$WORK/pd4.txt" > "$WORK/q.tsv"

  PATH="$WORK/nogh:$PATH" run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(jverdict nd4)" = "done" ]
}
run_case "D4 branch-delta: a new local branch with no HEAD move and no gh -> done" case_D4

# D5 a gated no-delta row is not relaunched by the next `queue run` over the same tsv
case_D5() {
  local repo="$WORK/rd5"; mkrepo "$repo"
  echo "report only" > "$WORK/pd5.txt"
  seed_transcript nd5 "  RUNNER_DONE"
  row nd5 "$repo" "$WORK/pd5.txt" > "$WORK/q.tsv"

  PATH="$WORK/nogh:$PATH" run bash "$QUEUE" run "$WORK/q.tsv"
  PATH="$WORK/nogh:$PATH" run bash "$QUEUE" run "$WORK/q.tsv"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'new-window slug=nd5' "$QLOG")" -eq 1 ]
  [ "$(awk -F'\t' '$2=="nd5"' "$JOURNAL" | wc -l | tr -d ' ')" -eq 1 ]
}
run_case "D5 no-delta-idempotence: the second run over the same tsv opens no second window" case_D5

echo
if [ "$fail" -gt 0 ]; then echo "test-queue: $pass passed, $fail FAILED ->$failed_names"; exit 1; fi
echo "test-queue: all $pass passed"

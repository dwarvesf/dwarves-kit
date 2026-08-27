#!/usr/bin/env bash
# test-cheap-guards.sh -- SPEC-224 (board row ID-461), the two cheap guardrails on the autonomous
# run queue: draft-PR-by-default and a self-reported per-row/queue-wide spend ceiling.
#
# Both are real bash logic, so both are asserted directly, end to end through `queue run` with the
# stub mux. Every section carries its own negative control (the healthy case that must NOT trip):
#
#   A) draft-PR default   NC: --ready opens a normal PR (no draft clause on the typed line)
#   B) per-row ceiling    NC: a run under the ceiling reaches `done`, never `spend_ceiling`
#   C) queue-wide ceiling NC: a batch under the total runs every row
#   D) _status_num + backward compat
#   E) --push-only (ID-472) NC: without the flag the draft clause still types
#
# Isolation: KIT_LEDGER_DIR points at a temp dir, so sidecars and the journal never touch real
# machine state. The mux is the same stub the sibling suites use (no real UI, no real claude), and
# the typed /goal line is read back from the stub's verb log (QLOG) to prove the draft clause.
#
# Run: bash tests/test-cheap-guards.sh   (exit 0 = all checks green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE="$KIT_DIR/lib/queue/queue.sh"
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

# ---- shared environment (mirrors test-runaway-guards.sh) ---------------------------------------
WORK=""; RUNDIR=""; JOURNAL=""; QSTUB=""; QLOG=""
new_env() {
  WORK="$(_mk)"
  QSTUB="$WORK/stub"; mkdir -p "$QSTUB"; QLOG="$QSTUB/verbs.log"; : > "$QLOG"
  export KIT_LEDGER_DIR="$WORK/ledger"; mkdir -p "$KIT_LEDGER_DIR"
  RUNDIR="$KIT_LEDGER_DIR/queue-runs"; mkdir -p "$RUNDIR"
  JOURNAL="$WORK/queue-journal.tsv"; : > "$JOURNAL"
  _write_stub_wrapper
  export MUX_CMD="$WORK/mux" TERMINAL_MUX=tmux QSTUB QLOG
  export QUEUE_JOURNAL="$JOURNAL"
  export QUEUE_POLL_SECS=1 QUEUE_TIMEOUT_SECS=1 QUEUE_RETRY_SLEEP_SECS=0
  export QUEUE_STARTUP_SECS=0 QUEUE_SUBMIT_SETTLE_SECS=0
  unset QUEUE_PR_READY QUEUE_PUSH_ONLY QUEUE_MAX_TOOL_CALLS QUEUE_MAX_TOTAL_TOOL_CALLS 2>/dev/null || true
}

# The wrapper sources $QSTUB/<slug>.during on capture-pane, which is how a test simulates the
# SESSION acting (writing its status file) mid-poll.
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

during() { printf '%s\n' "$2" > "$QSTUB/$1.during"; }
# The run writes its own status file (the common case).
status_during() {
  printf '%b' "$2" > "$QSTUB/$1.status-src"
  during "$1" "cp \"\$QSTUB/$1.status-src\" \"\$KIT_LEDGER_DIR/queue-runs/$1.status\""
}
mkrepo() {  # dir -> clean git repo on default branch main
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester
  echo x > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm init
}
jverdict() { awk -F'\t' -v s="$1" '$2==s {v=$3} END{print v}' "$JOURNAL"; }
jreason()  { awk -F'\t' -v s="$1" '$2==s {v=$4} END{print v}' "$JOURNAL"; }
jrows()    { awk -F'\t' -v s="$1" '$2==s {n++} END{print n+0}' "$JOURNAL"; }
# The literal /goal line the conductor typed for <slug>, read back from the stub verb log.
typed() { grep "^type slug=$1 " "$QLOG" | sed 's/^type slug=[^ ]* text=//'; }

# Run a tsv of rows through the queue. Extra args pass flags (e.g. --ready).
run_tsv() {  # tsv-path [flags...]
  local tsv="$1"; shift
  bash "$QUEUE" run "$tsv" "$@" 2>&1
}
# Single-row convenience.
run_row() {  # slug repo pointer [flags...]
  local slug="$1" repo="$2" ptr="$3"; shift 3
  printf '%s\t%s\t%s\n' "$slug" "$repo" "$ptr" > "$WORK/q.tsv"
  run_tsv "$WORK/q.tsv" "$@"
}

echo "=== SPEC-224 cheap guardrails ==="
echo
echo "--- Section A: draft-PR by default ---"

# A1 the default posture: the typed /goal line instructs a DRAFT PR and carries the provenance footer.
new_env; REPO="$WORK/rA1"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
status_during a1 "EXIT_SIGNAL: true"
run_row a1 "$REPO" "$WORK/p.txt" >/dev/null
case "$(typed a1)" in *"gh pr create --draft"*) R=0 ;; *) R=1 ;; esac
assert "A1: the autonomous default types a draft-PR clause" $R "-- got: $(typed a1)"
case "$(typed a1)" in *"unattended orchestrator run"*"slug a1"*) R=0 ;; *) R=1 ;; esac
assert "A1: the draft clause carries the provenance footer (run marker + slug)" $R

# A2 NEGATIVE CONTROL: --ready drops the draft clause entirely (a normal PR).
new_env; REPO="$WORK/rA2"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
status_during a2 "EXIT_SIGNAL: true"
run_row a2 "$REPO" "$WORK/p.txt" --ready >/dev/null
case "$(typed a2)" in *"--draft"*|*"DRAFT"*) R=1 ;; *) R=0 ;; esac
assert "A2 NC: --ready types NO draft clause (the escape hatch)" $R "-- got: $(typed a2)"

# A3 the interactive path is untouched: ship.md keeps the normal-PR contract and marks the draft
# default autonomous-only. The draft default lives ONLY in _goal_line, which /kit:ship never calls.
case "$(cat "$KIT_DIR/commands/ship.md")" in *"Interactive"*"opens a normal PR"*) R=0 ;; *) R=1 ;; esac
assert "A3: ship.md keeps interactive shipping a normal PR" $R
case "$(cat "$KIT_DIR/commands/ship.md")" in *"unattended orchestrator run"*) R=0 ;; *) R=1 ;; esac
assert "A3: ship.md documents the autonomous draft footer" $R

echo
echo "--- Section B: the per-row spend ceiling ---"

# B1 the ceiling trips: a run whose self-reported TOOL_CALLS crosses QUEUE_MAX_TOOL_CALLS stops with
# verdict `stalled` and the SHARED reason field set to spend_ceiling (SPEC-221's reason, EXTENDED).
new_env; REPO="$WORK/rB1"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
export QUEUE_MAX_TOOL_CALLS=5
status_during b1 "TOOL_CALLS: 7"            # over the ceiling, no EXIT_SIGNAL -> keeps polling
run_row b1 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "B1: a run over the ceiling stops (stalled)" "$(jverdict b1)" "stalled"
assert_eq "B1: the stop names the shared reason spend_ceiling" "$(jreason b1)" "spend_ceiling"
case "$(typed b1)" in *"TOOL_CALLS: <your cumulative"*) R=0 ;; *) R=1 ;; esac
assert "B1: an active ceiling asks the run to self-report TOOL_CALLS" $R

# B2 NEGATIVE CONTROL: a run UNDER the ceiling finishes cleanly, never forced to spend_ceiling.
new_env; REPO="$WORK/rB2"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
export QUEUE_MAX_TOOL_CALLS=100
status_during b2 "TOOL_CALLS: 3\nEXIT_SIGNAL: true"
run_row b2 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "B2 NC: a run under the ceiling reaches done" "$(jverdict b2)" "done"
case "$(jreason b2)" in *spend_ceiling*) R=1 ;; *) R=0 ;; esac
assert "B2 NC: a healthy run is never labelled spend_ceiling" $R

# B3 security: an OVERSIZED self-reported count (30 digits, the untrusted-input attack) must still
# TRIP the ceiling, not silently disable it via an "integer expected" error on the -ge compare.
new_env; REPO="$WORK/rB3"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
export QUEUE_MAX_TOOL_CALLS=5
status_during b3 "TOOL_CALLS: 999999999999999999999999999999"
run_row b3 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "B3: an oversized self-report still trips (clamped, not disabled)" "$(jreason b3)" "spend_ceiling"

echo
echo "--- Section C: the queue-wide spend ceiling ---"

# C1 the batch total crosses QUEUE_MAX_TOTAL_TOOL_CALLS on the first row; that row still ships, then
# the REMAINING rows are skipped (SWE-agent: the instance autosubmits before the batch halts).
new_env; REPO="$WORK/rC"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
export QUEUE_MAX_TOTAL_TOOL_CALLS=10
status_during c1 "TOOL_CALLS: 12\nEXIT_SIGNAL: true"
status_during c2 "TOOL_CALLS: 1\nEXIT_SIGNAL: true"
printf 'c1\t%s\t%s\nc2\t%s\t%s\n' "$REPO" "$WORK/p.txt" "$REPO" "$WORK/p.txt" > "$WORK/qc.tsv"
run_tsv "$WORK/qc.tsv" >/dev/null
assert_eq "C1: the first row still ships (done)" "$(jverdict c1)" "done"
assert_eq "C1: the queue-wide ceiling skips the remaining row" "$(jrows c2)" "0"

# C2 NEGATIVE CONTROL: a batch UNDER the total runs every row.
new_env; REPO="$WORK/rC2"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
export QUEUE_MAX_TOTAL_TOOL_CALLS=100
status_during d1 "TOOL_CALLS: 2\nEXIT_SIGNAL: true"
status_during d2 "TOOL_CALLS: 2\nEXIT_SIGNAL: true"
printf 'd1\t%s\t%s\nd2\t%s\t%s\n' "$REPO" "$WORK/p.txt" "$REPO" "$WORK/p.txt" > "$WORK/qd.tsv"
run_tsv "$WORK/qd.tsv" >/dev/null
assert_eq "C2 NC: a cheap batch runs the first row" "$(jverdict d1)" "done"
assert_eq "C2 NC: a cheap batch also runs the second row" "$(jverdict d2)" "done"

echo
echo "--- Section D: _status_num + backward compatibility ---"

# D1 _status_num reads the MAX numeric value across a multi-line status file (append-or-rewrite safe).
new_env
. "$QUEUE"                                   # source for the helper (main is guarded, does not run)
printf 'TOOL_CALLS: 3\nTOOL_CALLS: 9\nTOOL_CALLS: 5\n' > "$RUNDIR/e1.status"
assert_eq "D1: _status_num returns the MAX across lines" "$(_status_num e1 TOOL_CALLS)" "9"
assert_eq "D1: _status_num is 0 when the key is absent" "$(_status_num nope TOOL_CALLS)" "0"

# D2 both ceilings unset: a run reporting a huge count never trips (ceilings disabled = shipped
# behavior). The typed line also carries NO TOOL_CALLS clause when no ceiling is set.
new_env; REPO="$WORK/rD2"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
status_during f1 "TOOL_CALLS: 9999\nEXIT_SIGNAL: true"
run_row f1 "$REPO" "$WORK/p.txt" >/dev/null
assert_eq "D2: with ceilings unset a big count never trips" "$(jverdict f1)" "done"
case "$(typed f1)" in *TOOL_CALLS*) R=1 ;; *) R=0 ;; esac
assert "D2: no ceiling means no TOOL_CALLS clause on the typed line" $R

echo
echo "--- Section E: --push-only (ID-472) ---"

# E1 --push-only types a push-and-stop clause, no `gh pr create` at all, and wins over the
# draft-PR default (which would otherwise fire).
new_env; REPO="$WORK/rE1"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
status_during e1 "EXIT_SIGNAL: true"
run_row e1 "$REPO" "$WORK/p.txt" --push-only >/dev/null
case "$(typed e1)" in *"push the branch"*) R=0 ;; *) R=1 ;; esac
assert "E1: --push-only types a push-and-stop clause" $R "-- got: $(typed e1)"
case "$(typed e1)" in *"gh pr create --draft"*) R=1 ;; *) R=0 ;; esac
assert "E1: --push-only types no draft-PR clause (the prohibition mentions gh pr create only to forbid it)" $R "-- got: $(typed e1)"

# E2 --push-only wins even when --ready is also passed (no PR beats which-kind-of-PR).
new_env; REPO="$WORK/rE2"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
status_during e2 "EXIT_SIGNAL: true"
run_row e2 "$REPO" "$WORK/p.txt" --push-only --ready >/dev/null
case "$(typed e2)" in *"push the branch"*) R=0 ;; *) R=1 ;; esac
assert "E2: --push-only overrides --ready" $R "-- got: $(typed e2)"

# E3 NEGATIVE CONTROL: without --push-only the draft clause is back (the unaffected default).
new_env; REPO="$WORK/rE3"; mkrepo "$REPO"; echo p > "$WORK/p.txt"
status_during e3 "EXIT_SIGNAL: true"
run_row e3 "$REPO" "$WORK/p.txt" >/dev/null
case "$(typed e3)" in *"gh pr create --draft"*) R=0 ;; *) R=1 ;; esac
assert "E3 NC: without the flag the draft-PR clause still types" $R "-- got: $(typed e3)"

echo
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

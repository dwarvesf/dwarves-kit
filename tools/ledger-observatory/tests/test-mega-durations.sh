#!/usr/bin/env bash
# Golden-fixture + over-test for `ledger mega-durations` (goal 05K, the original
# "where does the 2-3h go" ask, folded into the ledger-observatory move).
#
# Like test-gate-yield.sh, this points at COMMITTED fixture ledger dirs
# (tests/fixtures/mega-durations/runs/*.log, tests/fixtures/mega-durations-stripped/
# runs/*.log) rather than building one inline, so the exact fixture content is
# inspectable/diffable in the PR.
#
# tests/fixtures/mega-durations/runs/ (the happy-path golden fixture, hand-verified):
#   md-a: 3 GATE rows (grill untimed, spec 1000->1300, build 1300->2200)
#         -> included rows: spec+build; wall = max(2200) - min(1000) = 1200s, n=2
#   md-b: 3 GATE rows (grill untimed, spec untimed, ship 5000->5100)
#         -> included rows: ship only; wall = 5100 - 5000 = 100s, n=1
#   md-c: 2 GATE rows (grill untimed, build untimed) -> zero included rows
#   Totals: 8 GATE rows, 3 included (2 rids: md-a wall=1200, md-b wall=100),
#           5 excluded (1 from md-a, 2 from md-b, 2 from md-c).
#
# tests/fixtures/mega-durations-stripped/runs/ (the load-bearing NC): the SAME 3 rids,
# with every `OUTCOME | <gate> | end | ...` line removed (an unclosed start bracket
# never completes a pair, per read_kit_gates' own FIFO-pairing contract) -> every
# GATE row's start_ts/end_ts is NULL. This proves the "missing timestamps" path never
# crashes and reports an honest zero, not just the happy path with real data.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

FIX="$(mktemp -d)"
# every non-kit source isolated to an absent path -- only kit_gates matters here.
export LEDGER_OBS_TIDE_DB="$FIX/nonexistent.sqlite"
export LEDGER_OBS_TGCLEANUP_DIR="$FIX/nonexistent-tg"
export LEDGER_OBS_LEARNED_MD="$FIX/nonexistent-learned.md"
export LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"
export LEDGER_OBS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"
export LEDGER_OBS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"
export LEDGER_OBS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"
export LEDGER_OBS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"
export LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb"

R() { uv run ledger "$@" 2>&1; }

echo "== M-golden: the happy-path fixture (known, hand-verified durations) =="
export DWARVES_KIT_LOG_DIR="$ROOT/tests/fixtures/mega-durations"
rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"
R rebuild >/dev/null

OUT="$(R mega-durations --json)"
has "M-golden md-a wall_seconds=1200, n_gates_timed=2" '"rid": "md-a",
      "first_start": 1000,
      "last_end": 2200,
      "n_gates_timed": 2,
      "wall_seconds": 1200' "$OUT"
has "M-golden md-b wall_seconds=100, n_gates_timed=1" '"rid": "md-b",
      "first_start": 5000,
      "last_end": 5100,
      "n_gates_timed": 1,
      "wall_seconds": 100' "$OUT"
hasnt "M-golden md-c never appears (zero timed gates, zero rows, not a fabricated 0s row)" '"rid": "md-c"' "$OUT"
has "M-golden exactly 2 rids with complete timestamps" '"n_rids_with_complete_timestamps": 2' "$OUT"
has "M-golden exactly 5 rows excluded" '"n_rows_excluded": 5' "$OUT"

echo "== M-table: --table summary line matches the JSON counts =="
TOUT="$(R mega-durations --table)"
has "M-table row count footer" "(2 rows)" "$TOUT"
has "M-table summary line" "2 rid(s) with complete timestamps (5 row(s) excluded)" "$TOUT"

echo "== M-remat: delete-and-rematerialize is byte-identical (fixture files canonical) =="
BEFORE="$(R mega-durations --json)"
rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"
AFTER="$(R mega-durations --json)"
eq "M-remat identical output" "$AFTER" "$BEFORE"

echo "== M-nc-stripped (LOAD-BEARING): fixture with every end_ts stripped -> 0 rids with
           complete timestamps, all 8 rows excluded, exit 0 (never a crash on missing data) =="
export DWARVES_KIT_LOG_DIR="$ROOT/tests/fixtures/mega-durations-stripped"
rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"
NC_RC=0
R rebuild >/dev/null 2>&1 || NC_RC=$?
eq "M-nc-stripped rebuild exits 0" "$NC_RC" "0"
NC_OUT="$(R mega-durations --json 2>&1)"
NC_RC=0
R mega-durations --json >/dev/null 2>&1 || NC_RC=$?
eq "M-nc-stripped mega-durations exits 0 (no crash on all-NULL timestamps)" "$NC_RC" "0"
has "M-nc-stripped zero rids with complete timestamps" '"n_rids_with_complete_timestamps": 0' "$NC_OUT"
has "M-nc-stripped all 8 rows excluded" '"n_rows_excluded": 8' "$NC_OUT"
has "M-nc-stripped empty durations array" '"durations": []' "$NC_OUT"
NC_TABLE="$(R mega-durations --table)"
has "M-nc-stripped --table summary reads '0 rid(s) with complete timestamps (8 row(s) excluded)'" \
    "0 rid(s) with complete timestamps (8 row(s) excluded)" "$NC_TABLE"

echo "== M-nc-deliberate-break: prove the exclusion count is falsifiable, not vacuous =="
# Simulate the bug this NC guards against: a query with no NULL-guard at all would try to
# CAST every row's (possibly NULL) start_ts/end_ts, which for THIS stripped fixture means
# every row is NULL -> min/max over an all-NULL group is NULL, not a crash, but ALSO not
# the honest "8 excluded" count -- it would silently report 0 excluded instead of 8.
BROKEN="$(uv run python3 - <<'PY' 2>&1
from ledger_observatory import materialize
cols, rows = materialize.query(
    "SELECT count(*) AS n FROM kit_gates WHERE start_ts IS NULL OR end_ts IS NULL"
)
print(rows[0][0])
PY
)"
eq "M-nc-deliberate-break the real exclusion count on the stripped fixture is 8 (not 0)" "$BROKEN" "8"

echo "== M-nc: read-only negative control (fixture files are never mutated) =="
export DWARVES_KIT_LOG_DIR="$ROOT/tests/fixtures/mega-durations"
FIXTURE_BEFORE="$(find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort)"
rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"
R rebuild >/dev/null
R mega-durations --json >/dev/null
FIXTURE_AFTER="$(find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort)"
eq "M-nc fixture ledger files byte-identical after rebuild+query" "$FIXTURE_AFTER" "$FIXTURE_BEFORE"

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

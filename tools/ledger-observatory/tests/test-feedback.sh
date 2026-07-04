#!/usr/bin/env bash
# Over-test for the feedback loop (SPEC-129 test plan). Self-contained: builds SOURCE-file
# fixtures (kit pipe-logs + a tide sqlite) with hand-verified values, points every source env
# var at them, runs the REAL end-to-end path (source -> `ledger rebuild` lens -> `ledger
# anomalies` detect/propose), and asserts. The tool's ONLY write is the gitignored staging
# buffer; NO board and NO source ledger is mutated (proven by sha256 NCs below).
#
# The load-bearing case is F-nc-noise: a near-boundary NOISE-FLOOR lens state must propose
# NOTHING. If it is weak the whole loop is worse than nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
ADDBL="$ROOT/../cc-backlog/bin/add-backlog"   # the real human-gate command (consumes staging)

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

# ---- env: point every source + the staging/board at fixtures --------------------------------
FIX="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$FIX/kitlogs"
export LEDGER_OBS_TIDE_DB="$FIX/state.sqlite"
export LEDGER_OBS_TGCLEANUP_DIR="$FIX/tg"        # empty (skip-safe)
export LEDGER_OBS_LEARNED_MD="$FIX/learned.md"   # absent (skip-safe)
export LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"  # absent -> skip-safe empty git_fixes/impl_notes
export LEDGER_OBS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"     # absent -> skip-safe empty sessions
export LEDGER_OBS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"   # absent -> skip-safe empty safety
export LEDGER_OBS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export LEDGER_OBS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb"
export CC_BACKLOG_STAGING="$FIX/backlog-staging.md"
export CC_BACKLOG_BACKLOG="$FIX/BACKLOG.md"
mkdir -p "$LEDGER_OBS_TGCLEANUP_DIR"

# a realistic board fixture (dedup source + the byte-identity victim for propose-not-autofile)
cat > "$CC_BACKLOG_BACKLOG" <<'EOF'
# Backlog
| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | pre-existing unrelated row | notes | queued |
EOF

# ---- fixture builders -----------------------------------------------------------------------
reset()         { rm -rf "$DWARVES_KIT_LOG_DIR"; mkdir -p "$DWARVES_KIT_LOG_DIR/runs";
                  rm -f "$LEDGER_OBS_TIDE_DB" "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"; }
reset_staging() { rm -f "$CC_BACKLOG_STAGING"; }

# kitrun <name> "<lane> <classified> <type> <ctype>" <n_override>
#   lane!=classified => lane_misroute=1 ; each override line => +1 gates_ovr (lane-telemetry map)
kitrun() {
  local name="$1" hdr="$2" novr="$3" f
  f="$DWARVES_KIT_LOG_DIR/runs/$name.log"
  # shellcheck disable=SC2086
  set -- $hdr
  {
    echo "2026-07-04T01:00:00Z | START | lane=$1 classified=$2 type=$3 ctype=$4 repo=fixrepo"
    local i=0
    while [ "$i" -lt "$novr" ]; do
      printf '2026-07-04T01:%02d:00Z | GATE | spec | override | waved\n' "$((i+10))"
      i=$((i+1))
    done
    echo "2026-07-04T02:00:00Z | GATE | build | ran | built"
  } > "$f"
}

# tide_costs <c1> <c2> ...  -> tide sqlite tier_b_calls, id ascending in the given cost order
tide_costs() {
  python3 - "$LEDGER_OBS_TIDE_DB" "$@" <<'PY'
import sqlite3, sys
db, costs = sys.argv[1], sys.argv[2:]
c = sqlite3.connect(db)
c.execute("CREATE TABLE tier_b_calls (id INTEGER, ts TEXT, cost_usd REAL, input_tokens INTEGER, "
          "output_tokens INTEGER, cache_creation_tokens INTEGER, cache_read_tokens INTEGER, "
          "status TEXT, backend TEXT)")
for i, cost in enumerate(costs, 1):
    c.execute("INSERT INTO tier_b_calls VALUES (?,?,?,?,?,?,?,?,?)",
              (i, f"2026-07-04T{i:02d}:00:00Z", float(cost), 100, 50, 0, 0, "ok", "deepseek"))
c.commit(); c.close()
PY
}

R()  { uv run ledger "$@" 2>&1; }
REBUILD() { uv run ledger rebuild >/dev/null 2>&1; }
staged_n() { [ -f "$CC_BACKLOG_STAGING" ] && grep -c '^## \[staged\]' "$CC_BACKLOG_STAGING" || echo 0; }

DEBT='"key": "debt"'
COST='"key": "cost_spike"'
MIS='"key": "misfire"'

# =============================================================================================
echo "== F-debt-over: SUM(gates_ovr)=6 (>5) fires debt, nothing else =="
reset; kitrun o1 "full full data data" 6; REBUILD
OUT="$(R anomalies --json)"
has  "F-debt-over fires debt"      "$DEBT" "$OUT"
hasnt "F-debt-over no cost"        "$COST" "$OUT"
hasnt "F-debt-over no misfire"     "$MIS"  "$OUT"

echo "== F-debt-under: SUM(gates_ovr)=5 (== debt_max, not >) does NOT fire =="
reset; kitrun u1 "full full data data" 5; REBUILD
hasnt "F-debt-under no debt" "$DEBT" "$(R anomalies --json)"

echo "== F-cost-spike: prior 5 x0.10 + latest 0.90 (9x) fires cost_spike =="
reset; tide_costs 0.10 0.10 0.10 0.10 0.10 0.90; REBUILD
OUT="$(R anomalies --json)"
has  "F-cost-spike fires cost"  "$COST" "$OUT"
hasnt "F-cost-spike no debt"    "$DEBT" "$OUT"
hasnt "F-cost-spike no misfire" "$MIS"  "$OUT"

echo "== F-cost-nospike: 6 x0.10 (latest not >3x median) does NOT fire =="
reset; tide_costs 0.10 0.10 0.10 0.10 0.10 0.10; REBUILD
hasnt "F-cost-nospike no cost" "$COST" "$(R anomalies --json)"

echo "== F-cost-boundary: latest 0.30 == median(0.10) x 3.0 does NOT fire =="
reset; tide_costs 0.10 0.10 0.10 0.10 0.10 0.30; REBUILD
hasnt "F-cost-boundary no cost (equality)" "$COST" "$(R anomalies --json)"

echo "== F-cost-floor: exactly 5 calls (== cost_window, one below window+1) does NOT fire =="
reset; tide_costs 0.10 0.10 0.10 0.10 5.00; REBUILD
hasnt "F-cost-floor no cost (thin)" "$COST" "$(R anomalies --json)"

echo "== F-misfire-over: 4 runs, 2 misrouted (rate 0.5 > 0.25) fires misfire =="
reset
kitrun m1 "full normal data data" 0   # lane!=cls -> misroute
kitrun m2 "full normal data data" 0   # misroute
kitrun m3 "full full data data"   0
kitrun m4 "full full data data"   0
REBUILD
OUT="$(R anomalies --json)"
has  "F-misfire-over fires misfire" "$MIS"  "$OUT"
hasnt "F-misfire-over no debt"      "$DEBT" "$OUT"
hasnt "F-misfire-over no cost"      "$COST" "$OUT"

echo "== F-misfire-boundary: 4 runs, 1 misrouted (rate == 0.25) does NOT fire =="
reset
kitrun b1 "full normal data data" 0   # 1 misroute
kitrun b2 "full full data data"   0
kitrun b3 "full full data data"   0
kitrun b4 "full full data data"   0
REBUILD
hasnt "F-misfire-boundary no misfire (equality)" "$MIS" "$(R anomalies --json)"

echo "== F-misfire-floor: 3 runs all misrouted (runs=3 < misfire_min_runs=4) does NOT fire =="
reset
kitrun f1 "full normal data data" 0
kitrun f2 "full normal data data" 0
kitrun f3 "full normal data data" 0
REBUILD
hasnt "F-misfire-floor no misfire (thin)" "$MIS" "$(R anomalies --json)"

echo "== F-nc-noise: NOISE-FLOOR near-boundary state proposes NOTHING (FALSE-POSITIVE NC) =="
reset
kitrun n1 "full full data data" 1   # ovr=1
kitrun n2 "full full data data" 1
kitrun n3 "full full data data" 1
kitrun n4 "full full data data" 1   # sum ovr=4 (<=5), 0 misroute over 4 runs
tide_costs 0.10 0.10 0.10 0.10 0.10 0.11   # latest 1.1x median (< 3x)
REBUILD
reset_staging
OUT="$(R anomalies --propose --json)"
hasnt "F-nc-noise reports no debt"    "$DEBT"    "$OUT"
hasnt "F-nc-noise reports no cost"    "$COST"    "$OUT"
hasnt "F-nc-noise reports no misfire" "$MIS"     "$OUT"
hasnt "F-nc-noise stages nothing"     '"action": "staged"' "$OUT"
eq   "F-nc-noise zero staged blocks"  "$(staged_n)" "0"

echo "== F-proposal-not-autofile: --propose stages, board byte-identical, add-backlog sees it =="
reset; kitrun p1 "full full data data" 6; REBUILD   # debt fires
reset_staging
BOARD_BEFORE="$(shasum -a 256 "$CC_BACKLOG_BACKLOG")"
OUT="$(R anomalies --propose --json)"
has  "F-pnaf reports staged"        '"action": "staged"' "$OUT"
eq   "F-pnaf one staged block"      "$(staged_n)" "1"
has  "F-pnaf staged block in buffer" "## [staged] Feedback: unpaid understanding-debt over threshold" "$(cat "$CC_BACKLOG_STAGING")"
BOARD_AFTER="$(shasum -a 256 "$CC_BACKLOG_BACKLOG")"
eq   "F-pnaf board BYTE-IDENTICAL (not auto-filed)" "$BOARD_AFTER" "$BOARD_BEFORE"
# the staged proposal is consumable by the REAL add-backlog human gate:
ADDBL_OUT="$(python3 "$ADDBL" list 2>&1)"
has  "F-pnaf add-backlog lists the proposal" "unpaid understanding-debt over threshold" "$ADDBL_OUT"

echo "== F-dedup: a second --propose stages NOTHING new (idempotent) =="
OUT2="$(R anomalies --propose --json)"   # same lens, staging already has the debt block
has  "F-dedup second run marks duplicate" '"action": "duplicate"' "$OUT2"
hasnt "F-dedup second run stages nothing"  '"action": "staged"'    "$OUT2"
eq   "F-dedup still exactly one block"     "$(staged_n)" "1"

echo "== F-threshold-flag: the one --threshold flag tunes each cutoff =="
reset; kitrun t1 "full full data data" 6; tide_costs 0.10 0.10 0.10 0.10 0.10 0.15; REBUILD
DEF="$(R anomalies --json)"
has  "F-threshold default fires debt"   "$DEBT" "$DEF"
hasnt "F-threshold default no cost (1.5x<3x)" "$COST" "$DEF"
hasnt "F-threshold debt_max=100 suppresses debt" "$DEBT" "$(R anomalies --threshold debt_max=100 --json)"
has  "F-threshold cost_multiplier=1.1 makes cost fire" "$COST" "$(R anomalies --threshold cost_multiplier=1.1 --json)"
R anomalies --threshold bogus=1 >/dev/null 2>&1; eq "F-threshold unknown key exits 2" "$?" "2"
R anomalies --threshold debt_max=abc >/dev/null 2>&1; eq "F-threshold non-numeric exits 2" "$?" "2"

echo "== F-readonly-nc: detect+propose mutates NO source ledger (byte-identical) =="
reset; kitrun r1 "full full data data" 6; tide_costs 0.10 0.10 0.10 0.10 0.10 0.90; REBUILD
reset_staging
sumsrc() { find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort; shasum -a 256 "$LEDGER_OBS_TIDE_DB"; }
SRC_BEFORE="$(sumsrc)"
R anomalies --propose >/dev/null 2>&1
SRC_AFTER="$(sumsrc)"
eq "F-readonly-nc every source ledger byte-identical" "$SRC_AFTER" "$SRC_BEFORE"

echo "== F-one-path: detection reads via SG-02 materialize only (static) =="
SRC="src/ledger_observatory/anomalies.py"
has   "F-one-path imports materialize"        "from . import materialize" "$(cat "$SRC")"
hasnt "F-one-path no direct duckdb import"    "import duckdb"              "$(cat "$SRC")"
hasnt "F-one-path no adapters bypass"         "adapters"                  "$(cat "$SRC")"
hasnt "F-one-path no raw-ledger reader bypass" "read_kit"                 "$(cat "$SRC")"

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

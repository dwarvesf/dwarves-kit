#!/usr/bin/env bash
# test-kit-gates-cost.sh -- rung-4 redteam cost checkpoint (ops-toolkit
# research/2026-07-18-rung4-cost-checkpoint.md). Validates `kit_gates`'s new `cost` column:
# a phase-scoped `| TOKENS | ... phase=<gate> |` line (emitted per round by
# lib/gate/redteam-gate.sh) FIFO-pairs onto its `redteam` GATE row the same way an
# `| OUTCOME |` bracket already pairs onto caught/start_ts/end_ts (SPEC-129 DEC-002).
#
# Golden fixture: tests/fixtures/kit-gates-cost/runs/*.log (committed, inspectable/diffable
# in the PR, per the SPEC-131 test-plan convention test-gate-yield.sh already established).
#   rt-a: 2 redteam rounds (findings cost=0.42, secure cost=0.31) + 1 unrelated `spec` gate
#         -> proves per-round FIFO order (round 1 gets 0.42, round 2 gets 0.31, never
#            swapped) AND that a non-redteam gate's cost stays NULL.
#   rt-b: 1 round, TOKENS cost=notanumber -> cost NULL, no crash (malformed input).
#   rt-c: 1 round, NO phase-scoped TOKENS line at all (a round whose cost call never landed,
#         e.g. the AC6 failed-then-retried case in test-redteam-gate.sh) -> cost NULL, honest,
#         never fabricated.
#   rt-d: 1 round, plus an UNSCOPED (no phase=) rid-wide TOKENS line -> cost NULL for the
#         gate row; the unscoped line must never be mistaken for this gate's cost.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }

FIX="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$ROOT/tests/fixtures/kit-gates-cost"
export STATS_TIDE_DB="$FIX/nonexistent.sqlite"
export STATS_TGCLEANUP_DIR="$FIX/nonexistent-tg"
export STATS_LEARNED_MD="$FIX/nonexistent-learned.md"
export STATS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"
export STATS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"
export STATS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"
export STATS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"
export STATS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"
export STATS_DB_REMOVED="$FIX/lens.duckdb"

R() { uv run stats "$@" 2>&1; }

FIXTURE_BEFORE="$(find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort)"

echo "== C-rebuild: kit_gates materializes over the cost fixture =="
rm -f "$STATS_DB_REMOVED" "$STATS_DB_REMOVED.wal"
R rebuild >/dev/null

ROWS="$(R show kit_gates --json)"

echo "== C-order: rt-a's two rounds keep FIFO order -- round 1 gets 0.42, round 2 gets 0.31 (never swapped) =="
has "C-order rt-a round 1 (findings) paired to cost=0.42" '"rid": "rt-a",
    "gate": "redteam",
    "outcome": "ran",
    "caught": true,
    "reason": "round=1 verdict=findings 2 findings, fixed",
    "start_ts": "1000",
    "end_ts": "1030",
    "cost": 0.42' "$ROWS"
has "C-order rt-a round 2 (secure) paired to cost=0.31" '"rid": "rt-a",
    "gate": "redteam",
    "outcome": "ran",
    "caught": false,
    "reason": "round=2 verdict=secure",
    "start_ts": "1030",
    "end_ts": "1050",
    "cost": 0.31' "$ROWS"

echo "== C-unrelated: rt-a's non-redteam 'spec' gate has cost=null (never contaminated) =="
has "C-unrelated rt-a spec gate cost=null" '"rid": "rt-a",
    "gate": "spec",
    "outcome": "ran",
    "caught": null,
    "reason": "drafted the spec",
    "start_ts": null,
    "end_ts": null,
    "cost": null' "$ROWS"

echo "== C-malformed: rt-b's cost=notanumber lands as null, not a crash, not a fake 0 =="
has "C-malformed rt-b cost=null on an unparseable TOKENS cost=" '"rid": "rt-b",
    "gate": "redteam",
    "outcome": "ran",
    "caught": true,
    "reason": "round=1 verdict=findings malformed cost, must not crash",
    "start_ts": "2000",
    "end_ts": "2010",
    "cost": null' "$ROWS"

echo "== C-orphan: rt-c's round with NO phase-scoped TOKENS line at all -> cost=null, honest =="
has "C-orphan rt-c cost=null (no TOKENS line to pair)" '"rid": "rt-c",
    "gate": "redteam",
    "outcome": "ran",
    "caught": true,
    "reason": "round=1 verdict=capped a failed round retried without ever emitting a cost line",
    "start_ts": "3000",
    "end_ts": "3005",
    "cost": null' "$ROWS"

echo "== C-unscoped: rt-d's unscoped (no phase=) TOKENS line never pairs onto the redteam gate =="
has "C-unscoped rt-d cost=null (the rid-wide TOKENS line is not phase-tagged)" '"rid": "rt-d",
    "gate": "redteam",
    "outcome": "ran",
    "caught": false,
    "reason": "round=1 verdict=secure an unscoped rid-wide TOKENS line must never pair here",
    "start_ts": "4000",
    "end_ts": "4010",
    "cost": null' "$ROWS"

echo "== C-sum: cost is genuine arithmetic (DOUBLE), not display-only text -- SUM over rt-a's 2 rounds =="
SUM="$(uv run python3 - <<'PY' 2>&1
from stats import materialize
cols, rows = materialize.query(
    "SELECT round(sum(cost), 2) AS total FROM kit_gates WHERE rid = 'rt-a' AND gate = 'redteam'"
)
print(rows[0][0])
PY
)"
if [ "$SUM" = "0.73" ]; then ok "C-sum rt-a redteam cost sums to 0.73 (0.42 + 0.31, real arithmetic)"; else bad "C-sum want 0.73, got '$SUM'"; fi

echo "== C-nc-deliberate-break: prove the malformed-cost NULL-exclusion is falsifiable, not vacuous =="
# If a future edit coerced an unparseable cost= to 0.0 instead of NULL, this count would go
# from 1 to 0 (a fabricated-zero would silently join the SUM/AVG above and understate cost).
BROKEN="$(uv run python3 - <<'PY' 2>&1
from stats import materialize
cols, rows = materialize.query(
    "SELECT count(*) AS n FROM kit_gates WHERE gate = 'redteam' AND cost IS NULL"
)
print(rows[0][0])
PY
)"
if [ "$BROKEN" = "3" ]; then ok "C-nc-deliberate-break exactly 3 redteam rows are NULL-cost (rt-b malformed + rt-c orphan + rt-d unscoped)"; else bad "C-nc-deliberate-break want 3 NULL-cost redteam rows, got '$BROKEN'"; fi

echo "== C-mega-durations: OUTCOME brackets on redteam rounds make mega-durations pick them up (requirement b) =="
# No gate-name whitelist in mega-durations (cli.py's own docstring) -- this just proves the
# OUTCOME start/end pairs redteam-gate.sh emits are real, complete brackets that the EXISTING
# wall-time query already reads, with zero mega-durations changes needed.
MD="$(R mega-durations --json)"
has "C-mega-durations rt-a wall_seconds=50 (2 redteam rounds, min(1000)..max(1050))" '"rid": "rt-a",
      "first_start": 1000,
      "last_end": 1050,
      "n_gates_timed": 2,
      "wall_seconds": 50' "$MD"
has "C-mega-durations rt-c (orphan-cost round) still timed (5s) -- a missing cost never blocks the duration read" '"rid": "rt-c",
      "first_start": 3000,
      "last_end": 3005,
      "n_gates_timed": 1,
      "wall_seconds": 5' "$MD"

echo "== C-remat: delete-and-rematerialize is byte-identical (fixture files canonical) =="
BEFORE="$(R show kit_gates --json)"
rm -f "$STATS_DB_REMOVED" "$STATS_DB_REMOVED.wal"
AFTER="$(R show kit_gates --json)"
if [ "$BEFORE" = "$AFTER" ]; then ok "C-remat identical output"; else bad "C-remat output differs after delete+rebuild"; fi

echo "== C-nc: read-only negative control (fixture files are never mutated) =="
FIXTURE_AFTER="$(find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort)"
if [ "$FIXTURE_BEFORE" = "$FIXTURE_AFTER" ]; then ok "C-nc fixture ledger files byte-identical after rebuild+queries"; else bad "C-nc a fixture file changed"; fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

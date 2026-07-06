#!/usr/bin/env bash
# Golden-fixture + over-test for `kit_gates` / `ledger gate-yield` (SPEC-131 test plan).
#
# Unlike the other test-*.sh files (which build their fixture inline in $(mktemp -d) every
# run), this one points at a COMMITTED fixture ledger dir
# (tests/fixtures/kit-gates/runs/*.log), per the goal file's "golden fixture: a committed
# fixture ledger dir with known rids" requirement, so the exact fixture content is
# inspectable/diffable in the PR, not regenerated blind on every run. The test never writes
# into the fixture dir; only the (mktemp) lens db + unrelated sources are ephemeral.
#
# The FP-NC (F-nc) is load-bearing: `fix-legit-skip.log`'s `ui-design` gate is skipped twice
# with NO caught signal anywhere in the whole fixture set. gate-yield MUST report it with its
# 2 skips (not drop the gate, not report skipped=0, not mislabel it as 100% ceremony with no
# skip visibility) , a benchmark that silently drops or mislabels a legitimate skip is worse
# than none.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }

# ---- env: kit source points at the COMMITTED fixture; everything else is empty/absent ------
FIX="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$ROOT/tests/fixtures/kit-gates"
export STATS_TIDE_DB="$FIX/state.sqlite"          # absent -> skip-safe empty table
export STATS_TGCLEANUP_DIR="$FIX/tg"              # empty -> skip-safe
export STATS_LEARNED_MD="$FIX/learned.md"         # absent -> skip-safe
export STATS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"     # absent -> skip-safe empty sessions
export STATS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"   # absent -> skip-safe empty safety
export STATS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export STATS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export STATS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"  # absent -> skip-safe empty git_fixes/impl_notes
export STATS_DB_REMOVED="$FIX/lens.duckdb"
mkdir -p "$STATS_TGCLEANUP_DIR"

R() { uv run stats "$@" 2>&1; }

FIXTURE_BEFORE="$(find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort)"

echo "== G-rebuild: kit_gates materializes, one row per GATE line across the fixture set =="
OUT="$(R rebuild)"
has "G-rebuild kit_gates=11" '"kit_gates": 11' "$OUT"

echo "== G-rows: exact per-row values (rid, gate, outcome, caught, reason, start_ts, end_ts) =="
ROWS="$(R show kit_gates --json)"
# Each assertion below targets one (rid, gate) row via a distinctive substring; no embedded
# newlines (bash string-vs-JSON-pretty-print fragility), one field-combination per check.
has "G-rows fix-happy grill skipped, reason present" '"rid": "fix-happy",
    "gate": "grill",
    "outcome": "skipped",
    "caught": null,
    "reason": "single well-scoped sub-goal, no open branches",' "$ROWS"
has "G-rows fix-happy ship override" '"rid": "fix-happy",
    "gate": "ship",
    "outcome": "override",' "$ROWS"
has "G-rows fix-outcome build caught=true w/ start_ts/end_ts" '"rid": "fix-outcome",
    "gate": "build",
    "outcome": "ran",
    "caught": true,
    "reason": "built with a caught OUTCOME bracket",
    "start_ts": "1000",
    "end_ts": "1300"' "$ROWS"
has "G-rows fix-malformed grill missing-reason (reason=null, no crash)" '"rid": "fix-malformed",
    "gate": "grill",
    "outcome": "skipped",
    "caught": null,
    "reason": null,' "$ROWS"
has "G-rows fix-malformed spec#1 malformed at= kept raw, caught=null" '"rid": "fix-malformed",
    "gate": "spec",
    "outcome": "ran",
    "caught": null,
    "reason": "first spec call, ok",
    "start_ts": "notanumber",
    "end_ts": "2000"' "$ROWS"
has "G-rows fix-malformed spec#2 duplicate gate, no bracket left" '"rid": "fix-malformed",
    "gate": "spec",
    "outcome": "ran",
    "caught": null,
    "reason": "second spec call, duplicate gate name in one rid",
    "start_ts": null,
    "end_ts": null' "$ROWS"
N_SPEC_FIXMALFORMED="$(printf '%s' "$ROWS" | grep -c '"rid": "fix-malformed"' || true)"
if [ "$N_SPEC_FIXMALFORMED" -eq 3 ]; then ok "G-rows fix-malformed contributes exactly 3 rows (grill + 2x spec, malformed line adds none)"; else bad "G-rows fix-malformed row count -> want 3, got $N_SPEC_FIXMALFORMED"; fi
N_TOTAL="$(printf '%s' "$ROWS" | grep -c '"rid":' || true)"
if [ "$N_TOTAL" -eq 11 ]; then ok "G-rows exactly 11 rows total (one per GATE line, none dropped)"; else bad "G-rows want 11 rows, got $N_TOTAL"; fi

echo "== G-yield: exact gate-yield aggregation per gate (hand-verified against the fixture) =="
YIELD="$(R gate-yield --json)"
has "G-yield build: ran=2" '"gate": "build",
    "ran": 2,' "$YIELD"
has "G-yield build: caught=1 total=2 override_pct=0.0" '"caught": 1,
    "total": 2,
    "override_pct": 0.0' "$YIELD"
has "G-yield grill: ran=0 override=0 skipped=2" '"gate": "grill",
    "ran": 0,
    "override": 0,
    "skipped": 2,' "$YIELD"
has "G-yield ship: override=1 override_pct=100.0" '"gate": "ship",
    "ran": 0,
    "override": 1,
    "skipped": 0,
    "caught": 0,
    "total": 1,
    "override_pct": 100.0' "$YIELD"
has "G-yield spec: ran=4 caught=0" '"gate": "spec",
    "ran": 4,
    "override": 0,
    "skipped": 0,
    "caught": 0,' "$YIELD"
has "G-yield ui-design: ran=0 skipped=2 caught=0" '"gate": "ui-design",
    "ran": 0,
    "override": 0,
    "skipped": 2,
    "caught": 0,' "$YIELD"

echo "== F-nc: FALSE-POSITIVE negative control (load-bearing) =="
# ui-design has ZERO caught signal anywhere in the fixture (no OUTCOME bracket for it at all)
# AND is legitimately skipped both times it was recorded. It must be REPORTED with its 2 skips,
# not dropped from the table and not silently zeroed out.
UI_ROW="$(printf '%s' "$YIELD" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    if r["gate"] == "ui-design":
        print(json.dumps(r))
        sys.exit(0)
print("MISSING")
')"
if [ "$UI_ROW" = "MISSING" ]; then
  bad "F-nc ui-design DROPPED from gate-yield (a legitimate skip must never disappear)"
else
  has "F-nc ui-design present with its real skip count" '"skipped": 2' "$UI_ROW"
  has "F-nc ui-design caught=0 (never mislabeled, no caught signal exists)" '"caught": 0' "$UI_ROW"
  has "F-nc ui-design NOT counted as ran/override" '"ran": 0, "override": 0' "$UI_ROW"
  ok "F-nc ui-design reported honestly: skipped=2, caught=0, not dropped, not mislabeled"
fi

echo "== F-nc-deliberate-break: prove the FP-NC is falsifiable, not vacuous =="
# Simulate the bug this NC guards against: a query that GROUP BYs only rows with outcome='ran'
# would silently drop ui-design (0 ran rows) from the result entirely.
BROKEN="$(uv run python3 - <<'PY' 2>&1
from stats import materialize
cols, rows = materialize.query(
    "SELECT gate, count(*) AS n FROM kit_gates WHERE outcome = 'ran' GROUP BY gate ORDER BY gate"
)
import json
print(json.dumps([dict(zip(cols, r)) for r in rows]))
PY
)"
hasnt "F-nc-deliberate-break a ran-only GROUP BY drops ui-design (the bug the real query avoids)" '"gate": "ui-design"' "$BROKEN"

echo "== O-plan: /kit:test-plan-shaped over-test pass (parser edge cases beyond the golden fixture) =="
# These target read_kit_gates() directly (no rebuild/CLI round-trip needed): a missing runs
# dir, a file with ZERO valid GATE/OUTCOME lines, and an unclosed OUTCOME start bracket (no
# matching end). None of these are covered by the golden fixture files above.
OVER="$(uv run python3 - <<'PY' 2>&1
import tempfile
from pathlib import Path
from stats import adapters

results = []

# O1: runs dir does not exist at all -> empty columns + empty rows, no exception.
cols, rows = adapters.read_kit_gates(Path("/nonexistent-o1-dir-xyz"))
results.append(("O1-missing-dir", cols == adapters.KIT_GATES_COLUMNS and rows == []))

with tempfile.TemporaryDirectory() as td:
    runs = Path(td) / "runs"
    runs.mkdir()

    # O2: a file with zero valid GATE/OUTCOME lines (only noise + a START line).
    (runs / "o2-noise.log").write_text(
        "2026-07-04T09:00:00Z | START | lane=normal classified=normal type=docs ctype=docs repo=x\n"
        "garbage garbage garbage\n"
        "\n"
    )
    cols2, rows2 = adapters.read_kit_gates(runs)
    results.append(("O2-zero-valid-lines", rows2 == []))

    # O3: an OUTCOME start bracket with NO matching end (phase never closes).
    (runs / "o3-unclosed.log").write_text(
        "2026-07-04T10:00:00Z | START | lane=normal classified=normal type=docs ctype=docs repo=x\n"
        "2026-07-04T10:00:01Z | GATE | review | ran | reviewed\n"
        "2026-07-04T10:00:02Z | OUTCOME | review | start | at=500\n"
    )
    cols3, rows3 = adapters.read_kit_gates(runs)
    row = next((r for r in rows3 if r[0] == "o3-unclosed"), None)
    ok3 = row is not None and row[1] == "review" and row[2] == "ran" and row[3] is None and row[5] is None and row[6] is None
    results.append(("O3-unclosed-bracket-no-crash-no-fake-caught", ok3))

for name, passed in results:
    print(f"{name}={'OK' if passed else 'FAIL'}")
PY
)"
has "O1-missing-dir OK (empty columns+rows, no exception)"                 "O1-missing-dir=OK" "$OVER"
has "O2-zero-valid-lines OK (noise-only file yields zero rows, no crash)"  "O2-zero-valid-lines=OK" "$OVER"
has "O3-unclosed-bracket OK (no matching end -> caught/start_ts/end_ts stay NULL, no fake pairing)" "O3-unclosed-bracket-no-crash-no-fake-caught=OK" "$OVER"

echo "== G-remat: delete-and-rematerialize is byte-identical (fixture files canonical) =="
BEFORE="$(R show kit_gates --json)"
rm -f "$STATS_DB_REMOVED" "$STATS_DB_REMOVED.wal"
AFTER="$(R show kit_gates --json)"
if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then ok "G-remat identical output"; else bad "G-remat output differs after delete+rebuild"; fi

echo "== G-nc: read-only negative control (fixture files are never mutated) =="
FIXTURE_AFTER="$(find "$DWARVES_KIT_LOG_DIR" -type f -exec shasum -a 256 {} \; | sort)"
if [ "$FIXTURE_BEFORE" = "$FIXTURE_AFTER" ]; then ok "G-nc fixture ledger files byte-identical after rebuild+queries"; else bad "G-nc a fixture file changed"; fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Over-test for the `ledger` CLI (SPEC-127 test plan). Self-contained: builds a fixture
# set for ALL 4 source shapes (pipe-log kit corpus + sqlite tide + json tg-cleanup +
# markdown learned-ledger), points every source env var at it, and asserts hand-verified
# VALUES (not just non-empty counts). No live source is read; no source is mutated.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
# assert: <label> <needle> <haystack>
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }

# ---- fixtures ---------------------------------------------------------------
FIX="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$FIX/kitlogs"
export LEDGER_OBS_TIDE_DB="$FIX/state.sqlite"
export LEDGER_OBS_TGCLEANUP_DIR="$FIX/tg"
export LEDGER_OBS_LEARNED_MD="$FIX/learned-ledger.md"
export LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"  # absent -> skip-safe empty git_fixes/impl_notes
export LEDGER_OBS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"     # absent -> skip-safe empty sessions
export LEDGER_OBS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"   # absent -> skip-safe empty safety
export LEDGER_OBS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export LEDGER_OBS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb"
# DWARVES_KIT_LIB defaults to ~/.claude/dwarves-kit/lib (lane-telemetry.sh lives there).

mkdir -p "$DWARVES_KIT_LOG_DIR/runs" "$LEDGER_OBS_TGCLEANUP_DIR"

# 1) kit pipe-log corpus (two runs; known lanes) -- read via lane-telemetry _rows reuse
cat > "$DWARVES_KIT_LOG_DIR/runs/fixrun-full.log" <<'EOF'
2026-07-04T01:00:00Z | START | lane=full classified=full type=data-tool ctype=data-tool repo=fixrepo
2026-07-04T01:05:00Z | GATE | spec | ran | drafted with a reason | that contains a pipe
2026-07-04T01:06:00Z | GATE | ship | ran | shipped
EOF
cat > "$DWARVES_KIT_LOG_DIR/runs/fixrun-normal.log" <<'EOF'
2026-07-04T02:00:00Z | START | lane=normal classified=normal type=docs ctype=docs repo=fixrepo
2026-07-04T02:05:00Z | GATE | build | ran | built
EOF

# 2) tide state.sqlite (sqlite shape). route='full' plants a JOIN key onto kit_runs.lane.
python3 - "$LEDGER_OBS_TIDE_DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE moves (id INTEGER, ts TEXT, source_path TEXT, target_path TEXT, content_sha TEXT, size_bytes INTEGER, route TEXT, confidence REAL, ai_response_json TEXT, undone_at TEXT)")
c.execute("INSERT INTO moves VALUES (1,'2026-07-04T03:00:00Z','/dl/a.pdf','/doc/a.pdf','sha_fixture_aaa',111,'full',0.9,'{}',NULL)")
c.execute("INSERT INTO moves VALUES (2,'2026-07-04T03:01:00Z','/dl/b.pdf','/doc/b.pdf','sha_fixture_bbb',222,'normal',0.8,'{}','2026-07-04T04:00:00Z')")
c.execute("CREATE TABLE tier_b_calls (id INTEGER, ts TEXT, cost_usd REAL, input_tokens INTEGER, output_tokens INTEGER, cache_creation_tokens INTEGER, cache_read_tokens INTEGER, status TEXT, backend TEXT)")
c.execute("INSERT INTO tier_b_calls VALUES (1,'2026-07-04T03:00:00Z',0.42,1200,340,0,5000,'ok','deepseek')")
c.commit()
PY

# 3) tg-cleanup json -- BOTH shapes (synthetic; no real data)
cat > "$LEDGER_OBS_TGCLEANUP_DIR/review.json" <<'EOF'
[{"id":-1001,"title":"Example Alpha","kind":"basic_group","username":null,"member_count":3,"last_message_date":"2026-01-01T00:00:00+00:00","unread_count":0,"muted":false,"access_hash":null,"verified":false,"scam":false,"fake":false}]
EOF
cat > "$LEDGER_OBS_TGCLEANUP_DIR/keep-auto.json" <<'EOF'
{"keep_personal":[{"id":-1002,"title":"Kept Bravo","kind":"supergroup","username":"kb","member_count":9,"last_message_date":"2026-02-02T00:00:00+00:00","unread_count":1,"muted":true,"access_hash":123,"verified":false,"scam":false,"fake":false}]}
EOF

# 4) learned-ledger.md (markdown table shape)
cat > "$LEDGER_OBS_LEARNED_MD" <<'EOF'
# learned-ledger

## Schema
(ignored)

## Ledger

| date | item | kind | home | status |
|---|---|---|---|---|
| 2026-07-04 | fixture-concept | decision | til | queued |
| 2026-07-03 | second-fixture | insight | research | flushed:x.md |
EOF

R() { uv run ledger "$@" 2>&1; }

echo "== R-rebuild: materialize the db from the files =="
OUT="$(R rebuild)"
has "R-rebuild kit_runs>0"   '"kit_runs": 2' "$OUT"
has "R-rebuild tide_moves>0" '"tide_moves": 2' "$OUT"
has "R-rebuild tg_dialogs>0" '"tg_dialogs": 2' "$OUT"
has "R-rebuild learned>0"    '"learned": 2' "$OUT"

echo "== R-show: structured output, both formats =="
has "R-show-json (value)"  '"item": "fixture-concept"' "$(R show learned --json)"
TBL="$(R show learned --table)"
has "R-show-table (value)" 'fixture-concept' "$TBL"
has "R-show-table (box)"   '+---' "$TBL"

echo "== R-join: a real cross-ledger JOIN (kit_runs x tide_moves) =="
JOIN="$(R query "SELECT k.rid, k.lane, m.content_sha FROM kit_runs k JOIN tide_moves m ON m.route = k.lane ORDER BY k.rid" --json)"
has "R-join rows (full run x full-route move)" '"content_sha": "sha_fixture_aaa"' "$JOIN"
has "R-join key (lane full)" '"lane": "full"' "$JOIN"
# the undone (route=normal) move joins the normal run too -> exactly 2 joined rows
NJOIN="$(R query "SELECT count(*) AS n FROM kit_runs k JOIN tide_moves m ON m.route = k.lane" --json)"
has "R-join count = 2" '"n": 2' "$NJOIN"

echo "== R-remat: delete-and-rematerialize is byte-identical (files canonical) =="
BEFORE="$(R show kit_runs --json)"
rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"
AFTER="$(R show kit_runs --json)"   # lazy-rebuilds from the files first
if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then ok "R-remat identical output"; else bad "R-remat output differs after delete+rebuild"; fi

echo "== R-formats: cross-format read correctness across all 4 shapes (values) =="
has "R-formats-kit (pipe-log)"   '"rid": "fixrun-full"' "$(R show kit_runs --json)"
has "R-formats-kit lane"         '"lane": "full"'       "$(R show kit_runs --json)"
has "R-formats-sqlite (sqlite)"  'sha_fixture_aaa'      "$(R show tide_moves --json)"
TG="$(R show tg_dialogs --json)"
has "R-formats-json title"       '"title": "Kept Bravo"'   "$TG"
has "R-formats-json category"    '"category": "keep_personal"' "$TG"   # carried from object key
has "R-formats-json array-shape" '"title": "Example Alpha"'    "$TG"   # the flat-array file
has "R-formats-md (markdown)"    '"home": "til"'        "$(R show learned --json)"

echo "== R-nc: read-only negative control (a query mutates NO source) =="
sumall() { find "$DWARVES_KIT_LOG_DIR" "$LEDGER_OBS_TGCLEANUP_DIR" -type f -exec shasum -a 256 {} \; | sort; \
           shasum -a 256 "$LEDGER_OBS_TIDE_DB" "$LEDGER_OBS_LEARNED_MD"; }
NC_BEFORE="$(sumall)"
R query "SELECT count(*) FROM kit_runs" >/dev/null
R query "SELECT * FROM tide_moves JOIN tg_dialogs ON 1=1 LIMIT 1" >/dev/null
NC_AFTER="$(sumall)"
if [ "$NC_BEFORE" = "$NC_AFTER" ]; then ok "R-nc every source byte-identical after queries"; else bad "R-nc a source changed"; fi

echo "== R-guard: a write-shaped query is refused and cannot mutate =="
R query "DELETE FROM kit_runs" >/dev/null 2>&1; G1=$?
R query "DROP TABLE learned" >/dev/null 2>&1;  G2=$?
if [ "$G1" -ne 0 ]; then ok "R-guard DELETE refused (exit $G1)"; else bad "R-guard DELETE not refused"; fi
if [ "$G2" -ne 0 ]; then ok "R-guard DROP refused (exit $G2)";   else bad "R-guard DROP not refused"; fi
has "R-guard db intact after refusal" '"n": 2' "$(R query "SELECT count(*) AS n FROM kit_runs" --json)"

echo "== R-guard-pragma: the PRAGMA/multi-statement filesystem-write bypass is closed (HIGH-1) =="
# A read-verb-FIRST multi-statement chain that (pre-fix) wrote a source file via
# PRAGMA profiling_output. Must be REFUSED and the source .json left byte-identical.
VICTIM="$LEDGER_OBS_TGCLEANUP_DIR/keep-auto.json"
V_BEFORE="$(shasum -a 256 "$VICTIM")"
R query "PRAGMA enable_profiling='json'; PRAGMA profiling_output='$VICTIM'; SELECT 1" >/dev/null 2>&1; GP=$?
if [ "$GP" -ne 0 ]; then ok "R-guard-pragma multi-statement PRAGMA refused (exit $GP)"; else bad "R-guard-pragma NOT refused"; fi
R query "PRAGMA profiling_output='$VICTIM'" >/dev/null 2>&1; GP2=$?
if [ "$GP2" -ne 0 ]; then ok "R-guard-pragma lone PRAGMA refused (exit $GP2)"; else bad "R-guard-pragma lone PRAGMA NOT refused"; fi
R query "COPY (SELECT 1) TO '$VICTIM'" >/dev/null 2>&1; GP3=$?
if [ "$GP3" -ne 0 ]; then ok "R-guard-pragma COPY TO refused (exit $GP3)"; else bad "R-guard-pragma COPY TO NOT refused"; fi
V_AFTER="$(shasum -a 256 "$VICTIM")"
if [ "$V_BEFORE" = "$V_AFTER" ]; then ok "R-guard-pragma source file byte-identical (no write escaped)"; else bad "R-guard-pragma SOURCE FILE MUTATED"; fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

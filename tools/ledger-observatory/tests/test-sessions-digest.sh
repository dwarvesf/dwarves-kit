#!/usr/bin/env bash
# Over-test for the `sessions`/`safety` adapters + `ledger digest` (SPEC-135 test plan).
# Self-contained: builds session transcript jsonl fixtures + a secret-guard log fixture +
# (for the digest bridge) a kit_gates run-ledger + a generated git repo, points every source
# env var at fixtures, runs the REAL end-to-end path (source -> `ledger rebuild` -> CLI), and
# asserts.
#
# THE LOAD-BEARING CASE (PRIV-nc): a fixture transcript embeds the literal string
# `FAKE-SECRET-a1b2c3` in BOTH a `tool_result.content` value AND a `custom-title` line (the two
# confirmed-real leak surfaces named in SPEC-135's Problem section). The test asserts that
# string appears in ZERO materialized tables/columns while the fixture's numeric `sessions` row
# DOES exist. PRIV-nc-positive-control proves the RAW fixture file actually contains the string
# (so the negative result isn't vacuous). The FURTHER falsifiability proof (temporarily
# widening the schema/parser to also capture the forbidden field, observing the assertion turn
# RED, then restoring) is a manual Build-time step recorded in
# `docs/verification/sessions-digest.md`'s Confirmation table, per this tool's own established
# convention for every prior sub-goal's deliberate-break NC (SPEC-131/132/133/134).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
ADDBL="$ROOT/../cc-backlog/bin/add-backlog"

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

FIX="$(mktemp -d)"
SESSIONS_DIR="$FIX/sessions"
GITREPO="$FIX/repo"
KITLOG="$FIX/kit-runs"
SAFETY_LOG="$FIX/secret-guard.log"
mkdir -p "$SESSIONS_DIR" "$KITLOG/runs"

# ---- build the git fixture: a real repo, controlled dates, no interactive prompts ----------
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q -b main --template=
git -C "$GITREPO" config user.name "Fixture Bot"
git -C "$GITREPO" config user.email "fixture@example.com"
git -C "$GITREPO" config commit.gpgsign false

commit() {
  # commit <relpath> <content> <subject> <iso8601-date>  (SPEC-132/133/134 precedent)
  local rel="$1" content="$2" subject="$3" date="$4"
  mkdir -p "$(dirname "$GITREPO/$rel")"
  printf '%s\n' "$content" > "$GITREPO/$rel"
  git -C "$GITREPO" add "$rel" >/dev/null
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$GITREPO" commit -q -m "$subject" >/dev/null
}

gate_row() {
  # gate_row <rid> <gate> <outcome>  (SPEC-131/134 precedent, no OUTCOME bracket needed here)
  local rid="$1" gate="$2" outcome="$3"
  local f="$KITLOG/runs/$rid.log"
  {
    echo "2026-07-01T00:00:00Z | START | lane=full classified=full type=feat ctype=feat repo=fixrepo"
    echo "2026-07-01T00:00:03Z | GATE | $gate | $outcome"
  } > "$f"
}

# ---- env: point every source at the fixtures (isolate ALL of them, not just this sub-goal's,
#      per SG-03's cross-suite-regression lesson: an unisolated shared source silently pollutes
#      an unrelated suite's assertions) --------------------------------------------------------
export DWARVES_KIT_LOG_DIR="$KITLOG"
export LEDGER_OBS_GIT_REPO_DIR="$GITREPO"
export LEDGER_OBS_TIDE_DB="$FIX/state.sqlite"
export LEDGER_OBS_TGCLEANUP_DIR="$FIX/tg"
export LEDGER_OBS_LEARNED_MD="$FIX/learned.md"
export LEDGER_OBS_SESSIONS_DIR="$SESSIONS_DIR"
export LEDGER_OBS_SECRET_GUARD_LOG="$SAFETY_LOG"
export LEDGER_OBS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export LEDGER_OBS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb"
export CC_BACKLOG_STAGING="$FIX/backlog-staging.md"
export CC_BACKLOG_BACKLOG="$FIX/BACKLOG.md"
mkdir -p "$LEDGER_OBS_TGCLEANUP_DIR"

cat > "$CC_BACKLOG_BACKLOG" <<'EOF'
# Backlog
| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | pre-existing unrelated row | notes | queued |
EOF

R()  { uv run ledger "$@" 2>&1; }
REBUILD() { uv run ledger rebuild >/dev/null 2>&1; }
reset_sessions() { rm -rf "$SESSIONS_DIR"; mkdir -p "$SESSIONS_DIR"; }
reset_kit()      { rm -rf "$KITLOG/runs"; mkdir -p "$KITLOG/runs"; }
reset_safety()   { rm -f "$SAFETY_LOG"; }
reset_db()       { rm -f "$LEDGER_OBSERVATORY_DB" "$LEDGER_OBSERVATORY_DB.wal"; }
reset_staging()  { rm -f "$CC_BACKLOG_STAGING"; }
reset_all()      { reset_sessions; reset_kit; reset_safety; reset_db; }
staged_n() { [ -f "$CC_BACKLOG_STAGING" ] && grep -c '^## \[staged\]' "$CC_BACKLOG_STAGING" || echo 0; }

QROW() {
  # QROW <sql> -> the single scalar value of a one-row-one-column query, via the SAME
  # materialize.query() path the CLI uses (no second read path).
  uv run python3 - "$1" <<'PY'
import sys
from ledger_observatory import materialize
cols, rows = materialize.query(sys.argv[1])
print(rows[0][0] if rows and rows[0] else "")
PY
}

# =============================================================================================
echo "== golden: a session file with KNOWN token/tool-call/error/compaction/canary counts =="
reset_all
mkdir -p "$SESSIONS_DIR/proj-golden"
cat > "$SESSIONS_DIR/proj-golden/golden-session.jsonl" <<EOF
{"type":"user","timestamp":"2026-07-01T10:00:00.000Z","message":{"role":"user","content":"hello"}}
{"type":"assistant","timestamp":"2026-07-01T10:00:05.000Z","message":{"role":"assistant","stop_reason":"tool_use","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":10,"cache_creation_input_tokens":5},"content":[{"type":"text","text":"Let me check."},{"type":"tool_use","id":"call_1","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","timestamp":"2026-07-01T10:00:06.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"call_1","content":"total 0","is_error":false}]}}
{"type":"assistant","timestamp":"2026-07-01T10:00:07.000Z","message":{"role":"assistant","stop_reason":"tool_use","usage":{"input_tokens":120,"output_tokens":60,"cache_read_input_tokens":12,"cache_creation_input_tokens":6},"content":[{"type":"tool_use","id":"call_2","name":"Read","input":{}}]}}
{"type":"user","timestamp":"2026-07-01T10:00:08.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"call_2","content":"boom","is_error":true}]}}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-07-01T10:00:09.000Z"}
{"type":"assistant","timestamp":"2026-07-01T10:00:10.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":50,"output_tokens":25,"cache_read_input_tokens":5,"cache_creation_input_tokens":2},"content":[{"type":"text","text":"Done, no canary here."}]}}
{"type":"assistant","timestamp":"2026-07-01T10:00:15.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":30,"output_tokens":15,"cache_read_input_tokens":3,"cache_creation_input_tokens":1},"content":[{"type":"text","text":"All good.\n\n🐱 Neko-san"}]}}
EOF
REBUILD
eq "golden session_id"        "$(QROW "SELECT session_id FROM sessions WHERE project_slug='proj-golden'")"        "golden-session"
eq "golden first_ts"          "$(QROW "SELECT first_ts FROM sessions WHERE project_slug='proj-golden'")"          "2026-07-01T10:00:00.000Z"
eq "golden last_ts"           "$(QROW "SELECT last_ts FROM sessions WHERE project_slug='proj-golden'")"           "2026-07-01T10:00:15.000Z"
eq "golden duration_s"        "$(QROW "SELECT duration_s FROM sessions WHERE project_slug='proj-golden'")"        "15"
eq "golden input_tokens"      "$(QROW "SELECT input_tokens FROM sessions WHERE project_slug='proj-golden'")"      "300"
eq "golden output_tokens"     "$(QROW "SELECT output_tokens FROM sessions WHERE project_slug='proj-golden'")"     "150"
eq "golden cache_read_tokens" "$(QROW "SELECT cache_read_tokens FROM sessions WHERE project_slug='proj-golden'")" "30"
eq "golden cache_creation_tokens" "$(QROW "SELECT cache_creation_tokens FROM sessions WHERE project_slug='proj-golden'")" "14"
eq "golden tool_call_count"   "$(QROW "SELECT tool_call_count FROM sessions WHERE project_slug='proj-golden'")"   "2"
eq "golden error_count"       "$(QROW "SELECT error_count FROM sessions WHERE project_slug='proj-golden'")"       "1"
eq "golden compaction_count"  "$(QROW "SELECT compaction_count FROM sessions WHERE project_slug='proj-golden'")"  "1"
eq "golden canary_drop_count" "$(QROW "SELECT canary_drop_count FROM sessions WHERE project_slug='proj-golden'")" "1"

# =============================================================================================
echo "== safety golden: a fixture secret-guard log with KNOWN per-status/per-rule counts =="
cat > "$SAFETY_LOG" <<'EOF'
[2026-07-01T00:00:00Z] [BLOCK] [sess-1] [Bash] [B1] 1Password CLI output would land in the transcript.
[2026-07-01T00:00:01Z] [BLOCK] [sess-1] [Bash] [B1] 1Password CLI output would land in the transcript.
[2026-07-01T00:00:02Z] [BYPASS] [sess-2] [Edit] user explicit bypass marker; secret value lands in transcript by user choice
[2026-07-01T00:00:03Z] [WARN] [sess-1] [Bash] [B9] secret-read redirected to disk: /tmp/pt-fixture-path.json
[2026-07-01T00:00:04Z] [BYPASS] [unknown] [Write] test/doc fixture path exemption: /some/real/fixture/secret-guard.sh
EOF
REBUILD
eq "safety total rows"     "$(QROW "SELECT count(*) FROM safety")"                     "5"
eq "safety BLOCK count"    "$(QROW "SELECT count(*) FROM safety WHERE status='BLOCK'")"  "2"
eq "safety BYPASS count"   "$(QROW "SELECT count(*) FROM safety WHERE status='BYPASS'")" "2"
eq "safety WARN count"     "$(QROW "SELECT count(*) FROM safety WHERE status='WARN'")"   "1"
eq "safety B1 rule count"  "$(QROW "SELECT count(*) FROM safety WHERE rule='B1'")"       "2"
eq "safety B9 rule count"  "$(QROW "SELECT count(*) FROM safety WHERE rule='B9'")"       "1"
eq "safety NULL-rule count (BYPASS lines carry no rule code)" \
   "$(QROW "SELECT count(*) FROM safety WHERE rule IS NULL")" "2"
NC_SAFETY_PATH="$(QROW "SELECT count(*) FROM safety WHERE session LIKE '%fixture-path%' OR tool LIKE '%fixture-path%'")"
eq "safety free-text path never captured into session/tool columns" "$NC_SAFETY_PATH" "0"

# =============================================================================================
echo "== PRIV-nc (LOAD-BEARING, absolute): FAKE-SECRET-a1b2c3 in tool_result.content AND"
echo "           custom-title must appear in ZERO materialized tables/columns, while the"
echo "           session's own NUMERIC row still exists (counted, not silently dropped) =="
reset_all
mkdir -p "$SESSIONS_DIR/proj-privacy"
PRIV_FILE="$SESSIONS_DIR/proj-privacy/privacy-session.jsonl"
cat > "$PRIV_FILE" <<'EOF'
{"type":"custom-title","customTitle":"investigate FAKE-SECRET-a1b2c3 leaked title","sessionId":"privacy-session"}
{"type":"user","timestamp":"2026-07-02T00:00:00.000Z","message":{"role":"user","content":"do something"}}
{"type":"assistant","timestamp":"2026-07-02T00:00:01.000Z","message":{"role":"assistant","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":1,"cache_creation_input_tokens":1},"content":[{"type":"tool_use","id":"call_x","name":"Edit","input":{"file_path":"/tmp/x"}}]}}
{"type":"user","timestamp":"2026-07-02T00:00:02.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"call_x","content":"String to replace not found in file.\nString: FAKE-SECRET-a1b2c3 embedded in file text","is_error":true}]}}
{"type":"assistant","timestamp":"2026-07-02T00:00:03.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":2,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"Done.\n\n🐱 Neko-san"}]}}
EOF
REBUILD

if grep -q "FAKE-SECRET-a1b2c3" "$PRIV_FILE"; then
  ok "PRIV-nc-positive-control: the raw fixture file DOES contain the secret (not vacuous)"
else
  bad "PRIV-nc-positive-control: fixture setup bug, secret missing from raw fixture"
fi

eq "PRIV-nc numeric row exists (session counted)" \
   "$(QROW "SELECT count(*) FROM sessions WHERE session_id='privacy-session'")" "1"
eq "PRIV-nc error_count still correctly counted despite is_error's leaky content" \
   "$(QROW "SELECT error_count FROM sessions WHERE session_id='privacy-session'")" "1"

HITS="$(uv run python3 - <<'PY'
from ledger_observatory import materialize
needle = "FAKE-SECRET-a1b2c3"
hits = []
for name in materialize.table_names():
    cols, rows = materialize.show(name)
    for row in rows:
        for v in row:
            if v is not None and needle in str(v):
                hits.append((name, v))
print(len(hits))
PY
)"
eq "PRIV-nc full-text scan across EVERY materialized table/column: ZERO hits" "$HITS" "0"

# =============================================================================================
echo "== over-test: malformed/truncated jsonl line does not crash the parse; valid lines"
echo "           still contribute; the file's last line is cut mid-write (no trailing newline) =="
reset_sessions
mkdir -p "$SESSIONS_DIR/proj-malformed"
printf '%s\n%s\n%s' \
  '{"type":"user","timestamp":"2026-07-03T00:00:00.000Z","message":{"role":"user","content":"hi"}}' \
  '{"type": "assistant", "message": {' \
  '{"type":"assistant","timestamp":"2026-07-03T00:00:05.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":7,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"ok 🐱 Neko-san"}]}}' \
  > "$SESSIONS_DIR/proj-malformed/malformed-session.jsonl"
REBUILD
eq "O-malformed still produces a row (valid lines survive a bad line)" \
   "$(QROW "SELECT count(*) FROM sessions WHERE session_id='malformed-session'")" "1"
eq "O-malformed input_tokens only from the valid assistant line" \
   "$(QROW "SELECT input_tokens FROM sessions WHERE session_id='malformed-session'")" "7"
eq "O-malformed first_ts from the valid user line" \
   "$(QROW "SELECT first_ts FROM sessions WHERE session_id='malformed-session'")" "2026-07-03T00:00:00.000Z"

echo "== over-test: an empty session (zero timestamped lines) produces NO row =="
mkdir -p "$SESSIONS_DIR/proj-empty"
cat > "$SESSIONS_DIR/proj-empty/empty-session.jsonl" <<'EOF'
{"type":"custom-title","customTitle":"just metadata, no timestamp"}
{"type":"mode","mode":"normal"}
EOF
REBUILD
eq "O-empty no row for a zero-timestamped-line file" \
   "$(QROW "SELECT count(*) FROM sessions WHERE session_id='empty-session'")" "0"

echo "== over-test: a multi-compaction session (3 compact_boundary lines) counts all 3 =="
mkdir -p "$SESSIONS_DIR/proj-multicompact"
cat > "$SESSIONS_DIR/proj-multicompact/multicompact-session.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-04T00:00:00.000Z","message":{"role":"user","content":"go"}}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-07-04T00:00:01.000Z"}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-07-04T00:00:02.000Z"}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-07-04T00:00:03.000Z"}
{"type":"assistant","timestamp":"2026-07-04T00:00:04.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD
eq "O-multicompact compaction_count=3" \
   "$(QROW "SELECT compaction_count FROM sessions WHERE session_id='multicompact-session'")" "3"

echo "== over-test (CRITICAL regression, SPEC-135 DEC-008): a usage field that is valid JSON"
echo "           but NOT numeric (a STRING) must not crash the parse or leak its content into"
echo "           an exception -- it is coerced to 0, the rest of the row still counts, and a"
echo "           full-text scan for the planted string finds ZERO hits anywhere =="
reset_all
mkdir -p "$SESSIONS_DIR/proj-badtype"
cat > "$SESSIONS_DIR/proj-badtype/badtype-session.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-05T00:00:00.000Z","message":{"role":"user","content":"go"}}
{"type":"assistant","timestamp":"2026-07-05T00:00:05.000Z","message":{"role":"assistant","stop_reason":"tool_use","usage":{"input_tokens":"FAKE-SECRET-badtype-x9","output_tokens":50,"cache_read_input_tokens":10,"cache_creation_input_tokens":5},"content":[{"type":"tool_use","id":"c1","name":"Bash","input":{}}]}}
{"type":"assistant","timestamp":"2026-07-05T00:00:07.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":30,"output_tokens":15,"cache_read_input_tokens":3,"cache_creation_input_tokens":1},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD_OUT="$(uv run ledger rebuild 2>&1)"
REBUILD_EXIT=$?
eq "O-badtype rebuild exits 0 (no uncaught exception)" "$REBUILD_EXIT" "0"
hasnt "O-badtype planted string never appears in the rebuild output/traceback" \
      "FAKE-SECRET-badtype-x9" "$REBUILD_OUT"
eq "O-badtype row still exists (bad field coerced to 0, row not dropped)" \
   "$(QROW "SELECT count(*) FROM sessions WHERE session_id='badtype-session'")" "1"
eq "O-badtype input_tokens=30 (bad string field counted as 0, only the valid line contributed)" \
   "$(QROW "SELECT input_tokens FROM sessions WHERE session_id='badtype-session'")" "30"
BADTYPE_HITS="$(uv run python3 - <<'PY'
from ledger_observatory import materialize
needle = "FAKE-SECRET-badtype-x9"
hits = 0
for name in materialize.table_names():
    _cols, rows = materialize.show(name)
    for row in rows:
        for v in row:
            if v is not None and needle in str(v):
                hits += 1
print(hits)
PY
)"
eq "O-badtype full-text scan: the bad usage string is in ZERO materialized columns" "$BADTYPE_HITS" "0"

echo "== over-test (MINOR, SPEC-135 DEC-009): a non-ISO8601 timestamp string is dropped (that"
echo "           line's ts contribution only), never persisted raw into first_ts/last_ts =="
reset_all
mkdir -p "$SESSIONS_DIR/proj-badts"
cat > "$SESSIONS_DIR/proj-badts/badts-session.jsonl" <<'EOF'
{"type":"assistant","timestamp":"not-a-timestamp-lol","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
{"type":"assistant","timestamp":"2026-07-06T00:00:05.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":2,"output_tokens":2,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD
eq "O-badts first_ts is the VALID iso line, never the junk string" \
   "$(QROW "SELECT first_ts FROM sessions WHERE session_id='badts-session'")" "2026-07-06T00:00:05.000Z"
eq "O-badts the junk timestamp string is nowhere in first_ts/last_ts" \
   "$(QROW "SELECT count(*) FROM sessions WHERE session_id='badts-session' AND (first_ts LIKE '%not-a-timestamp%' OR last_ts LIKE '%not-a-timestamp%')")" "0"

echo "== over-test: read_sessions/read_safety are skip-safe on a missing source =="
MISSING_CHECK="$(uv run python3 - <<'PY'
from pathlib import Path
from ledger_observatory import adapters
results = []
cols, rows = adapters.read_sessions(Path("/nonexistent-sessions-dir-xyz"))
results.append(("sessions-missing", cols == adapters.SESSIONS_COLUMNS and rows == []))
cols2, rows2 = adapters.read_safety(Path("/nonexistent-safety-log-xyz"))
results.append(("safety-missing", cols2 == adapters.SAFETY_COLUMNS and rows2 == []))
for name, ok_ in results:
    print(f"{name}={ok_}")
PY
)"
has "O-missing sessions-dir skip-safe" "sessions-missing=True" "$MISSING_CHECK"
has "O-missing safety-log skip-safe"   "safety-missing=True"   "$MISSING_CHECK"

echo "== over-test: a safety-log line with no rule code AND a path-bearing message is never"
echo "           captured beyond the bracket fields (re-confirms the safety golden's own NC) =="
NC_PATH_IN_ANY_COL="$(QROW "SELECT count(*) FROM safety WHERE ts LIKE '%/tmp%' OR status LIKE '%/tmp%'")"
eq "O-path-message never lands in ts/status either" "$NC_PATH_IN_ANY_COL" "0"

# =============================================================================================
echo "== token_runaway: ARMED against sessions, fires over a low --threshold, not over the"
echo "           default (loose) budget, and never fires when sessions is empty =="
reset_all
mkdir -p "$SESSIONS_DIR/proj-golden"
cat > "$SESSIONS_DIR/proj-golden/golden-session.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-01T10:00:00.000Z","message":{"role":"user","content":"hello"}}
{"type":"assistant","timestamp":"2026-07-01T10:00:15.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":300,"output_tokens":150,"cache_read_input_tokens":30,"cache_creation_input_tokens":14},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD
TRK='"key": "token_runaway"'
hasnt "T-default no fire under the loose default budget (494 total tokens)" "$TRK" "$(R anomalies --json)"
has   "T-low-threshold fires when --threshold token_budget_max=100 (below the 494 total)" \
      "$TRK" "$(R anomalies --threshold token_budget_max=100 --json)"
has   "T-low-threshold names the right session"       "golden-session" "$(R anomalies --threshold token_budget_max=100 --json)"
reset_sessions
REBUILD
hasnt "T-empty no fire when sessions table is empty" "$TRK" "$(R anomalies --threshold token_budget_max=1 --json)"
HELP="$(uv run ledger anomalies --help 2>&1)"
has "H-help lists token_budget_max" "token_budget_max" "$HELP"

# =============================================================================================
echo "== digest: sessions x kit_gates JOIN (time-containment bridge), coverage + cost +"
echo "           time-to-done, with an honest-empty second rid =="
reset_all
gate_row digest-rid-1 ship ran
gate_row digest-rid-2 ship ran
commit d1.py "v1" "feat(digest-rid-1): ship it"        "2026-07-03T12:05:00+00:00"
commit d2.py "v1" "feat(digest-rid-2): shipped elsewhere" "2026-01-01T00:00:00+00:00"
mkdir -p "$SESSIONS_DIR/proj-digest"
cat > "$SESSIONS_DIR/proj-digest/digest-session.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-03T12:00:00.000Z","message":{"role":"user","content":"go"}}
{"type":"assistant","timestamp":"2026-07-03T12:10:00.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":100,"cache_creation_input_tokens":50},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD
DIGEST_JSON="$(R digest --json)"
eq "D-shipped_rids"    "$(echo "$DIGEST_JSON" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["shipped_rids"])')"    "2"
eq "D-bridged_rids"    "$(echo "$DIGEST_JSON" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["bridged_rids"])')"    "1"
eq "D-coverage_pct"    "$(echo "$DIGEST_JSON" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["coverage_pct"])')"    "50.0"
eq "D-cost_per_verified_outcome_tokens (1650 total tokens / 1 bridged rid)" \
   "$(echo "$DIGEST_JSON" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["cost_per_verified_outcome_tokens"])')" "1650.0"
eq "D-avg_time_to_done_min (5 min: session start 12:00 -> ship commit 12:05)" \
   "$(echo "$DIGEST_JSON" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["avg_time_to_done_min"])')" "5.0"
has "D-digest also folds in anomalies (unknown_density or another real signal may fire; the" \
    '"anomalies"' "$DIGEST_JSON"

echo "== digest overlap (MAJOR regression, SPEC-135 DEC-010): TWO sessions both containing one"
echo "           rid's ship_ts must NOT double-count cost -- exactly ONE session (the closest-"
echo "           preceding, greatest first_ts <= ship_ts) is attributed, cost + time-to-done"
echo "           from the SAME session =="
reset_all
gate_row overlap-rid ship ran
commit ov.py "v1" "feat(overlap-rid): ship it" "2026-07-03T12:05:00+00:00"
mkdir -p "$SESSIONS_DIR/proj-overlap"
# Session A: window 11:50-12:20 (contains 12:05), first_ts 11:50, 1000 total tokens.
cat > "$SESSIONS_DIR/proj-overlap/overlap-A.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-03T11:50:00.000Z","message":{"role":"user","content":"go"}}
{"type":"assistant","timestamp":"2026-07-03T12:20:00.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":700,"output_tokens":200,"cache_read_input_tokens":80,"cache_creation_input_tokens":20},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
# Session B: window 12:00-12:15 (ALSO contains 12:05), first_ts 12:00 (LATER, so the closest-
# preceding one), 500 total tokens. This is the one that must be attributed, not the sum (1500).
cat > "$SESSIONS_DIR/proj-overlap/overlap-B.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-03T12:00:00.000Z","message":{"role":"user","content":"go"}}
{"type":"assistant","timestamp":"2026-07-03T12:15:00.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":350,"output_tokens":100,"cache_read_input_tokens":40,"cache_creation_input_tokens":10},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD
DIGEST_OVL="$(R digest --json)"
eq "D-overlap bridged_rids=1 (one rid, one session, not two)" \
   "$(echo "$DIGEST_OVL" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["bridged_rids"])')" "1"
eq "D-overlap cost=500 (ONLY the closest-preceding session B, NOT 1500 = A+B double-count)" \
   "$(echo "$DIGEST_OVL" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["cost_per_verified_outcome_tokens"])')" "500.0"
eq "D-overlap time-to-done=5.0 (from session B's OWN start 12:00, the SAME session as the cost)" \
   "$(echo "$DIGEST_OVL" | uv run python3 -c 'import json,sys; print(json.load(sys.stdin)["scorecard"][0]["avg_time_to_done_min"])')" "5.0"

echo "== digest honest-empty: zero shipped rids -> NULL coverage/cost, never a crash =="
reset_kit
reset_db
REBUILD
DIGEST_EMPTY="$(R digest --json)"
has "D-empty coverage_pct is null" '"coverage_pct": null' "$DIGEST_EMPTY"
has "D-empty cost_per_verified_outcome_tokens is null" '"cost_per_verified_outcome_tokens": null' "$DIGEST_EMPTY"
has "D-empty shipped_rids=0" '"shipped_rids": 0' "$DIGEST_EMPTY"

echo "== digest --propose: stages via the SAME anomalies_mod.stage_proposals() path =="
reset_all
mkdir -p "$SESSIONS_DIR/proj-golden"
cat > "$SESSIONS_DIR/proj-golden/golden-session.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-07-01T10:00:00.000Z","message":{"role":"user","content":"hello"}}
{"type":"assistant","timestamp":"2026-07-01T10:00:15.000Z","message":{"role":"assistant","stop_reason":"end_turn","usage":{"input_tokens":300,"output_tokens":150,"cache_read_input_tokens":30,"cache_creation_input_tokens":14},"content":[{"type":"text","text":"🐱 Neko-san"}]}}
EOF
REBUILD
reset_staging
DIRECT_OUT="$(R anomalies --threshold token_budget_max=100 --propose --json)"
DIRECT_STAGED="$(staged_n)"
reset_staging
DIGEST_OUT="$(R digest --threshold token_budget_max=100 --propose --json)"
DIGEST_STAGED="$(staged_n)"
eq "P-digest-propose stages the SAME count as anomalies --propose (one path, not two)" \
   "$DIGEST_STAGED" "$DIRECT_STAGED"
has "P-digest-propose stages token_runaway" '"key": "token_runaway"' "$DIGEST_OUT"
ADDBL_OUT="$(python3 "$ADDBL" list 2>&1)"
has "P-digest-propose add-backlog sees the staged proposal" "token footprint over budget" "$ADDBL_OUT"

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

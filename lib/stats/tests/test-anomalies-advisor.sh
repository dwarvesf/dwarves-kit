#!/usr/bin/env bash
# Over-test for the ceremony / token-runaway / serial-when-parallel anomaly detectors
# (SPEC-134 test plan). Self-contained: builds kit_gates fixtures (run-ledger log files, same
# grammar adapters.py parses) + a generated git repo (same precedent as
# test-defect-correlation.sh/test-deviation-rate.sh), points every source env var at them, runs
# the REAL end-to-end path (source -> `ledger rebuild` lens -> `ledger anomalies`), and asserts.
#
# DELIBERATELY does not use `kit_runs` (lane-telemetry.sh) anywhere: confirmed during this
# sub-goal's build that `read_kit()`'s subprocess into the installed `lane-telemetry.sh`
# returns 0 rows in this local environment (a pre-existing, out-of-scope issue, see
# `_meta/megagoals/harness-observatory/DECISIONS.md`) -- the SAME reason `test-feedback.sh`'s
# debt/misfire fixtures currently fail here. `serial_when_parallel` is anchored on `git_fixes.ts`
# instead (the HANDOFF windowing lesson), so this suite never touches the broken path.
#
# The load-bearing cases:
#   - C-fp-nc: a gate skipped ~80% of the time for an entirely LEGITIMATE reason (non-UI runs)
#     must NOT be proposed for cutting. C-fp-nc-deliberate-break proves a bare skip-rate query
#     WOULD flag it, so the real detector's caught-signal conditioning is the thing doing the
#     work, not decoration.
#   - C-mixed: a gate with enough KNOWN caught samples but even ONE true catch must NOT fire
#     (proves the "NONE of them true" clause is load-bearing, not just the min-sample floor).
#   - C-multifile-nc: ONE real rid whose bridged commit touches 5 files must NOT count as 5
#     samples of evidence (a single multi-file commit must never fake evidence-sufficiency).
#   - S-nofire: a genuinely dependent pair (shared file) with the SAME non-overlapping windows
#     that would otherwise fire must NOT fire.
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

FIX="$(mktemp -d)"
GITREPO="$FIX/repo"
KITLOG="$FIX/kit-runs"

# ---- build the git fixture: a real repo, controlled dates, no interactive prompts ----------
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q -b main --template=
git -C "$GITREPO" config user.name "Fixture Bot"
git -C "$GITREPO" config user.email "fixture@example.com"
git -C "$GITREPO" config commit.gpgsign false

commit() {
  # commit <relpath> <content> <subject> <iso8601-date>
  local rel="$1" content="$2" subject="$3" date="$4"
  mkdir -p "$(dirname "$GITREPO/$rel")"
  printf '%s\n' "$content" > "$GITREPO/$rel"
  git -C "$GITREPO" add "$rel" >/dev/null
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$GITREPO" commit -q -m "$subject" >/dev/null
}

# commit_multi <relpaths-space-separated> <subject> <iso8601-date>  -- ONE commit, N files.
commit_multi() {
  local rels="$1" subject="$2" date="$3" rel
  for rel in $rels; do
    mkdir -p "$(dirname "$GITREPO/$rel")"
    printf 'v1\n' > "$GITREPO/$rel"
  done
  git -C "$GITREPO" add $rels >/dev/null
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$GITREPO" commit -q -m "$subject" >/dev/null
}

# ---- env: point every source at the fixtures -----------------------------------------------
export DWARVES_KIT_LOG_DIR="$KITLOG"
export STATS_GIT_REPO_DIR="$GITREPO"
export STATS_TIDE_DB="$FIX/state.sqlite"          # absent -> skip-safe empty table
export STATS_TGCLEANUP_DIR="$FIX/tg"              # empty -> skip-safe
export STATS_LEARNED_MD="$FIX/learned.md"         # absent -> skip-safe
export STATS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"     # absent -> skip-safe empty sessions
export STATS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"   # absent -> skip-safe empty safety
export STATS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"      # absent -> skip-safe empty memories (repo store)
export STATS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"  # absent -> skip-safe empty memories (builtin store)
export STATS_DB_REMOVED="$FIX/lens.duckdb"
export CC_BACKLOG_STAGING="$FIX/backlog-staging.md"
export CC_BACKLOG_BACKLOG="$FIX/BACKLOG.md"
mkdir -p "$STATS_TGCLEANUP_DIR" "$KITLOG/runs"

cat > "$CC_BACKLOG_BACKLOG" <<'EOF'
# Backlog
| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | pre-existing unrelated row | notes | queued |
EOF

R()  { uv run stats "$@" 2>&1; }
REBUILD() { uv run stats rebuild >/dev/null 2>&1; }
reset()         { rm -rf "$KITLOG/runs"; mkdir -p "$KITLOG/runs";
                  rm -f "$STATS_DB_REMOVED" "$STATS_DB_REMOVED.wal"; }
reset_staging() { rm -f "$CC_BACKLOG_STAGING"; }
staged_n() { [ -f "$CC_BACKLOG_STAGING" ] && grep -c '^## \[staged\]' "$CC_BACKLOG_STAGING" || echo 0; }

# gate_row <rid> <gate> <outcome> <caught|-> [reason]
#   caught != "-" also emits an OUTCOME start/end bracket (kit's SPEC-129 additive marker).
gate_row() {
  local rid="$1" gate="$2" outcome="$3" caught="$4" reason="${5:-}"
  local f="$KITLOG/runs/$rid.log"
  {
    echo "2026-07-01T00:00:00Z | START | lane=full classified=full type=feat ctype=feat repo=fixrepo"
    if [ "$caught" != "-" ]; then
      echo "2026-07-01T00:00:01Z | OUTCOME | $gate | start | at=1"
      echo "2026-07-01T00:00:02Z | OUTCOME | $gate | end | at=2 caught=$caught dur_s=1"
    fi
    if [ -n "$reason" ]; then
      echo "2026-07-01T00:00:03Z | GATE | $gate | $outcome | $reason"
    else
      echo "2026-07-01T00:00:03Z | GATE | $gate | $outcome"
    fi
  } > "$f"
}

CER='"key": "ceremony"'
SWP='"key": "serial_when_parallel"'
TRK='"key": "token_runaway"'

# =============================================================================================
echo "== C-cut: 5 'grill' ran rows, all caught=false (>= ceremony_min_ran) -> CUT =="
reset
gate_row cutcase-1 grill ran false
gate_row cutcase-2 grill ran false
gate_row cutcase-3 grill ran false
gate_row cutcase-4 grill ran false
gate_row cutcase-5 grill ran false
REBUILD
OUT="$(R anomalies --json)"
has   "C-cut fires ceremony"       "$CER"        "$OUT"
has   "C-cut action=CUT"           "action=CUT"  "$OUT"
has   "C-cut names gate grill"     "gate=grill"  "$OUT"
hasnt "C-cut no token_runaway (never armed, even while ceremony fires)" "$TRK" "$OUT"

echo "== C-cut-floor: only 4 caught=false rows (< ceremony_min_ran=5) does NOT fire =="
reset
gate_row f1 grill ran false
gate_row f2 grill ran false
gate_row f3 grill ran false
gate_row f4 grill ran false
REBUILD
hasnt "C-cut-floor no ceremony (thin caught evidence)" "$CER" "$(R anomalies --json)"

echo "== C-mixed: 5 'mixed' ran rows, 4 caught=false + 1 caught=true -> must NOT fire =="
echo "           (proves the NONE-true clause is load-bearing, not just the min-sample floor)"
reset
gate_row mx1 mixed ran false
gate_row mx2 mixed ran false
gate_row mx3 mixed ran false
gate_row mx4 mixed ran false
gate_row mx5 mixed ran true
REBUILD
hasnt "C-mixed no ceremony (one real catch among enough known samples)" "$CER" "$(R anomalies --json)"

echo "== C-condition: 5 'audit' ran rows, no caught data, git-bridged, never fixed -> CONDITION =="
reset
gate_row condcase-1 audit ran -
gate_row condcase-2 audit ran -
gate_row condcase-3 audit ran -
gate_row condcase-4 audit ran -
gate_row condcase-5 audit ran -
commit cond1.py "v1" "feat(condcase-1): work"  "2026-01-01T00:00:00+00:00"
commit cond2.py "v1" "feat(condcase-2): work"  "2026-01-02T00:00:00+00:00"
commit cond3.py "v1" "feat(condcase-3): work"  "2026-01-03T00:00:00+00:00"
commit cond4.py "v1" "feat(condcase-4): work"  "2026-01-04T00:00:00+00:00"
commit cond5.py "v1" "feat(condcase-5): work"  "2026-01-05T00:00:00+00:00"
REBUILD
OUT="$(R anomalies --json)"
has "C-condition fires ceremony"        "$CER"              "$OUT"
has "C-condition action=CONDITION"      "action=CONDITION"  "$OUT"
has "C-condition names gate audit"      "gate=audit"         "$OUT"

echo "== C-condition-nofire: same shape, but ONE bridged file gets a later fix() -> no fire =="
reset
gate_row condb-1 auditb ran -
gate_row condb-2 auditb ran -
gate_row condb-3 auditb ran -
gate_row condb-4 auditb ran -
gate_row condb-5 auditb ran -
commit condb1.py "v1" "feat(condb-1): work" "2026-02-01T00:00:00+00:00"
commit condb2.py "v1" "feat(condb-2): work" "2026-02-02T00:00:00+00:00"
commit condb3.py "v1" "feat(condb-3): work" "2026-02-03T00:00:00+00:00"
commit condb4.py "v1" "feat(condb-4): work" "2026-02-04T00:00:00+00:00"
commit condb5.py "v1" "feat(condb-5): work" "2026-02-05T00:00:00+00:00"
commit condb1.py "v2" "fix(condb-1): patch" "2026-02-06T00:00:00+00:00"   # fix-followed for condb-1
REBUILD
hasnt "C-condition-nofire no ceremony (one later fix breaks the zero-fix-followed claim)" \
      "$CER" "$(R anomalies --json)"

echo "== C-multifile-nc: ONE real rid, its bridged commit touches 5 files -> bridged MUST"
echo "                   count as 1 (not 5); below the floor, so no fire (over-test for the"
echo "                   count(*) vs count(DISTINCT rid) file-count-inflation bug) =="
reset
gate_row multicase-1 multigate ran -
commit_multi "multi_a.py multi_b.py multi_c.py multi_d.py multi_e.py" \
             "feat(multicase-1): five files in one commit" "2026-06-01T00:00:00+00:00"
REBUILD
hasnt "C-multifile-nc no ceremony (1 real rid, not 5, despite 5 touched files)" \
      "$CER" "$(R anomalies --json)"

echo "== C-thin-true: gate 'thintrue' has THIN caught data (2 < ceremony_min_ran) but ONE of"
echo "                those 2 is caught=true, AND the soft path's own floor is separately"
echo "                satisfied (5 bridged, 0 fixed) -- must NOT fire either path (code-review"
echo "                MAJOR fix: caught_true>0 must suppress BOTH hard and soft, not just hard) =="
reset
gate_row thin-1 thintrue ran true    # the one real (thin) catch
gate_row thin-2 thintrue ran false
gate_row thin-3 thintrue ran -       # no OUTCOME bracket -> caught unknown
gate_row thin-4 thintrue ran -
gate_row thin-5 thintrue ran -
commit thin1.py "v1" "feat(thin-1): work" "2026-06-10T00:00:00+00:00"
commit thin2.py "v1" "feat(thin-2): work" "2026-06-11T00:00:00+00:00"
commit thin3.py "v1" "feat(thin-3): work" "2026-06-12T00:00:00+00:00"
commit thin4.py "v1" "feat(thin-4): work" "2026-06-13T00:00:00+00:00"
commit thin5.py "v1" "feat(thin-5): work" "2026-06-14T00:00:00+00:00"
REBUILD
hasnt "C-thin-true no ceremony (a THIN but REAL catch must suppress the soft/CONDITION path too)" \
      "$CER" "$(R anomalies --json)"

echo "== C-fp-nc: 'ui-design' skipped ~80% for a LEGITIMATE reason (non-UI runs); caught=true"
echo "           in its few ran rows -- must NOT be proposed for cutting (load-bearing FP-NC) =="
reset
gate_row ui-1 ui-design ran true
gate_row ui-2 ui-design ran true
gate_row ui-3 ui-design ran true
gate_row ui-4 ui-design ran true
gate_row ui-5 ui-design ran true
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  gate_row "ui-skip-$n" ui-design skipped - "reason=not-applicable: non-ui-run"
done
REBUILD
OUT="$(R anomalies --json)"
hasnt "C-fp-nc ceremony does NOT fire on ui-design (real caught=true evidence)" "$CER" "$OUT"

echo "== C-fp-nc-deliberate-break: prove a bare skip-rate query WOULD flag ui-design =="
# Simulate the bug this design guards against: a naive detector that fires on skip fraction
# alone, with NO reference to caught/fix-correlation at all.
BROKEN="$(uv run python3 - <<'PY' 2>&1
from stats import materialize
cols, rows = materialize.query("""
    SELECT gate,
           count(*) FILTER (WHERE outcome = 'skipped') * 1.0 / count(*) AS skip_rate
    FROM kit_gates GROUP BY gate HAVING skip_rate > 0.5
""")
import json
print(json.dumps([dict(zip(cols, r)) for r in rows]))
PY
)"
has "C-fp-nc-deliberate-break a bare skip-rate query WOULD flag ui-design (the bug the real detector avoids)" \
    '"gate": "ui-design"' "$BROKEN"

echo "== S-fire: two dep-independent rids (git-windowed, NOT kit_runs) ran back-to-back =="
reset
gate_row sg-01-alpha build ran -
gate_row sg-02-beta  build ran -
commit alpha1.py "v1" "feat(sg-01-alpha): work1" "2026-03-01T00:00:00+00:00"
commit alpha2.py "v1" "feat(sg-01-alpha): work2" "2026-03-01T00:10:00+00:00"   # alpha window 10min
commit beta1.py  "v1" "feat(sg-02-beta): work1"  "2026-03-01T00:10:00+00:00"
commit beta2.py  "v1" "feat(sg-02-beta): work2"  "2026-03-01T00:25:00+00:00"   # beta window 15min
REBUILD
OUT="$(R anomalies --json)"
has "S-fire fires serial_when_parallel"        "$SWP"                                  "$OUT"
has "S-fire names both rids"                   "rid_a=sg-01-alpha rid_b=sg-02-beta"    "$OUT"
has "S-fire minutes_saved=10.0 (min of 10,15)" "minutes_saved=10.0"                   "$OUT"

echo "== S-nofire: a genuinely dependent pair (shares one bridged file), same non-overlap,"
echo "            durations that WOULD clear the floor if independent -> must NOT fire =="
reset
gate_row sg-03-gamma build ran -
gate_row sg-04-delta build ran -
commit shared.py "v1"  "feat(sg-03-gamma): work1" "2026-04-01T00:00:00+00:00"
commit gamma2.py "v1"  "feat(sg-03-gamma): work2" "2026-04-01T00:10:00+00:00"   # gamma window 10min
commit shared.py "v2"  "feat(sg-04-delta): work1" "2026-04-01T00:10:00+00:00"   # SAME file as gamma
commit delta2.py "v1"  "feat(sg-04-delta): work2" "2026-04-01T00:25:00+00:00"   # delta window 15min
REBUILD
hasnt "S-nofire no serial_when_parallel (genuinely dependent, shares shared.py)" \
      "$SWP" "$(R anomalies --json)"

echo "== S-nofire-zero-evidence: two rids with ZERO git correlation at all -> never a candidate =="
reset
gate_row sg-07-nogit build ran -
gate_row sg-08-nogit2 build ran -
REBUILD
hasnt "S-nofire-zero-evidence no serial_when_parallel (no bridge evidence for either rid)" \
      "$SWP" "$(R anomalies --json)"

echo "== T-armed (SPEC-135 update): token_runaway is now ARMED against the sessions table;"
echo "           this suite isolates STATS_SESSIONS_DIR to a nonexistent dir, so it"
echo "           still correctly does NOT fire here (an empty sessions table is a zero-"
echo "           evidence lens, the same honest-empty contract every detector in this module"
echo "           follows) -- this is no longer testing a permanent NOT-ARMED stub (SG-04's"
echo "           original assertion), it is testing the ARMED detector's OWN empty-table"
echo "           abstention, see tests/test-sessions-digest.sh for the real armed fire/no-fire"
echo "           coverage against a real sessions fixture =="
hasnt "T-armed absent on this suite's isolated zero-sessions lens" "$TRK" "$(R anomalies --json)"
SRC="src/stats/anomalies.py"
has  "T-armed detector present in DETECTORS" "_detect_token_runaway" "$(cat "$SRC")"
has  "T-armed docstring states ARMED (SPEC-135)" "ARMED" "$(cat "$SRC")"

echo "== P-propose: ceremony CUT stages, board byte-identical, add-backlog sees it, idempotent =="
reset
gate_row p1 grill ran false
gate_row p2 grill ran false
gate_row p3 grill ran false
gate_row p4 grill ran false
gate_row p5 grill ran false
REBUILD
reset_staging
BOARD_BEFORE="$(shasum -a 256 "$CC_BACKLOG_BACKLOG")"
OUT="$(R anomalies --propose --json)"
has  "P-propose reports staged"         '"action": "staged"' "$OUT"
eq   "P-propose one staged block"       "$(staged_n)" "1"
has  "P-propose staged block in buffer" "## [staged] Feedback: gate ran but never caught anything (ceremony)" \
     "$(cat "$CC_BACKLOG_STAGING")"
BOARD_AFTER="$(shasum -a 256 "$CC_BACKLOG_BACKLOG")"
eq   "P-propose board BYTE-IDENTICAL (not auto-filed)" "$BOARD_AFTER" "$BOARD_BEFORE"
if [ -f "$ADDBL" ]; then
  ADDBL_OUT="$(python3 "$ADDBL" list 2>&1)"
  has  "P-propose add-backlog lists the proposal" "gate ran but never caught anything" "$ADDBL_OUT"
else
  echo "SKIP  P-propose add-backlog cross-check (cc-backlog is an ops-toolkit-only sibling tool; not present in this repo)"
fi
OUT2="$(R anomalies --propose --json)"
has  "P-dedup second run marks duplicate" '"action": "duplicate"' "$OUT2"
eq   "P-dedup still exactly one block"    "$(staged_n)" "1"

echo "== S-propose: serial_when_parallel ALSO stages via the same generic path =="
reset
gate_row sg-05-e build ran -
gate_row sg-06-f build ran -
commit e1.py "v1" "feat(sg-05-e): work1" "2026-05-01T00:00:00+00:00"
commit e2.py "v1" "feat(sg-05-e): work2" "2026-05-01T00:10:00+00:00"
commit f1.py "v1" "feat(sg-06-f): work1" "2026-05-01T00:10:00+00:00"
commit f2.py "v1" "feat(sg-06-f): work2" "2026-05-01T00:25:00+00:00"
REBUILD
reset_staging
OUT="$(R anomalies --propose --json)"
has "S-propose stages serial_when_parallel" \
    '"title": "Feedback: dep-independent runs executed in separate serial waves"' "$OUT"
eq  "S-propose one staged block" "$(staged_n)" "1"

echo "== H-help: both new thresholds are listed in --help =="
HELP="$(uv run stats anomalies --help 2>&1)"
has "H-help lists ceremony_min_ran"          "ceremony_min_ran"          "$HELP"
has "H-help lists serial_min_minutes_saved"  "serial_min_minutes_saved" "$HELP"

echo "== O-one-path: detection reads via SG-02 materialize only (static, unchanged contract) =="
has   "O-one-path imports materialize"        "from . import materialize" "$(cat "$SRC")"
hasnt "O-one-path no direct duckdb import"    "import duckdb"              "$(cat "$SRC")"
hasnt "O-one-path no adapters bypass"         "adapters"                  "$(cat "$SRC")"
hasnt "O-one-path no raw-ledger reader bypass" "read_kit"                 "$(cat "$SRC")"

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Golden-fixture + over-test for `rejected_findings` / `ledger review-yield` (SPEC-137 test plan).
#
# Points at a COMMITTED fixture tree (tests/fixtures/review-yield/), same precedent
# test-gate-yield.sh set: repo-a/repo-b/repo-empty (rejected-findings.md, per-repo) +
# runs/*.log (kit_gates, review-gate lines carrying the SPEC-144 findings=/rejected=/
# suppressed= grammar). The test never writes into the fixture dir; only the (mktemp) lens
# db is ephemeral.
#
# The honest-zero NC (H-nc) is load-bearing: proven by a literal source-edit break of
# cli.py's review-yield SQL (red), then a restore (green) -- not just an inline alternate
# query, matching the goal file's explicit "break it ... watch RED, restore, GREEN" ask.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }

FIX="$(mktemp -d)"
FIXTURE_ROOT="$ROOT/tests/fixtures/review-yield"

# ---- env: rejected_findings sources point at the COMMITTED fixture repos; kit source points
# at the COMMITTED review-gate fixture ledger; everything else is empty/absent -------------
export STATS_REPOS="$FIXTURE_ROOT/repo-a,$FIXTURE_ROOT/repo-b,$FIXTURE_ROOT/repo-empty,$FIXTURE_ROOT/repo-missing-entirely"
export DWARVES_KIT_LOG_DIR="$FIXTURE_ROOT"
export STATS_TIDE_DB="$FIX/state.sqlite"
export STATS_TGCLEANUP_DIR="$FIX/tg"
export STATS_LEARNED_MD="$FIX/learned.md"
export STATS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir"
export STATS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"
export STATS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"
export STATS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"
export STATS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"
export STATS_DB_REMOVED="$FIX/lens.duckdb"
mkdir -p "$STATS_TGCLEANUP_DIR"

R() { uv run stats "$@" 2>&1; }

FIXTURE_BEFORE="$(find "$FIXTURE_ROOT" -type f -exec shasum -a 256 {} \; | sort)"

echo "== P-rebuild: rejected_findings materializes (repo-a x3 lenses + repo-b x1 lens; repo-empty/repo-missing-entirely contribute zero) =="
OUT="$(R rebuild)"
has "P-rebuild rejected_findings=4" '"rejected_findings": 4' "$OUT"
has "P-rebuild kit_gates=5" '"kit_gates": 5' "$OUT"

echo "== P-skip-warning: the 2 malformed rows in repo-a (too-few-cells, non-rejected verdict) are counted, not silent =="
has "P-skip-warning names a count" 'skipped 2 malformed row' "$OUT"

echo "== P-rows: exact per-(repo, lens) rejected_findings values =="
RF="$(R show rejected_findings --json)"
has "P-rows repo-a/security n=2 first=2026-01-01 last=2026-01-05" '"repo": "repo-a",
    "lens": "security",
    "n_rejected": 2,
    "first_ts": "2026-01-01",
    "last_ts": "2026-01-05"' "$RF"
has "P-rows repo-a/architecture n=1 (malformed+non-rejected rows never counted)" '"repo": "repo-a",
    "lens": "architecture",
    "n_rejected": 1,
    "first_ts": "2026-01-10",
    "last_ts": "2026-01-10"' "$RF"
has "P-rows repo-a/test-coverage n=6 (high-n lens, the accepted-verdict row on 01-12 excluded)" '"repo": "repo-a",
    "lens": "test-coverage",
    "n_rejected": 6,
    "first_ts": "2026-03-01",
    "last_ts": "2026-03-06"' "$RF"
has "P-rows repo-b/security n=1" '"repo": "repo-b",
    "lens": "security",
    "n_rejected": 1,
    "first_ts": "2026-02-01",
    "last_ts": "2026-02-01"' "$RF"
hasnt "P-rows repo-empty contributes NO row (file exists, zero real rows)" '"repo": "repo-empty"' "$RF"
N_TOTAL="$(printf '%s' "$RF" | grep -c '"repo":' || true)"
if [ "$N_TOTAL" -eq 4 ]; then ok "P-rows exactly 4 (repo, lens) rows total"; else bad "P-rows want 4 rows, got $N_TOTAL"; fi

echo "== Y-yield: exact review-yield numbers (hand-verified against the fixture) =="
# raised: fx-review-1 findings=3 rejected=1; fx-review-2 findings=2 rejected=0 (suppressed=1
# NEVER counted); fx-review-3 is outcome=skipped, EXCLUDED; fx-review-4 findings=0, no
# rejected= token (NULL, COALESCEs to 0) + a real caught=true OUTCOME bracket; fx-review-5 is
# gate=build, NEVER leaks in. sum_findings=3+2+0=5, sum_rejected=1+0=1, raised=6.
# review_ran=3 (fx-review-1,2,4; fx-review-3 skipped is excluded), review_caught=1 (fx-review-4).
YIELD="$(R review-yield --json)"
has "Y-yield repo-a/security: raised=6 fp_rate=0.333 low_n=true (n_rejected=2<5)" '"repo": "repo-a",
    "lens": "security",
    "n_rejected": 2,
    "first_ts": "2026-01-01",
    "last_ts": "2026-01-05",
    "review_ran": 3,
    "review_caught": 1,
    "raised": 6,
    "approx": true,
    "fp_rate_approx": 0.333,
    "low_n": true' "$YIELD"
has "Y-yield repo-a/architecture: fp_rate=0.167 low_n=true" '"repo": "repo-a",
    "lens": "architecture",
    "n_rejected": 1,' "$YIELD"
has "Y-yield repo-a/architecture fp_rate value" '"fp_rate_approx": 0.167' "$YIELD"
has "Y-yield repo-a/test-coverage: HIGH-N row, fp_rate=1.0 low_n=FALSE (both floors clear: n_rejected=6>=5, raised=6>=5)" '"repo": "repo-a",
    "lens": "test-coverage",
    "n_rejected": 6,
    "first_ts": "2026-03-01",
    "last_ts": "2026-03-06",
    "review_ran": 3,
    "review_caught": 1,
    "raised": 6,
    "approx": true,
    "fp_rate_approx": 1.0,
    "low_n": false' "$YIELD"
has "Y-yield repo-b/security: fp_rate=0.167 low_n=true" '"repo": "repo-b",
    "lens": "security",
    "n_rejected": 1,
    "first_ts": "2026-02-01",
    "last_ts": "2026-02-01",
    "review_ran": 3,
    "review_caught": 1,
    "raised": 6,
    "approx": true,
    "fp_rate_approx": 0.167,
    "low_n": true' "$YIELD"
N_Y="$(printf '%s' "$YIELD" | grep -c '"repo":' || true)"
if [ "$N_Y" -eq 4 ]; then ok "Y-yield exactly 4 rows (one per (repo,lens); repo-empty absent)"; else bad "Y-yield want 4 rows, got $N_Y"; fi

echo "== Y-honest-negative: test-coverage's fp_rate=1.0 is reported EXACTLY (never filtered/clamped) =="
has "Y-honest-negative a lens whose rejects equal the whole raised total still reports plainly" '"fp_rate_approx": 1.0' "$YIELD"

echo "== Y-suppressed-excluded: suppressed=1 on fx-review-2 never contributes to raised =="
# If suppressed leaked in, raised would be 7 (6+1), not 6 -- every fp_rate_approx above would
# shift (e.g. repo-b/security would be round(1/7,3)=0.143, not 0.167). The exact-match
# assertions above ALREADY prove this; this is the explicit, named confirmation.
hasnt "Y-suppressed-excluded raised is never 7" '"raised": 7' "$YIELD"

echo "== D-min-n: --min-n lets the operator move the low_n floor (named tunable, not buried) =="
YIELD_MINN10="$(R review-yield --min-n 10 --json)"
has "D-min-n with --min-n 10, even the high-n test-coverage row is now low_n=true (n_rejected=6<10)" '"lens": "test-coverage",
    "n_rejected": 6,
    "first_ts": "2026-03-01",
    "last_ts": "2026-03-06",
    "review_ran": 3,
    "review_caught": 1,
    "raised": 6,
    "approx": true,
    "fp_rate_approx": 1.0,
    "low_n": true' "$YIELD_MINN10"

echo "== Z-div-by-zero: raised=0 (no review kit_gates activity at all) -> fp_rate_approx NULL for every row, never 0.0 =="
ZFIX="$(mktemp -d)"
mkdir -p "$ZFIX/tg"
ZERO_YIELD="$(env \
  STATS_REPOS="$STATS_REPOS" \
  DWARVES_KIT_LOG_DIR="$ZFIX/nonexistent-kit-log-dir" \
  STATS_TIDE_DB="$ZFIX/state.sqlite" \
  STATS_TGCLEANUP_DIR="$ZFIX/tg" \
  STATS_LEARNED_MD="$ZFIX/learned.md" \
  STATS_SESSIONS_DIR="$ZFIX/nonexistent-sessions-dir" \
  STATS_SECRET_GUARD_LOG="$ZFIX/nonexistent-safety.log" \
  STATS_MEMORY_REPO_DIR="$ZFIX/nonexistent-memory-repo" \
  STATS_MEMORY_PROJECTS_ROOT="$ZFIX/nonexistent-memory-projects" \
  STATS_GIT_REPO_DIR="$ZFIX/nonexistent-git-repo" \
  STATS_DB_REMOVED="$ZFIX/lens.duckdb" \
  bash -c 'uv run stats rebuild >/dev/null 2>&1 && uv run stats review-yield --json 2>&1')"
hasnt "Z-div-by-zero no row fabricates fp_rate_approx=0.0" '"fp_rate_approx": 0.0' "$ZERO_YIELD"
has "Z-div-by-zero every row shows raised=0" '"raised": 0' "$ZERO_YIELD"
has "Z-div-by-zero fp_rate_approx is null" '"fp_rate_approx": null' "$ZERO_YIELD"
has "Z-div-by-zero every row is low_n (raised=0 < 5)" '"low_n": true' "$ZERO_YIELD"

echo "== H-nc: HONEST-ZERO negative control (load-bearing) =="
# No ledger files (rejected_findings 0 rows) + no review kit_gates activity -> ZERO output
# rows, clean exit, never a crash, never a fabricated row.
HFIX="$(mktemp -d)"
HZERO="$(env \
  STATS_REPOS="$HFIX/repo-none-at-all" \
  DWARVES_KIT_LOG_DIR="$HFIX/nonexistent-kit-log-dir" \
  STATS_TIDE_DB="$HFIX/state.sqlite" \
  STATS_TGCLEANUP_DIR="$HFIX/tg" \
  STATS_LEARNED_MD="$HFIX/learned.md" \
  STATS_SESSIONS_DIR="$HFIX/nonexistent-sessions-dir" \
  STATS_SECRET_GUARD_LOG="$HFIX/nonexistent-safety.log" \
  STATS_MEMORY_REPO_DIR="$HFIX/nonexistent-memory-repo" \
  STATS_MEMORY_PROJECTS_ROOT="$HFIX/nonexistent-memory-projects" \
  STATS_GIT_REPO_DIR="$HFIX/nonexistent-git-repo" \
  STATS_DB_REMOVED="$HFIX/lens.duckdb" \
  bash -c 'mkdir -p "$STATS_TGCLEANUP_DIR"; uv run stats rebuild >/dev/null 2>&1 && uv run stats review-yield --json' 2>&1)"
RC_H=$?
if [ "$HZERO" = "[]" ] && [ "$RC_H" -eq 0 ]; then
  ok "H-nc zero ledger files + zero review activity -> zero rows, exit 0, no crash, no fabricated rate"
else
  bad "H-nc want '[]' exit 0, got rc=$RC_H output=$HZERO"
fi

echo "== H-nc-deliberate-break: prove H-nc is falsifiable, not vacuous (literal source edit, red -> green) =="
# Simulate the bug this NC guards against: reverse the join direction (drive FROM the
# always-1-row review_agg, LEFT JOIN rejected_findings) and change the empty-denominator
# branch from NULL to 0.0. On the SAME zero-ledger-files zero-review-activity state above,
# this fabricates exactly one bogus all-NULL/0.0 row instead of returning zero rows.
CLI_FILE="$ROOT/src/stats/cli.py"
CLI_BACKUP="$(mktemp)"
cp "$CLI_FILE" "$CLI_BACKUP"

python3 - "$CLI_FILE" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
needle = (
    "    FROM rejected_findings rf\n"
    "    CROSS JOIN review_agg ra\n"
    "    ORDER BY rf.repo, rf.lens\n"
    "    \"\"\"\n"
    "    cols, rows = materialize.query(sql)\n"
    "    _emit(cols, rows, as_json)\n"
    "\n"
    "\n"
    "@app.command(name=\"memory-sweep\")"
)
broken = (
    "    FROM review_agg ra\n"
    "    LEFT JOIN rejected_findings rf ON true\n"
    "    ORDER BY rf.repo, rf.lens\n"
    "    \"\"\"\n"
    "    cols, rows = materialize.query(sql)\n"
    "    _emit(cols, rows, as_json)\n"
    "\n"
    "\n"
    "@app.command(name=\"memory-sweep\")"
)
assert needle in text, "review-yield SQL tail not found verbatim -- fixture out of sync with cli.py"
text = text.replace(needle, broken, 1)
text = text.replace(
    "             ELSE NULL END AS fp_rate_approx,",
    "             ELSE 0.0 END AS fp_rate_approx,  -- DELIBERATE BREAK (test-review-yield.sh H-nc)",
    1,
)
open(path, "w", encoding="utf-8").write(text)
PY

BROKEN_OUT="$(env \
  STATS_REPOS="$HFIX/repo-none-at-all" \
  DWARVES_KIT_LOG_DIR="$HFIX/nonexistent-kit-log-dir" \
  STATS_TIDE_DB="$HFIX/state.sqlite" \
  STATS_TGCLEANUP_DIR="$HFIX/tg" \
  STATS_LEARNED_MD="$HFIX/learned.md" \
  STATS_SESSIONS_DIR="$HFIX/nonexistent-sessions-dir" \
  STATS_SECRET_GUARD_LOG="$HFIX/nonexistent-safety.log" \
  STATS_MEMORY_REPO_DIR="$HFIX/nonexistent-memory-repo" \
  STATS_MEMORY_PROJECTS_ROOT="$HFIX/nonexistent-memory-projects" \
  STATS_GIT_REPO_DIR="$HFIX/nonexistent-git-repo" \
  STATS_DB_REMOVED="$HFIX/lens.duckdb" \
  uv run stats review-yield --json 2>&1)"
echo "-- RED (broken) run output: $BROKEN_OUT --"
if printf '%s' "$BROKEN_OUT" | grep -q '"fp_rate_approx": 0.0'; then
  ok "H-nc-deliberate-break RED: the broken query fabricates a 0.0-rate row from zero real data"
else
  bad "H-nc-deliberate-break did not reproduce the fabricated-row bug -- NC may be vacuous"
fi

cp "$CLI_BACKUP" "$CLI_FILE"
RESTORED_OUT="$(env \
  STATS_REPOS="$HFIX/repo-none-at-all" \
  DWARVES_KIT_LOG_DIR="$HFIX/nonexistent-kit-log-dir" \
  STATS_TIDE_DB="$HFIX/state.sqlite" \
  STATS_TGCLEANUP_DIR="$HFIX/tg" \
  STATS_LEARNED_MD="$HFIX/learned.md" \
  STATS_SESSIONS_DIR="$HFIX/nonexistent-sessions-dir" \
  STATS_SECRET_GUARD_LOG="$HFIX/nonexistent-safety.log" \
  STATS_MEMORY_REPO_DIR="$HFIX/nonexistent-memory-repo" \
  STATS_MEMORY_PROJECTS_ROOT="$HFIX/nonexistent-memory-projects" \
  STATS_GIT_REPO_DIR="$HFIX/nonexistent-git-repo" \
  STATS_DB_REMOVED="$HFIX/lens.duckdb" \
  uv run stats review-yield --json 2>&1)"
echo "-- GREEN (restored) run output: $RESTORED_OUT --"
if [ "$RESTORED_OUT" = "[]" ]; then
  ok "H-nc-deliberate-break GREEN: restored source returns zero rows again"
else
  bad "H-nc-deliberate-break restore did not return to zero rows: $RESTORED_OUT"
fi
if diff -q "$CLI_BACKUP" "$CLI_FILE" >/dev/null 2>&1; then
  ok "H-nc-deliberate-break source is byte-identical to pre-break (clean restore)"
else
  bad "H-nc-deliberate-break source did NOT restore cleanly"
fi

echo "== O-anomaly: review_fp anomaly detector fires on the high-n lens, propose-never-autofile =="
ANOM="$(R anomalies --json)"
has "O-anomaly review_fp fires (repo-a/test-coverage: fp_rate=1.0 >= 0.5 threshold, both floors clear)" '"key": "review_fp"' "$ANOM"
has "O-anomaly names the exact lens" "lens 'test-coverage' in repo-a" "$ANOM"

STAGING="$FIX/backlog-staging.md"
BOARD="$FIX/BACKLOG.md"
: > "$BOARD"
PROPOSE_OUT="$(CC_BACKLOG_STAGING="$STAGING" CC_BACKLOG_BACKLOG="$BOARD" R anomalies --propose --json)"
has "O-anomaly --propose stages review_fp" '"key": "review_fp"' "$PROPOSE_OUT"
if [ -f "$STAGING" ] && grep -q "review lens FP-rate" "$STAGING"; then
  ok "O-anomaly staged into the cc-backlog staging buffer (never the board)"
else
  bad "O-anomaly staging buffer missing the review_fp block"
fi
if [ ! -s "$BOARD" ]; then
  ok "O-anomaly the board file was NEVER written (propose-never-autofile)"
else
  bad "O-anomaly the board file was modified -- propose-never-autofile violated"
fi

echo "== T-nonfinite: --threshold review_fp_min_n=nan/inf is rejected (kit:code-reviewer LOW finding, SPEC-137) =="
NAN_OUT="$(R anomalies --threshold review_fp_min_n=nan 2>&1)"
has "T-nonfinite nan rejected with a clean CLI error, never spliced into SQL" 'must be finite' "$NAN_OUT"
INF_OUT="$(R anomalies --threshold review_fp_min_n=inf 2>&1)"
has "T-nonfinite inf rejected with a clean CLI error" 'must be finite' "$INF_OUT"
# Read STDOUT only: stats now materializes in-memory per invocation (SPEC-182 no-persist),
# so legitimate source-quality warnings (e.g. "skipped N malformed rows") emit to STDERR on
# every call, not once-at-cache-build. The JSON payload is on stdout; a well-behaved consumer
# reads stdout, so the parse check must not conflate the streams.
# bypass R (which folds stderr into stdout) so the per-invocation materialization warning
# does not corrupt the JSON payload; the parse check wants stdout only.
FINITE_OUT="$(uv run stats anomalies --threshold review_fp_min_n=3 --json 2>/dev/null)"
if printf '%s' "$FINITE_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" >/dev/null 2>&1; then
  ok "T-nonfinite a real finite override still parses fine (the guard is non-finite-only)"
else
  bad "T-nonfinite a finite override broke anomalies --json: $FINITE_OUT"
fi

echo "== O-plan: over-test pass targeting read_rejected_findings() directly =="
OVER="$(uv run python3 - <<'PY' 2>&1
from pathlib import Path
from stats import adapters

results = []

# O1: a repo whose docs/verification/rejected-findings.md does not exist at all.
cols, rows = adapters.read_rejected_findings([Path("/nonexistent-o1-repo-xyz")])
results.append(("O1-missing-file", rows == []))

# O2: a repo whose file exists but has zero real rows under "## Rows".
import tempfile
with tempfile.TemporaryDirectory() as td:
    repo = Path(td) / "repo"
    vdir = repo / "docs" / "verification"
    vdir.mkdir(parents=True)
    (vdir / "rejected-findings.md").write_text(
        "# Ledger\n\n## Rows\n\n| date | lens | finding-key | verdict | reason |\n|---|---|---|---|---|\n"
    )
    cols2, rows2 = adapters.read_rejected_findings([repo])
    results.append(("O2-zero-rows-file", rows2 == []))

    # O3: the "## Format" template row must never be read as data (it lives under a
    # DIFFERENT heading than "## Rows").
    repo3 = Path(td) / "repo3"
    vdir3 = repo3 / "docs" / "verification"
    vdir3.mkdir(parents=True)
    (vdir3 / "rejected-findings.md").write_text(
        "# Ledger\n\n## Format\n\n"
        "| date | lens | finding-key | verdict | reason |\n|---|---|---|---|---|\n"
        "| YYYY-MM-DD | some-lens | x:y | rejected | template row, must never count |\n\n"
        "## Rows\n\n| date | lens | finding-key | verdict | reason |\n|---|---|---|---|---|\n"
    )
    cols3, rows3 = adapters.read_rejected_findings([repo3])
    results.append(("O3-format-template-row-ignored", rows3 == []))

for name, passed in results:
    print(f"{name}={'OK' if passed else 'FAIL'}")
PY
)"
has "O1-missing-file OK (no exception, zero rows)"        "O1-missing-file=OK" "$OVER"
has "O2-zero-rows-file OK (a real file with zero rows contributes nothing)" "O2-zero-rows-file=OK" "$OVER"
has "O3-format-template-row-ignored OK (the ## Format section is never read as data)" "O3-format-template-row-ignored=OK" "$OVER"

echo "== G-remat: delete-and-rematerialize is byte-identical (fixture files canonical) =="
# Explicit `rebuild` before EACH `show` (rather than relying on show's lazy _ensure_db) so
# neither capture has the rejected_findings skip-warning line merged into it unevenly.
R rebuild >/dev/null
BEFORE="$(R show rejected_findings --json)"
rm -f "$STATS_DB_REMOVED" "$STATS_DB_REMOVED.wal"
R rebuild >/dev/null
AFTER="$(R show rejected_findings --json)"
if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then ok "G-remat identical output"; else bad "G-remat output differs after delete+rebuild"; fi

echo "== G-nc: read-only negative control (fixture files are never mutated) =="
FIXTURE_AFTER="$(find "$FIXTURE_ROOT" -type f -exec shasum -a 256 {} \; | sort)"
if [ "$FIXTURE_BEFORE" = "$FIXTURE_AFTER" ]; then ok "G-nc fixture ledger files byte-identical after rebuild+queries"; else bad "G-nc a fixture file changed"; fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

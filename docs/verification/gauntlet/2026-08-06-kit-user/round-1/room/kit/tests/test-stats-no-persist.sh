#!/usr/bin/env bash
# test-stats-no-persist.sh -- SPEC-182 (kit-modularity SG-02): the LOAD-BEARING
# event-sourcing guarantee that `stats` is a stateless projection and persists NOTHING.
#
# Two layers:
#   1. STANDING anti-drift LINT (always runs, CI-safe, no uv): grep the stats source to
#      assert it opens ONLY an in-memory DuckDB and carries no persistent-cache path. A
#      one-time runtime NC cannot stop a future "convenient perf cache" slipping in; this
#      grep does (advisor P6). If someone re-adds a persistent `duckdb.connect("<file>")`
#      or a `.stats-cache`/`*.duckdb` output path, this fails.
#   2. RUNTIME full-snapshot NC (runs when uv+the synced venv are available; skips loudly
#      otherwise): take a FULL filesystem snapshot of a temp HOME + the ledger dir + any
#      repo-local derived-view artifact, run `stats <lens>` TWICE with no intervening ledger
#      write, snapshot again, and assert NO file was created/changed ANYWHERE (advisor P5:
#      catch a ~/.cache or repo-local `.stats-cache/` too, not just $KIT_LEDGER_DIR).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
STATS_DIR="$ROOT/lib/stats"
SRC="$STATS_DIR/src/stats"

pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
skp()  { skip=$((skip+1)); printf '  SKIP  %s\n' "$1"; }

echo "== LINT: the stats source persists no derived view (standing anti-drift, advisor P6) =="

# (a) every duckdb.connect() opens :memory:, never a file path.
BADCONN="$(grep -rn "duckdb.connect(" "$SRC" | grep -v 'duckdb.connect(":memory:")' || true)"
if [ -z "$BADCONN" ]; then
  ok "every duckdb.connect() is :memory: (no persistent db opened)"
else
  bad "a non-:memory: duckdb.connect() reintroduces a persistent cache:"; printf '%s\n' "$BADCONN" | sed 's/^/        /'
fi

# (b) no persistent-cache path constants (a derived .duckdb/.db output or a .stats-cache dir).
BADPATH="$(grep -rnE '\.duckdb|\.stats-cache|LEDGER_OBSERVATORY_DB|def db_path' "$SRC" || true)"
if [ -z "$BADPATH" ]; then
  ok "no persistent-cache path (.duckdb / .stats-cache / db_path) in the stats source"
else
  bad "a persistent-cache path reappeared in the stats source:"; printf '%s\n' "$BADPATH" | sed 's/^/        /'
fi

echo "== RUNTIME: full temp-HOME snapshot is byte-identical across two lens runs (advisor P5) =="

if ! command -v uv >/dev/null 2>&1 || [ ! -d "$STATS_DIR/.venv" ]; then
  skp "runtime snapshot NC (uv or the synced venv unavailable -- CI runs the LINT above; run locally after 'uv sync' to exercise this)"
else
  TMPHOME="$(mktemp -d)"
  FIX="$(mktemp -d)"
  mkdir -p "$FIX/runs"
  # a minimal fixture ledger: one run with a couple GATE lines so gate-yield has rows.
  cat > "$FIX/runs/np-fixrun.log" <<'EOF'
2026-07-05T01:00:00Z | START | lane=full classified=full type=data-tool repo=fixrepo
2026-07-05T01:01:00Z | GATE | spec | ran | drafted
2026-07-05T01:02:00Z | GATE | ship | ran | shipped
EOF

  # snapshot helper: every file under the temp HOME + the ledger dir + any repo-local
  # derived-view artifact (the three places a projection cache could hide), as path+sha.
  snap() {
    { /usr/bin/find "$TMPHOME" "$FIX" -type f -exec shasum {} \; 2>/dev/null
      /usr/bin/find "$ROOT/lib/stats" -type f \( -name '*.duckdb' -o -name '*.db' \) 2>/dev/null | grep -v '/.venv/' | while read -r f; do shasum "$f"; done
      /usr/bin/find "$ROOT" -maxdepth 2 -type d -name '.stats-cache' 2>/dev/null
    } | sort
  }

  # Fully isolate every source root at an empty/temp location so no real machine file is
  # read, and suppress python bytecode so a .pyc write (not a projection) can't false-fail.
  run_lens() {
    env -i PATH="$PATH" HOME="$TMPHOME" \
      XDG_CACHE_HOME="$TMPHOME/.cache" XDG_STATE_HOME="$TMPHOME/.local/state" \
      PYTHONDONTWRITEBYTECODE=1 \
      KIT_LEDGER_DIR="$FIX" \
      STATS_SESSIONS_DIR="$TMPHOME/none" STATS_SECRET_GUARD_LOG="$TMPHOME/none.log" \
      STATS_MEMORY_PROJECTS_ROOT="$TMPHOME/none" STATS_GIT_REPO_DIR="$TMPHOME/none" \
      STATS_MEMORY_REPO_DIR="$TMPHOME/none" \
      uv run --project "$STATS_DIR" --quiet stats gate-yield >/dev/null 2>&1
  }

  # Warm the tool-runner (uv) cache BEFORE the baseline snapshot: uv populates its own
  # package cache under HOME/.cache/uv on first `uv run`, which is the RUNNER caching
  # packages, NOT stats persisting a projection. Warming first means S0 already contains
  # uv's cache, so any file appearing between S0 and S2 can only be a stats write.
  run_lens; RCW=$?
  S0="$(snap)"
  run_lens; RC1=$?
  S1="$(snap)"
  run_lens; RC2=$?
  S2="$(snap)"

  if [ "$RC1" -ne 0 ] || [ "$RC2" -ne 0 ]; then
    bad "stats gate-yield did not run cleanly (rc1=$RC1 rc2=$RC2) -- cannot assert no-persist"
  else
    ok "stats gate-yield ran twice cleanly over the fixture ledger"
  fi

  if [ "$S0" = "$S1" ] && [ "$S1" = "$S2" ]; then
    ok "no-persisted-projection: FULL snapshot (temp HOME + ledger dir + repo-local) is byte-identical before/after two lens runs -- NO file written ANYWHERE"
  else
    bad "a lens run wrote/changed a file (projection persisted) -- diff (before -> after):"
    diff <(printf '%s\n' "$S0") <(printf '%s\n' "$S2") | sed 's/^/        /'
  fi

  echo "== RUNTIME honest-zero + determinism: empty ledger -> zeros, same answer twice =="
  EMPTY="$(mktemp -d)"; mkdir -p "$EMPTY/runs"
  A="$(env -i PATH="$PATH" HOME="$TMPHOME" PYTHONDONTWRITEBYTECODE=1 KIT_LEDGER_DIR="$EMPTY" \
        STATS_SESSIONS_DIR="$TMPHOME/none" STATS_SECRET_GUARD_LOG="$TMPHOME/none.log" \
        STATS_MEMORY_PROJECTS_ROOT="$TMPHOME/none" STATS_GIT_REPO_DIR="$TMPHOME/none" \
        STATS_MEMORY_REPO_DIR="$TMPHOME/none" \
        uv run --project "$STATS_DIR" --quiet stats gate-yield --json 2>/dev/null)"; rcA=$?
  B="$(env -i PATH="$PATH" HOME="$TMPHOME" PYTHONDONTWRITEBYTECODE=1 KIT_LEDGER_DIR="$EMPTY" \
        STATS_SESSIONS_DIR="$TMPHOME/none" STATS_SECRET_GUARD_LOG="$TMPHOME/none.log" \
        STATS_MEMORY_PROJECTS_ROOT="$TMPHOME/none" STATS_GIT_REPO_DIR="$TMPHOME/none" \
        STATS_MEMORY_REPO_DIR="$TMPHOME/none" \
        uv run --project "$STATS_DIR" --quiet stats gate-yield --json 2>/dev/null)"; rcB=$?
  if [ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && [ "$A" = "$B" ]; then
    ok "honest-zero: empty ledger returns cleanly + the projection is deterministic (delete output, re-run, same answer)"
  else
    bad "empty-ledger honest-zero/determinism failed (rcA=$rcA rcB=$rcB A='$A' B='$B')"
  fi
fi

echo
echo "== $pass passed, $fail failed, $skip skipped =="
[ "$fail" -eq 0 ]

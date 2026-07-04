#!/usr/bin/env bash
# test-schema-parity.sh -- regression guard for the schema-drift bug: adapters.py's
# column-name lists and materialize.py's CREATE TABLE DDL used to be two independently
# hand-synced definitions with nothing checking they agreed on names/order, so a
# same-length reordering of one without the other would silently mislabel every column
# loaded into DuckDB. The fix (schemas.py) makes both derive from one (name, type) spec
# per table, plus a load-time schemas.assert_parity() belt-and-suspenders check.
#
# This test proves two things:
#   1. POSITIVE: for all 3 Python-sourced tables, adapters.*_COLUMNS today matches the
#      DDL column names/order materialize.py actually loads with (real code, not a copy).
#   2. NEGATIVE (load-bearing): schemas.assert_parity() itself RAISES when handed a
#      deliberately reordered/mismatched pair -- i.e. if this fix's guard were removed or
#      broken, a drift like the original bug would be caught, not silently accepted.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()  { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "== P-parity: adapters.*_COLUMNS matches materialize.*_DDL column names/order today =="
OUT="$(uv run python3 - <<'PY' 2>&1
from ledger_observatory import adapters, materialize, schemas

def ddl_names(ddl):
    return [part.strip().split()[0] for part in ddl.split(",") if part.strip()]

checks = [
    ("kit_runs", adapters.KIT_COLUMNS, materialize._KIT_DDL),
    ("tg_dialogs", adapters.TG_COLUMNS, materialize._TG_DDL),
    ("learned", adapters.LEARNED_COLUMNS, materialize._LEARNED_DDL),
]
for name, cols, ddl in checks:
    got = ddl_names(ddl)
    if got == list(cols):
        print(f"OK {name}: {len(cols)} columns, names/order match")
    else:
        print(f"MISMATCH {name}: adapter={cols!r} ddl={got!r}")

# assert_parity() itself must accept the real (matching) pairs without raising.
for name, cols, ddl in checks:
    schemas.assert_parity(cols, ddl)
print("assert_parity: all 3 real table pairs accepted")
PY
)"
RC=$?
echo "$OUT"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q MISMATCH \
   && printf '%s' "$OUT" | grep -q "assert_parity: all 3 real table pairs accepted"; then
  ok "P-parity all 3 tables' adapter columns match their DDL, assert_parity accepts them"
else
  bad "P-parity adapter/DDL mismatch or assert_parity rejected a real pair (rc=$RC)"
fi

echo
echo "== N-drift (load-bearing negative control): assert_parity RAISES on a reordered pair =="
# Simulates exactly the original bug: same length, same column set, but the DDL's
# column ORDER no longer matches the adapter's column-name order (a "same-length
# reordering" -- the failure mode named in the bug report).
NC_OUT="$(uv run python3 - <<'PY' 2>&1
from ledger_observatory import schemas

cols = ["rid", "repo", "lane"]
reordered_ddl = "repo VARCHAR, rid VARCHAR, lane VARCHAR"  # rid/repo swapped
try:
    schemas.assert_parity(cols, reordered_ddl)
    print("NO-RAISE: assert_parity silently accepted a reordered schema")
except AssertionError as e:
    print(f"RAISED: {e}")
PY
)"
echo "$NC_OUT"
if printf '%s' "$NC_OUT" | grep -q '^RAISED:'; then
  ok "N-drift reordered columns REJECTED (AssertionError raised)"
else
  bad "N-drift reordered columns NOT rejected -- the guard would miss the original bug"
fi

echo
echo "== N-drift-missing (negative control): assert_parity RAISES on a dropped column =="
NC2_OUT="$(uv run python3 - <<'PY' 2>&1
from ledger_observatory import schemas

cols = ["date", "item", "kind", "home", "status"]
short_ddl = "date VARCHAR, item VARCHAR, kind VARCHAR, home VARCHAR"  # 'status' missing
try:
    schemas.assert_parity(cols, short_ddl)
    print("NO-RAISE: assert_parity silently accepted a column-count mismatch")
except AssertionError as e:
    print(f"RAISED: {e}")
PY
)"
echo "$NC2_OUT"
if printf '%s' "$NC2_OUT" | grep -q '^RAISED:'; then
  ok "N-drift-missing dropped column REJECTED (AssertionError raised)"
else
  bad "N-drift-missing dropped column NOT rejected"
fi

echo
echo "== R-load: rebuild() actually calls the guard (not just importable) =="
# Prove _load_python_table really invokes assert_parity by monkeypatching it to raise
# unconditionally, then confirming rebuild() propagates that failure -- if the call
# site were ever deleted, this goes from FAIL(raised) to a silent pass.
FIX="$(mktemp -d)"
GUARD_OUT="$(env \
  DWARVES_KIT_LOG_DIR="$FIX/kitlogs" \
  LEDGER_OBS_TIDE_DB="$FIX/state.sqlite" \
  LEDGER_OBS_TGCLEANUP_DIR="$FIX/tg" \
  LEDGER_OBS_LEARNED_MD="$FIX/learned-ledger.md" \
  LEDGER_OBS_SESSIONS_DIR="$FIX/nonexistent-sessions-dir" \
  LEDGER_OBS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log" \
  LEDGER_OBS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo" \
  LEDGER_OBS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects" \
  LEDGER_OBSERVATORY_DB="$FIX/lens.duckdb" \
  uv run python3 - <<'PY' 2>&1
from ledger_observatory import materialize, schemas

def always_raise(cols, ddl):
    raise AssertionError("forced: parity guard was invoked")

schemas.assert_parity = always_raise
materialize.schemas.assert_parity = always_raise
try:
    materialize.rebuild()
    print("NO-RAISE: rebuild() completed without ever calling assert_parity")
except AssertionError as e:
    print(f"RAISED: {e}")
PY
)"
echo "$GUARD_OUT"
if printf '%s' "$GUARD_OUT" | grep -q 'RAISED: forced: parity guard was invoked'; then
  ok "R-load rebuild() invokes assert_parity on the real load path"
else
  bad "R-load rebuild() did not invoke assert_parity -- guard is dead code"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

#!/bin/bash
# test-harvest-sweep.sh -- tests for the harvest sweep (SPEC-357) and the shared
# stager it reuses from hooks/harvest.py. The extractor is always a stub; nothing
# here touches real transcripts, real launchd, or a real model.
#
# Run: bash tests/test-harvest-sweep.sh
# Exit 0 = all tests pass. Exit 1 = failures found.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TD="$(mktemp -d "${TMPDIR:-/tmp}/harvest-sweep-test.XXXXXX")"
trap 'rm -rf "${TD:?}"' EXIT

export HARVEST_STATE_DIR="$TD/state"
export HARVEST_SWEEP_CLAUDE_ROOT="$TD/claude-root"
export HARVEST_SWEEP_DEVIN_DB="$TD/devin.db"
export HARVEST_SWEEP_LAUNCH_RECORD="$TD/launch-record"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local NAME="$1" EXPECTED="$2" ACTUAL="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME (expected '$EXPECTED', got '$ACTUAL')"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
echo "=== T1 shared stager ==="

# One in-process run prints one KEY=VALUE line per check; the bash side asserts each.
T1_OUT=$(KIT_DIR="$KIT_DIR" TD="$TD" python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("harvest", os.path.join(os.environ["KIT_DIR"], "hooks", "harvest.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

ledger = os.path.join(os.environ["TD"], "t1", "ledger.md")
lines = lambda: open(ledger).read().splitlines() if os.path.exists(ledger) else []

fresh = h._stage_candidates(ledger, [], [
    {"item": "Alpha Thing", "kind": "insight", "home": "til"},
    {"item": "alpha thing", "kind": "insight", "home": "til"},
    {"item": "Beta", "kind": "bogus-kind", "home": "bogus-home"},
    "not a dict",
])
print("fresh_items=" + ",".join(r["item"] for r in fresh))
print("batch_dedup=" + str(len(fresh)))
beta = [r for r in fresh if r["item"] == "beta"][0]
print("beta_map=%s/%s" % (beta["kind"], beta["home"]))
print("header_count=" + str(sum(1 for l in lines() if l.startswith("| date |"))))
print("row_count=" + str(sum(1 for l in lines() if l.endswith("| queued |"))))

again = h._stage_candidates(ledger, [], [{"item": "Alpha Thing"}, {"item": "Gamma"}])
print("ledger_dedup=" + ",".join(r["item"] for r in again))
print("header_count_after=" + str(sum(1 for l in lines() if l.startswith("| date |"))))

before = open(ledger).read()
none = h._stage_candidates(ledger, [], [{"item": "Alpha Thing"}, {"item": "Gamma"}])
print("all_known=" + repr(none))
print("all_known_unchanged=" + str(open(ledger).read() == before))
PY
)
get() { printf '%s\n' "$T1_OUT" | sed -n "s/^$1=//p"; }

assert_eq "T1: returns only the fresh rows" "alpha-thing,beta" "$(get fresh_items)"
assert_eq "T1: dedups exact slugs within the batch" "2" "$(get batch_dedup)"
assert_eq "T1: unknown kind/home map to insight/drop" "insight/drop" "$(get beta_map)"
assert_eq "T1: writes the ledger header once" "1" "$(get header_count)"
assert_eq "T1: appends one queued row per fresh item" "2" "$(get row_count)"
assert_eq "T1: dedups against the existing ledger" "gamma" "$(get ledger_dedup)"
assert_eq "T1: header stays single after a second append" "1" "$(get header_count_after)"
assert_eq "T1: all-known batch returns []" "[]" "$(get all_known)"
assert_eq "T1: all-known batch writes nothing" "True" "$(get all_known_unchanged)"

# ============================================================
echo ""
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
echo -e "${GREEN}All harvest sweep tests passed.${NC}"

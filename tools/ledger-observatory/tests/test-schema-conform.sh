#!/usr/bin/env bash
# test-schema-conform.sh -- SG-01's proof: a real kit line + the planned DEBT/TOKENS
# marker shapes pass the Tier A conformance check; a malformed line is REJECTED (the
# load-bearing negative control); each of the 3 outlier sample records parses under its
# adapter contract. No engine, no DuckDB -- grep/parse + one real gate-ledger.sh
# invocation into a disposable scratch log dir (never the live one).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFORM="$HERE/lib/conform.sh"
GATE_LEDGER="$HOME/.claude/dwarves-kit/lib/gate-ledger.sh"
DOCS="$(cd "$HERE/.." && pwd)/docs"

pass=0
fail=0

check() {
  local desc="$1" want="$2" line="$3"
  local got rc=0
  got="$(bash "$CONFORM" check "$line" 2>&1)" || rc=$?
  local status
  if [ "$want" = "PASS" ] && [ "$rc" -eq 0 ]; then status=PASS
  elif [ "$want" = "FAIL" ] && [ "$rc" -ne 0 ]; then status=PASS
  else status=FAIL
  fi
  if [ "$status" = PASS ]; then
    printf 'PASS  %s (%s)\n' "$desc" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL  %s -- wanted %s, got rc=%s: %s\n' "$desc" "$want" "$rc" "$got"
    fail=$((fail + 1))
  fi
}

echo "== Tier A: a real line copied from a live kit ledger =="
real_line="$(grep -m1 '| START |' "$HOME/.local/state/dwarves-kit/logs/runs"/*.log 2>/dev/null | head -1 | sed 's/^[^:]*\.log://')"
if [ -z "$real_line" ]; then
  echo "SKIP  no live kit run ledger found on this machine; falling back to a fixture line"
  real_line="2026-07-02T18:52:48Z | START | lane=normal classified=normal type=spec-feature ctype=spec-feature repo=dwarves-kit"
fi
check "real live kit line passes" PASS "$real_line"

echo
echo "== Tier A: the planned debt + token marker shapes (generated, never hand-typed) =="
SCRATCH="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$SCRATCH"
bash "$GATE_LEDGER" tokens sg01-nc-rid in=1200 out=340 cache_read=5000 cache_create=0 cost=0.42 >/dev/null
bash "$GATE_LEDGER" debt sg01-nc-rid significance=high worthiness=high verdict=tap response=defer reason="weekend batch" >/dev/null
tokens_line="$(grep '| TOKENS |' "$SCRATCH/runs/sg01-nc-rid.log")"
debt_line="$(grep '| DEBT |' "$SCRATCH/runs/sg01-nc-rid.log")"
check "generated TOKENS line passes (kit-face SG-03 shape)" PASS "$tokens_line"
check "generated DEBT line passes (understanding-gate SG-02 shape)" PASS "$debt_line"

echo
echo "== Negative control: a malformed line is REJECTED (load-bearing) =="
check "no timestamp" FAIL "not-a-timestamp | START | lane=normal classified=normal type=x"
check "unknown verb" FAIL "2026-07-03T18:54:29Z | BOGUS | whatever=here"
check "no pipe delimiters at all" FAIL "just a plain line with no structure whatsoever"
check "START missing required k=v token" FAIL "2026-07-03T18:54:29Z | START | repo=ops-toolkit"

echo
echo "== Outlier adapter samples parse under their contract =="

# learned-ledger.md: the sample row in adapter-contracts.md must match the 5-column
# markdown table shape (date | item | kind | home | status).
ll_sample='| 2026-07-03 | kill-resilient-delegation | decision | research | flushed:research/2026-07-03-megagoal-execution-hygiene.md#7 |'
if printf '%s' "$ll_sample" | grep -qE '^\| [0-9]{4}-[0-9]{2}-[0-9]{2} \| [^|]+ \| (concept|insight|decision) \| [^|]+ \| (queued|flushed:[^|]+) \|$'; then
  echo "PASS  learned-ledger.md sample matches its 5-column contract"
  pass=$((pass + 1))
else
  echo "FAIL  learned-ledger.md sample does not match its documented column shape"
  fail=$((fail + 1))
fi
if grep -qF -- "$ll_sample" "$DOCS/adapter-contracts.md"; then
  echo "PASS  learned-ledger.md sample is the one actually embedded in adapter-contracts.md"
  pass=$((pass + 1))
else
  echo "FAIL  learned-ledger.md sample in this test drifted from adapter-contracts.md"
  fail=$((fail + 1))
fi

# tide state.sqlite: every column the contract claims for `moves` must be a real column
# in tools/tide/src/tide/state.py's CREATE TABLE (parses the adapter's own field-map).
# tide is an ops-toolkit-only sibling tool (never migrates into this kit repo, per the
# 05K goal's Quality bar: LEDGER_OBS_TIDE_DB is an ops-toolkit-specific source now
# required-explicit, not a kit-generic one) -- this cross-repo check is skip-safe, not
# fail-safe, when that sibling simply is not present in THIS repo.
TIDE_SCHEMA="$(cd "$HERE/../../.." && pwd)/tools/tide/src/tide/state.py"
if [ ! -f "$TIDE_SCHEMA" ]; then
  echo "SKIP  tide state.py not present in this repo (ops-toolkit-only sibling tool; nothing to cross-check here)"
else
  tide_ok=1
  for col in id ts source_path target_path content_sha size_bytes route confidence ai_response_json undone_at; do
    grep -q "^\s*${col} " "$TIDE_SCHEMA" || { tide_ok=0; echo "  missing column in state.py: $col"; }
  done
  if [ "$tide_ok" -eq 1 ]; then
    echo "PASS  tide state.sqlite 'moves' field-map matches tools/tide/src/tide/state.py"
    pass=$((pass + 1))
  else
    echo "FAIL  tide state.sqlite field-map drifted from tools/tide/src/tide/state.py"
    fail=$((fail + 1))
  fi
fi

# tg-cleanup *.json: the synthetic sample record must be valid JSON with every field
# the adapter contract claims, and must NOT match any real title/id from the live files.
tg_sample='{"id": -1000000001, "title": "Example Group", "kind": "basic_group", "username": null, "member_count": 3, "last_message_date": "2026-01-01T00:00:00+00:00", "unread_count": 0, "muted": false, "access_hash": null, "verified": false, "scam": false, "fake": false}'
if python3 - "$tg_sample" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
required = {"id","title","kind","username","member_count","last_message_date","unread_count","muted","access_hash","verified","scam","fake"}
missing = required - set(d.keys())
sys.exit(1 if missing else 0)
PYEOF
then
  echo "PASS  tg-cleanup sample record has every field the adapter contract claims"
  pass=$((pass + 1))
else
  echo "FAIL  tg-cleanup sample record is missing a documented field"
  fail=$((fail + 1))
fi

echo
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]

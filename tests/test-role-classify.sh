#!/usr/bin/env bash
# test-role-classify.sh -- the shared specialist-domain classifier (SPEC-089).
# Deterministic keyword heuristic; every domain has a positive case + the generic
# fall-through is asserted (a plain task must NOT be over-specialized).
set -u
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RC="$KIT_DIR/lib/role-classify.sh"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
expect() {  # expect "<desc>" <domain>
  TOTAL=$((TOTAL+1)); local got; got="$(bash "$RC" classify "$1")"
  if [ "$got" = "$2" ]; then PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} [$2] $1"
  else FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} want [$2] got [$got]: $1"; fi
}

echo "=== one positive case per domain ==="
expect "harden the login endpoint with constant-time password compare" security
expect "audit the workflow for hardcoded secrets and injection" security
expect "add a migration to backfill the users.status column" db-migration
expect "alter table orders to add an index on created_at" db-migration
expect "build a responsive settings modal component with aria labels" frontend
expect "the report query is slow, cache the hot path to cut latency" performance
expect "parse the CSV export and ingest it into DuckDB" data-etl
expect "deploy the cloudflare worker via wrangler and add a DNS record" infra
expect "add a POST /orders endpoint with a request schema and handler" api

echo ""
echo "=== generic fall-through (must NOT over-specialize plain tasks) ==="
expect "rename a variable and fix a typo in the README" generic
expect "update the changelog for the release" generic
expect "reword the help text on the start command" generic

echo ""
echo "=== interface ==="
TOTAL=$((TOTAL+1)); n="$(bash "$RC" domains | wc -l | tr -d ' ')"
if [ "$n" -ge 8 ]; then PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} domains lists >=8 names ($n)"; else FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} domains ($n)"; fi
TOTAL=$((TOTAL+1))
if bash "$RC" explain "harden auth" | grep -q 'matched:'; then PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} explain shows the matched phrase"; else FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} explain"; fi
TOTAL=$((TOTAL+1))
if bash "$RC" classify >/dev/null 2>&1; then FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} classify with no arg should error"; else PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} classify with no arg errors (exit!=0)"; fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

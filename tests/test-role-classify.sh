#!/usr/bin/env bash
# test-role-classify.sh -- the shared specialist-domain classifier (SPEC-089).
# Deterministic keyword heuristic; every domain has a positive case + the generic
# fall-through is asserted (a plain task must NOT be over-specialized).
set -u
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RC="$KIT_DIR/lib/classify/role-classify.sh"
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
echo "=== agent-for lookup (SPEC-111: worker domains -> workers; reviewers/generic -> empty) ==="
TOTAL=$((TOTAL+1)); [ "$(bash "$RC" agent-for db-migration)" = "db-migration-worker" ] && { PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} agent-for db-migration -> db-migration-worker"; } || { FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} agent-for db-migration"; }
TOTAL=$((TOTAL+1)); [ "$(bash "$RC" agent-for data-etl)" = "data-etl-worker" ] && { PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} agent-for data-etl -> data-etl-worker"; } || { FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} agent-for data-etl"; }
for d in performance api frontend infra security generic; do
  TOTAL=$((TOTAL+1)); [ -z "$(bash "$RC" agent-for "$d")" ] && { PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} agent-for $d -> empty (reviewer via review-team / Mode-C, not a 2b-0 worker)"; } || { FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} agent-for $d should be empty"; }
done
# reuse-HIT chain: a worker-domain task classifies then resolves to its worker (the 2b-0 reuse source)
TOTAL=$((TOTAL+1)); D=$(bash "$RC" classify "write a migration to add a column and backfill the table"); [ "$(bash "$RC" agent-for "$D")" = "db-migration-worker" ] && { PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} reuse-hit chain: migration task -> db-migration-worker"; } || { FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} reuse-hit chain (got domain='$D')"; }

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

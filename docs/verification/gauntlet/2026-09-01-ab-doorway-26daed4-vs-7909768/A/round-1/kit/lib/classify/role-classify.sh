#!/usr/bin/env bash
# role-classify.sh -- deterministic task description -> SPECIALIST DOMAIN (SPEC-089).
#
# A cheap FAST-PATH hint for high-frequency specialist domains. It is NOT the role
# universe: the role space is open-ended, and the meta-agent (Mode C) is the
# authority that can name ANY role (technical-doc-writer, typescript-dev,
# ui-designer, solidity-auditor, ...). This classifier only exists to skip the LLM
# hop for the common domains it DOES know.
#
# So a `generic` result does NOT mean "use a generic worker". It means "no fast-path
# match, escalate to meta-agent Mode C for open-ended role inference"; only Mode C's
# own NO_SPECIALIST verdict falls through to a plain worker. See SPEC-089.
#
# Pure keyword heuristic: no LLM, no network, deterministic (same desc -> same
# domain). First clear match wins; order is specificity, not priority. Peer of
# lane-classify.sh (which lane) and task-type-classify.sh (which work type).
#
# Usage:
#   role-classify.sh classify "<task description>"   -> the domain, exit 0
#   role-classify.sh domains                          -> the domain names, one per line
#   role-classify.sh explain  "<task description>"   -> domain + the phrase that matched
#
# Override the domain set/keywords by editing this file (mirrors task-type-classify.sh).
set -euo pipefail

DOMAINS="security db-migration frontend performance data-etl infra api generic"

# Emit "<domain>\t<matched-regex-label>" for a description; generic if nothing matches.
_role_match() {
  local lc; lc="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')"

  # security: auth / crypto / secrets / injection / access control.
  if printf '%s' "$lc" | grep -qE 'security|auth(entication|orization)?|\boauth\b|login|password|credential|secret|token|crypto|encrypt|decrypt|hash(ing)?|constant-time|timing attack|injection|\bxss\b|\bcsrf\b|\bssrf\b|sanitiz|input validation|permission|access control|rate.?limit|lockout|vulnerab|\bcve\b|harden'; then
    echo "security	auth/crypto/secrets/injection"; return 0; fi

  # db-migration: schema + data shape change.
  if printf '%s' "$lc" | grep -qE 'migrat(e|ion)|schema (change|migration|version)|backfill|\bddl\b|alter table|create table|add (a )?column|drop (a )?column|reindex|\bindex\b .*(add|create|drop)|data model|\borm\b|foreign key'; then
    echo "db-migration	schema/migration/backfill"; return 0; fi

  # frontend: UI surface.
  if printf '%s' "$lc" | grep -qE 'frontend|front-end|\bui\b|\bux\b|component|\bcss\b|tailwind|stylesheet|button|modal|form (field|input|layout)|accessib(le|ility)|\ba11y\b|\baria\b|render(ing)?|viewport|responsive|dark mode|\bdom\b'; then
    echo "frontend	ui/component/css/a11y"; return 0; fi

  # performance: make it faster / cheaper.
  if printf '%s' "$lc" | grep -qE 'performance|latency|throughput|profil(e|ing)|\bslow\b|speed ?up|optimi[sz]e|hot path|bottleneck|\bcache\b|caching|memoiz|n\+1|benchmark|\bp9[59]\b|memory (leak|usage|footprint)'; then
    echo "performance	latency/profiling/cache"; return 0; fi

  # data-etl: move/transform data.
  if printf '%s' "$lc" | grep -qE 'pipeline|\betl\b|extract.?transform|transform (the )?data|ingest|parse[dr]?|parsing|\bcsv\b|\bjsonl\b|duckdb|dataframe|polars|pandas|aggregate|dedup|normali[sz]e (the )?data|data (load|import|export)'; then
    echo "data-etl	pipeline/transform/ingest"; return 0; fi

  # infra: deploy / ops / host.
  if printf '%s' "$lc" | grep -qE 'deploy|\bci\b|\bcd\b|pipeline (yaml|config)|github actions|workflow file|container|docker|compose|kubernetes|\bk8s\b|daemon|launchd|\bplist\b|systemd|terraform|opentofu|\biac\b|cloudflare worker|wrangler|dns record|reverse proxy|caddy|nginx'; then
    echo "infra	deploy/ci/container/iac"; return 0; fi

  # api: server contract surface.
  if printf '%s' "$lc" | grep -qE '\bapi\b|endpoint|\brest\b|\bgraphql\b|\brpc\b|\bgrpc\b|handler|route (handler|path)|request (body|param|schema)|response (body|schema|code)|openapi|swagger|webhook|\bclient sdk\b|api (contract|client|version)'; then
    echo "api	endpoint/handler/contract"; return 0; fi

  echo "generic	(no domain keyword matched)"; return 0
}

# agent-for <domain>: the predefined WORKER agent for a domain (the execute.md 2b-0 reuse target,
# an IMPLEMENTER), or EMPTY. Reviewers are deliberately NOT here , a read-only reviewer cannot
# implement a task, so it dispatches via /kit:review-team's domain lenses, not the 2b-0 worker slot
# (SPEC-111). `generic` returns empty so 2b-0 falls through to Mode-C synthesis (SPEC-089:79, the
# dynamic long tail); a generic->agent map would collapse that escalation.
agent_for() {
  case "${1:-}" in
    db-migration) echo "db-migration-worker" ;;
    data-etl)     echo "data-etl-worker" ;;
    *)            : ;;   # reviewer domains / security / generic / unknown -> empty
  esac
}

cmd="${1:-}"; shift || true
case "$cmd" in
  classify) [ -n "${1:-}" ] || { echo "usage: role-classify.sh classify \"<task>\"" >&2; exit 2; }
            _role_match "$*" | cut -f1 ;;
  explain)  [ -n "${1:-}" ] || { echo "usage: role-classify.sh explain \"<task>\"" >&2; exit 2; }
            _role_match "$*" | awk -F'\t' '{print $1"  <- matched: "$2}' ;;
  domains)  printf '%s\n' $DOMAINS ;;
  agent-for) [ -n "${1:-}" ] || { echo "usage: role-classify.sh agent-for <domain>" >&2; exit 2; }
            agent_for "$1" ;;
  *) echo "usage: role-classify.sh {classify|explain|domains|agent-for} [\"<task>\"|<domain>]" >&2; exit 2 ;;
esac

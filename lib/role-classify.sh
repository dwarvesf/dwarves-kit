#!/usr/bin/env bash
# role-classify.sh -- deterministic task description -> SPECIALIST DOMAIN (SPEC-089).
#
# The third kit classifier, a peer of lane-classify.sh (which lane) and
# task-type-classify.sh (which work type). This one answers: does a task need a
# specialist ROLE, and which one? It is the shared primitive behind dynamic agent
# synthesis: any command (/kit:execute 2b-0, /kit:next, /kit:dispatch, a mega-goal
# orchestrator) calls it to decide whether to synthesize + inject a specialist
# preamble (via meta-agent Mode C) or fall through to a generic worker.
#
# Pure keyword heuristic: no LLM, no network, deterministic (same desc -> same
# domain). "generic" is the deliberate default so plain tasks are never
# over-specialized. First clear match wins; order is specificity, not priority.
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

cmd="${1:-}"; shift || true
case "$cmd" in
  classify) [ -n "${1:-}" ] || { echo "usage: role-classify.sh classify \"<task>\"" >&2; exit 2; }
            _role_match "$*" | cut -f1 ;;
  explain)  [ -n "${1:-}" ] || { echo "usage: role-classify.sh explain \"<task>\"" >&2; exit 2; }
            _role_match "$*" | awk -F'\t' '{print $1"  <- matched: "$2}' ;;
  domains)  printf '%s\n' $DOMAINS ;;
  *) echo "usage: role-classify.sh {classify|explain|domains} [\"<task>\"]" >&2; exit 2 ;;
esac

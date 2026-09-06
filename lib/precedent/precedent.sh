#!/usr/bin/env bash
# precedent.sh -- "have we done something like this before?" at intake (SPEC-068 / ID-056,
# promoted to a subsystem dir + the inventory surface by SPEC-245).
#
# The kit WRITES knowledge constantly (specs, retros, run ledgers, ADRs) but nothing READ
# it back at intake, so every new task started from a blank page. The `records` surface is
# that read-back: keyword-grep the durable surfaces, rank files by distinct-keyword hits,
# print the top matches. Grep-based by design: no embeddings, no index, no daemon.
#
# SPEC-068 answered the written record only. A task can still duplicate a tool, script,
# skill, cron, or memory note, none of which live in docs/. The `inventory` surface (SPEC-245)
# answers that half by scanning what has been BUILT, delegated to `inventory.py` beside this
# file (a dozen iterators and a scorer, past what grep pipelines express well). `all` runs
# both and prints one digest. /kit:assign and /kit:grill call `find` right after
# classification so prior art shapes the questions and the Done=.
#
# Usage:
#   precedent.sh find "<task description>" [max]
#       -> ranked precedent list from the written record (default max 5); the legacy,
#          records-only call shape every existing caller uses.
#   precedent.sh find "<words>" [--surface records|inventory|all] [--limit N] [--quiet]
#                                [--json] [--registry <file>] [--repo-root <path>]
#       -> `--surface` default `all`: records block, then inventory sections, then a
#          summary line. `records` alone is byte-identical to the legacy call.
#   precedent.sh find --explain "<hit label as printed>"
#       -> the header of the file behind an inventory hit label.
#   precedent.sh -h | --help | help
#
# Surfaces searched (repo-relative when present): docs/specs/, docs/decisions/,
# docs/retro/, docs/verification/, plus run-ledger reasons in $DWARVES_KIT_LOG_DIR/runs/
# (records); tools, scripts, skills, crons, memory per the registry (inventory).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"
KIT_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)"
# shellcheck source=lib/config/kit-config.sh
source "$LIB_ROOT/config/kit-config.sh" || { echo "FATAL: lib/config/kit-config.sh missing or unreadable" >&2; exit 1; }

ROOT=""  # resolved per-call in cmd_find, once --repo-root is known

_usage() {
  sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# repo-root resolution precedence (lib/board/board.sh:158-168): --repo-root flag > REPO_ROOT
# env > `git rev-parse --show-toplevel` > cwd.
_resolve_root() {
  local flag="$1"
  if [ -n "$flag" ]; then printf '%s\n' "$flag"; return; fi
  if [ -n "${REPO_ROOT:-}" ]; then printf '%s\n' "$REPO_ROOT"; return; fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# keywords: lowercase, dedup, drop stopwords + short tokens; keep the 8 most specific
_keywords() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '\n' \
    | grep -vE '^(the|a|an|and|or|to|of|in|on|for|with|into|from|that|this|it|is|are|be|as|at|by|we|our|all|any|via|per|the)$' \
    | grep -vE '^-' | awk 'length($0) >= 4' | sort -u | head -8 || true   # empty after filtering is a valid result, not a pipeline failure
}

# _records_find: the SPEC-068 body, unchanged. Byte-identical output to the pre-SPEC-245
# `lib/precedent.sh find` for the same input (the parity pin in the tests). Reads the global
# ROOT + LOG_DIR set by cmd_find before calling this.
_records_find() {
  local desc="${1:-}" max="${2:-5}"
  [ -n "$desc" ] || { echo "usage: find \"<task description>\" [max]" >&2; return 64; }
  printf '%s' "$max" | grep -qE '^[1-9][0-9]*$' || { echo "max must be a positive integer" >&2; return 64; }
  local kws; kws="$(_keywords "$desc")"
  [ -n "$kws" ] || { echo "(no searchable keywords in the description)"; return 0; }

  {
    # repo surfaces: one line per file per keyword hit
    local dir kw
    for dir in docs/specs docs/decisions docs/retro docs/verification; do
      [ -d "$ROOT/$dir" ] || continue
      while IFS= read -r kw; do
        grep -rlis -- "$kw" "$ROOT/$dir" 2>/dev/null || true
      done <<< "$kws"
    done
    # run-ledger reasons (the operational memory)
    if [ -d "$LOG_DIR/runs" ]; then
      while IFS= read -r kw; do
        grep -lis -- "$kw" "$LOG_DIR/runs/"*.log 2>/dev/null || true
      done <<< "$kws"
    fi
  } | sort | uniq -c | sort -rn | head -"$max" | while read -r hits file; do
    # one headline line per match: the file + its first heading or START line
    local head1
    head1="$(grep -m1 -E '^# |^\| START' "$file" 2>/dev/null | head -c 100 || true)"
    printf '%2dx  %s\n      %s\n' "$hits" "${file#"$ROOT"/}" "${head1:-"(no heading)"}"
  done
  return 0
}

# _inventory_find: dispatch to inventory.py. records_file (7th arg, optional) is a rendered
# records-surface text block; when given, inventory.py folds it into the digest and the
# summary line (the `all` surface's own call shape).
_inventory_find() {
  local words="$1" limit="$2" quiet="$3" json="$4" registry="$5" explain="$6" records_file="${7:-}"
  local py="$SELF_DIR/inventory.py"

  local -a args=(--root "$ROOT" --kit "$KIT_ROOT" --limit "$limit")
  [ "$quiet" -eq 1 ] && args+=(--quiet)
  [ "$json" -eq 1 ] && args+=(--json)
  [ -n "$registry" ] && args+=(--registry "$registry")
  [ -n "$explain" ] && args+=(--explain "$explain")
  [ -n "$records_file" ] && args+=(--records-file "$records_file")
  args+=(-- "$words")
  python3 "$py" "${args[@]}"
}

_explain() {
  local label="$1" registry="$2"
  local -a args=(--root "$ROOT" --kit "$KIT_ROOT" --explain "$label")
  [ -n "$registry" ] && args+=(--registry "$registry")
  python3 "$SELF_DIR/inventory.py" "${args[@]}"
}

cmd_find() {
  local desc="" max="" surface="all" surface_explicit=0 limit=5 quiet=0 json=0 \
        registry="" repo_root_flag="" explain="" desc_set=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --surface)
        [ $# -ge 2 ] || { echo "precedent find: --surface needs a value" >&2; return 64; }
        surface="$2"; surface_explicit=1; shift 2 ;;
      --limit)
        [ $# -ge 2 ] || { echo "precedent find: --limit needs a value" >&2; return 64; }
        limit="$2"; shift 2 ;;
      --quiet) quiet=1; shift ;;
      --json) json=1; shift ;;
      --registry)
        [ $# -ge 2 ] || { echo "precedent find: --registry needs a value" >&2; return 64; }
        registry="$2"; shift 2 ;;
      --repo-root)
        [ $# -ge 2 ] || { echo "precedent find: --repo-root needs a value" >&2; return 64; }
        repo_root_flag="$2"; shift 2 ;;
      --explain)
        [ $# -ge 2 ] || { echo "precedent find: --explain needs a value" >&2; return 64; }
        explain="$2"; shift 2 ;;
      -h|--help) _usage; return 0 ;;
      --) shift ;;
      -*)
        echo "precedent find: unknown flag '$1'" >&2; return 64 ;;
      *)
        if [ "$desc_set" -eq 0 ]; then desc="$1"; desc_set=1
        elif [ -z "$max" ]; then max="$1"
        else echo "precedent find: unexpected argument '$1'" >&2; return 64
        fi
        shift ;;
    esac
  done

  case "$surface" in
    records|inventory|all) : ;;
    *) echo "precedent find: unknown --surface '$surface' (want records|inventory|all)" >&2; return 64 ;;
  esac
  printf '%s' "$limit" | grep -qE '^[1-9][0-9]*$' \
    || { echo "precedent find: --limit must be a positive integer" >&2; return 64; }

  ROOT="$(_resolve_root "$repo_root_flag")"

  # registry resolution precedence (SPEC-245): --registry flag > PRECEDENT_REGISTRY env >
  # kit_config_get precedent.registry (project .kit.toml at ROOT, else the kit-root default)
  # > inventory.py's own XDG default. Only the third rung is resolved here; the other two
  # already won by the time this runs empty.
  if [ -z "$registry" ] && [ -z "${PRECEDENT_REGISTRY:-}" ]; then
    local cfg_registry
    cfg_registry="$(KIT_PROJECT_ROOT="$ROOT" kit_config_get precedent.registry "")"
    [ -n "$cfg_registry" ] && registry="$cfg_registry"
  fi

  if [ -n "$explain" ]; then
    _explain "$explain" "$registry"
    return $?
  fi

  # A positional [max] is the legacy records-only call shape (SPEC-068 callers): it forces
  # the records surface unless the caller also passed --surface explicitly, and it caps the
  # records list the same way --limit would.
  if [ -n "$max" ]; then
    [ "$surface_explicit" -eq 1 ] || surface="records"
    limit="$max"
  fi

  [ -n "$desc" ] || { echo "usage: find \"<task description>\" [max]" >&2; return 64; }

  case "$surface" in
    records)
      _records_find "$desc" "$limit"
      return $?
      ;;
    inventory)
      _inventory_find "$desc" "$limit" "$quiet" "$json" "$registry" ""
      return $?
      ;;
    all)
      local records_out rc=0
      records_out="$(_records_find "$desc" "$limit")" && rc=0 || rc=$?
      [ "$rc" -eq 0 ] || return "$rc"

      # render the records block to a temp file, hand it to inventory.py so ONE run
      # prints the records block, the inventory sections, and one combined summary line.
      local tmp_records=""
      tmp_records="$(mktemp "${TMPDIR:-/tmp}/precedent-records.XXXXXX")"
      printf '%s\n' "$records_out" > "$tmp_records"
      local irc=0
      _inventory_find "$desc" "$limit" "$quiet" "$json" "$registry" "" "$tmp_records" || irc=$?
      # `local` dies with this function, so a RETURN/EXIT trap set here cannot see it by
      # the time it fires (tried, hit `set -u` "unbound variable" at process exit);
      # cleaning up right here, once, is simpler and just as reliable.
      rm -f "$tmp_records"
      return "$irc"
      ;;
  esac
}

main() {
  local sub="${1:-}"
  case "$sub" in
    -h|--help|help) _usage; return 0 ;;
    find) shift; cmd_find "$@" ;;
    *)
      echo "usage: precedent.sh find \"<task description>\" [--surface records|inventory|all] [--limit N] [--quiet] [--json] [--registry <file>] [--repo-root <path>] [--explain <label>]" >&2
      return 64 ;;
  esac
}

main "$@"

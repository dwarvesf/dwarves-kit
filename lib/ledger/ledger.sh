#!/usr/bin/env bash
# ledger.sh -- the kit's ONE append substrate (SPEC-182, kit-modularity SG-02).
#
# WHY: row-append + root-location used to be re-implemented in gate-ledger.sh,
# proof-ledger.sh, and any other harness-internal writer. This is the single place both
# live. The append-only ledger is the WRITE plane -- the source of truth; `stats` (the read
# plane) is a stateless projection over it and persists nothing.
#
# Root resolution is delegated to lib/telemetry/kit-log-dir.sh (the ONE resolver): the
# precedence is $KIT_LEDGER_DIR (canonical) -> $DWARVES_KIT_LOG_DIR (back-compat) -> XDG
# default; a set-but-empty $KIT_LEDGER_DIR is a clean fatal error. Every stream lives under
# that single root; a <stream> is a root-relative path (`runs/<rid>.log`, `proof-overrides.log`).
#
# Two use modes:
#   - sourced   : `source lib/ledger/ledger.sh` then call `ledger_append`/`ledger_read`/`ledger_root`.
#   - standalone: `ledger append <stream> <text...>` / `ledger read <stream>` / `ledger root`.
#
# Contract (all safe under set -euo pipefail):
#   ledger_root                      -> print the resolved ledger root (fatal if unresolvable)
#   ledger_append <stream> <text...> -> append ONE line to <root>/<stream> (newlines collapsed)
#   ledger_read   <stream>           -> print <root>/<stream> (honest-empty if absent)
#
# Idempotent-source guard: sourcing twice is a no-op.
[ -n "${_KIT_LEDGER_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_LEDGER_SOURCED=1

# Resolve LIB_ROOT from this script's own location (the anti-alias mechanism, SG-01): this
# file is lib/ledger/ledger.sh, so LIB_ROOT is its parent's parent.
_LEDGER_SELF="${BASH_SOURCE[0]}"
LIB_ROOT="$(cd "$(dirname "$_LEDGER_SELF")/.." && pwd)"
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }

# One line per append: collapse newlines/carriage-returns to spaces so a multi-line or
# injected value can never forge extra ledger lines (mirrors gate-ledger.sh's oneline()).
_ledger_oneline() { printf '%s' "${*:-}" | tr '\n\r' '  '; }

ledger_root() {
  # kit_migrate_log_dir is a one-time additive migration out of the ~/.claude reinstall blast
  # zone; it no-ops when an explicit root is set (a test's mktemp), so it is safe to call here.
  kit_migrate_log_dir || true
  local root
  root="$(kit_resolve_log_dir)" || return 1
  printf '%s' "$root"
}

# ledger_append <stream> <text...>
ledger_append() {
  local stream="${1:-}"; shift || true
  [ -n "$stream" ] || { echo "ledger append: usage: ledger append <stream> <text...>" >&2; return 64; }
  local root; root="$(ledger_root)" || return 1
  local file="$root/$stream"
  mkdir -p "$(dirname "$file")" || { echo "ledger append: cannot create $(dirname "$file")" >&2; return 1; }
  printf '%s\n' "$(_ledger_oneline "$@")" >> "$file"
}

# ledger_read <stream>  -- honest-empty if the stream does not exist yet.
ledger_read() {
  local stream="${1:-}"
  [ -n "$stream" ] || { echo "ledger read: usage: ledger read <stream>" >&2; return 64; }
  local root; root="$(ledger_root)" || return 1
  local file="$root/$stream"
  [ -f "$file" ] || return 0
  cat "$file"
}

# Standalone CLI dispatch: only when executed directly, never when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    append) ledger_append "$@" ;;
    read)   ledger_read "$@" ;;
    root)   ledger_root && echo ;;
    ""|-h|--help|help)
      cat >&2 <<'USAGE'
ledger -- the kit append substrate (write plane, source of truth)
  ledger append <stream> <text...>   append one line to <root>/<stream>
  ledger read   <stream>             print <root>/<stream> (empty if absent)
  ledger root                        print the resolved ledger root
Root: $KIT_LEDGER_DIR > $DWARVES_KIT_LOG_DIR > XDG state default.
USAGE
      [ -z "$cmd" ] && exit 64 || exit 0 ;;
    *) echo "ledger: unknown subcommand '$cmd' (append|read|root)" >&2; exit 64 ;;
  esac
fi

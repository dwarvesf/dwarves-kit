#!/usr/bin/env bash
# front-door-advisory.sh -- ADVISORY skill front-door gate.
#
# A skill may declare `metadata.front_door` (the API, MCP or CLI source it drives). When a push changes
# one of those paths and the same skill's folder did not change, the skill has probably drifted from
# the code it documents. `skill-manifest check <repo> --base <ref>` already knows this rule (class
# `front-door`); this script runs it at push time and prints a warning. It is ADVISORY by hard
# contract: it ALWAYS exits 0 and can never block a push.
#
# Silent (prints nothing) when: the repo has no `skills/*/SKILL.md` declaring `front_door`, the
# `skill-manifest` binary is missing (SKILL_MANIFEST_BIN, else PATH), the base cannot be resolved, or
# the check passes. Only the diff rule is surfaced ("front door of <skill> changed since <ref> but
# <dir>/ did not"); every other problem class belongs to other checks.
#
# Usage:
#   front-door-advisory.sh check <root> [base]   -> one `[front-door]` line per drifted path; ALWAYS exit 0
#
# REUSE: the base resolver is ship-rules.sh:ship_rules_merge_base (merge base with the default branch).
set -uo pipefail

FD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

_resolve_bin() {
  local bin="${SKILL_MANIFEST_BIN:-}"
  if [ -n "$bin" ]; then [ -x "$bin" ] && printf '%s' "$bin"; return 0; fi
  command -v skill-manifest 2>/dev/null || true
}

check() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] || { echo "usage: front-door-advisory.sh check <root> [base]" >&2; return 64; }
  root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || return 0

  grep -qs '^[[:space:]]*front_door:' "$root"/skills/*/SKILL.md || return 0
  local bin; bin="$(_resolve_bin)"
  [ -n "$bin" ] || return 0

  if [ -z "$base" ]; then
    # shellcheck source=lib/gate/ship-rules.sh
    source "$FD_DIR/ship-rules.sh" 2>/dev/null || return 0
    base="$(ship_rules_merge_base "$root" HEAD)"
  fi
  [ -n "$base" ] || return 0

  local out line
  out="$("$bin" check "$root" --base "$base" 2>&1 >/dev/null)" || true
  while IFS= read -r line; do
    case "$line" in
      "check: "*"[front-door] front door of "*" changed since "*)
        line="${line#check: }"
        echo "[front-door] ${line%%: \[front-door\]*}: ${line#*\[front-door\] } (advisory; update the skill or confirm it still matches)"
        ;;
    esac
  done <<EOF
$out
EOF
  return 0
}

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    check) check "$@"; return 0 ;;
    *) echo "usage: front-door-advisory.sh check <root> [base]" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi

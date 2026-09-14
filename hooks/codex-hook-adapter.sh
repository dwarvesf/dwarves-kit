#!/usr/bin/env bash
# Normalize Codex hook input before invoking shared dwarves-kit policies.
# shellcheck disable=SC2016,SC2088

set -uo pipefail

EVENT="${1:-}"
POLICY_NAME="${2:-}"
ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

case "$EVENT:$POLICY_NAME" in
  PreToolUse:safety-gate.sh|PreToolUse:secrets-guard.sh|PreToolUse:ship-gate.sh|PreToolUse:commit-format.sh|Stop:anti-rationalization.sh) ;;
  *)
    printf 'dwarves-kit: unsupported Codex hook adapter target\n' >&2
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf 'dwarves-kit: jq is required for the %s guardrail\n' "$POLICY_NAME" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || {
  printf 'dwarves-kit: could not read Codex hook input\n' >&2
  exit 2
}

if ! printf '%s' "$INPUT" | jq -e --arg event "$EVENT" '
  type == "object" and
  .hook_event_name == $event and
  if $event == "PreToolUse" then
    (.tool_name | type == "string") and
    (.tool_input | type == "object") and
    (.tool_input.command | type == "string")
  else
    (.stop_hook_active | type == "boolean") and
    ((.last_assistant_message == null) or (.last_assistant_message | type == "string"))
  end
' >/dev/null 2>&1; then
  printf 'dwarves-kit: invalid Codex hook input\n' >&2
  exit 2
fi

POLICY="$ROOT/hooks/$POLICY_NAME"
if [ ! -x "$POLICY" ]; then
  printf 'dwarves-kit: required policy is unavailable\n' >&2
  exit 2
fi

export CLAUDE_PLUGIN_ROOT="$ROOT"

LAST_REASON=""

blocked() {
  if [ -n "$LAST_REASON" ]; then
    printf '%s\n' "$LAST_REASON" >&2
  else
    printf 'dwarves-kit: %s blocked this operation\n' "${POLICY_NAME%.sh}" >&2
  fi
  exit 2
}

run_policy() {
  local payload="$1" rc=0 output="" reason=""
  output=$(printf '%s' "$payload" | bash "$POLICY" 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] && return 0
  reason=$(printf '%s' "$output" | jq -r 'select(type == "object" and .decision == "block") | .reason // empty' 2>/dev/null || true)
  if [ -n "$reason" ]; then
    LAST_REASON=$(printf '%s' "$reason" | sed -E 's/(ghp_|sk-|xox[a-z]-)[A-Za-z0-9_-]{8,}/\1[redacted]/g; s/AKIA[A-Z0-9]{16}/AKIA[redacted]/g; s/[A-Fa-f0-9]{32,}/[redacted]/g')
  fi
  return 2
}

if [ "$EVENT" = "Stop" ]; then
  NORMALIZED=$(printf '%s' "$INPUT" | jq -ce '.assistant_response = (.assistant_response // .last_assistant_message // "")') || {
    printf 'dwarves-kit: could not normalize Codex Stop input\n' >&2
    exit 2
  }
  run_policy "$NORMALIZED" || blocked
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

if [ "$POLICY_NAME" != "secrets-guard.sh" ]; then
  run_policy "$INPUT" || blocked
  exit 0
fi

# Preserve the shared Bash detector, then submit every path-like token to the
# shared path policy. The adapter owns runtime parsing, not secret classification.
if [ "$TOOL_NAME" = "Bash" ]; then
  run_policy "$INPUT" || blocked
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
  CD_BASE=$(printf '%s\n' "$COMMAND" | sed -nE 's/(^|.*[;&|][[:space:]]*)cd[[:space:]]+([^;&|[:space:]]+).*/\2/p' | head -1)
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    case "$candidate" in cd|cat|less|more|head|tail|xxd|strings|od|tac|nl|base64|cp|\&\&|\|\||\||';'|-*) continue ;; esac
    if [ -n "$CD_BASE" ]; then
      case "$candidate" in /*|'~/'*|'$HOME/'*|'${HOME}/'*) ;; *) candidate="$CD_BASE/$candidate" ;; esac
    else
      case "$candidate" in */*|.*) ;; *) continue ;; esac
    fi
    PATH_PAYLOAD=$(jq -cn --arg path "$candidate" '{tool_name:"Read",tool_input:{file_path:$path}}')
    run_policy "$PATH_PAYLOAD" || blocked
  done < <(printf '%s\n' "$COMMAND" | tr '[:space:]' '\n' | tr -d '"'"'"'`' | sed -E 's/^[()<>{},;]+//; s/[()<>{},;]+$//')
  exit 0
fi

if [ "$TOOL_NAME" = "apply_patch" ]; then
  PATCH=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    PATH_PAYLOAD=$(jq -cn --arg path "$candidate" '{tool_name:"Edit",tool_input:{file_path:$path}}')
    run_policy "$PATH_PAYLOAD" || blocked
  done < <(printf '%s\n' "$PATCH" | tr -d '\r' | sed -nE 's/^\*\*\* ((Add|Update|Delete) File|Move (to|from)): (.*)$/\4/p')
  exit 0
fi

run_policy "$INPUT" || blocked
exit 0

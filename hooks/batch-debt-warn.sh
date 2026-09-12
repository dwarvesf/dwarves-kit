#!/bin/bash
# batch-debt-warn.sh, PreToolUse hook, matcher: Bash
# Warn when a session merges a second PR and the gate ledger recorded no lane
# START inside that window: a batch-shaped session whose understanding debt
# nothing captured. Advisory only, never blocks, every path exits 0.
# Source: ops-toolkit session-closer-hook.sh (learning-router warn), which fires
# only on research/ or learning/ file adds and so misses a pure-dev batch.
set -uo pipefail
INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
# Merge verb must head a segment of the FIRST line, so prose and heredoc bodies never engage.
printf '%s' "$CMD" | head -n 1 | tr ';&|' '\n' \
  | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
case "$SID" in ''|*[!A-Za-z0-9_-]*) SID=default ;; esac   # a payload id must never traverse the path
LEDGER="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/ledger/ledger.sh"
[ -r "$LEDGER" ] || exit 0
# shellcheck source=lib/ledger/ledger.sh
source "$LEDGER" 2>/dev/null || exit 0
ROOT=$(ledger_root 2>/dev/null) || exit 0
STREAM="merge-watch/$SID.log"
ledger_append "$STREAM" "$(date -u +%Y-%m-%dT%H:%M:%SZ) | MERGE" 2>/dev/null || exit 0

FILE="$ROOT/$STREAM"
grep -q '| WARNED' "$FILE" 2>/dev/null && exit 0                      # one warn per session
[ "$(grep -c '| MERGE' "$FILE" 2>/dev/null || echo 0)" -ge 2 ] || exit 0
SINCE=$(head -n 1 "$FILE" | awk -F' \\| ' '{print $1}')                # the batch window opens at merge #1
# A gated batch starts a lane between merges; an ungated one writes nothing at all.
STARTED=$(grep -h '| START' "$ROOT"/runs/*.log 2>/dev/null | awk -F' \\| ' -v s="$SINCE" '$1 > s' | head -n 1)
[ -n "$STARTED" ] && exit 0

ledger_append "$STREAM" "$(date -u +%Y-%m-%dT%H:%M:%SZ) | WARNED" 2>/dev/null || true
jq -n --arg ctx "📚 **Batch-debt warning**: this session has merged 2+ PRs with no lane START in the gate ledger since the first merge, so the batch is closing with its understanding debt unrecorded. Fix in one line: \`gate-ledger.sh start <rid> <lane> <lane> <type>\` then \`gate-ledger.sh debt <rid> significance=high worthiness=high verdict=tap response=defer\`. A batch with nothing to absorb can dismiss this." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
exit 0

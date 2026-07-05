#!/usr/bin/env bash
# transcript.sh: read a Claude Code transcript JSONL and emit the last K user+assistant turns as
# compact "[role] text" blocks. bash + jq only; does NOT import cc-harvest's Python (cross-language).
#
# Per-line schema (locked against a real sample in tests/fixtures/sample-transcript.jsonl,
# TASK-002): each line is one JSON object. The lines we want have:
#   .type        == "user" | "assistant"
#   .message.role  (preferred role label; falls back to .type)
#   .message.content[]  array of blocks; text blocks are {type:"text", text:"..."}
# Other line types (summary, system, tool_use/tool_result-only, thinking) are skipped: we only
# feed natural-language turns to the reviewer, which keeps the prompt cheap and on-signal.

# transcript_compact <path> [k]: stdout = last k turns as "[role] text" joined by blank lines.
# Empty output (no path / unreadable / no text turns) is a valid "nothing to review" signal.
transcript_compact() {
  local path="$1" k="${2:-40}"
  [ -n "$path" ] && [ -f "$path" ] || return 0
  # Pass 1: one compact JSON per qualifying turn {role,text}, dropping empty-text turns.
  # Pass 2: keep the last k, render as "[role] text".
  jq -c '
    select((.type=="user" or .type=="assistant") and (.message != null))
    | { role: (.message.role // .type),
        text: ([ (.message.content // [])[]? | select(.type=="text") | .text ] | join("\n")) }
    | select(.text | (. != null and (gsub("\\s";"") | length) > 0))
  ' "$path" 2>/dev/null \
  | tail -n "$k" \
  | jq -rs 'map("[\(.role)] \(.text)") | join("\n\n")' 2>/dev/null
}

# Allow `bash lib/transcript.sh <path> [k]` for manual inspection / the fixture test.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  transcript_compact "${1:-}" "${2:-40}"
fi

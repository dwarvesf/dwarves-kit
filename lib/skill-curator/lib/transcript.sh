#!/usr/bin/env bash
# transcript.sh: read a Claude Code transcript JSONL and emit the last K user+assistant turns as
# compact "[role] text" blocks. The parse lives in the kit's one transcript parser,
# lib/session/parse_transcript.py (--tail-text); this file is only the bash entry point.
#
# Per-line schema (locked against a real sample in tests/fixtures/sample-transcript.jsonl):
# each line is one JSON object. The lines we want have:
#   .type        == "user" | "assistant"
#   .message.role  (preferred role label; falls back to .type)
#   .message.content[]  array of blocks; text blocks are {type:"text", text:"..."}
# Other line types (summary, system, tool_use/tool_result-only, thinking) are skipped: we only
# feed natural-language turns to the reviewer, which keeps the prompt cheap and on-signal.

_TRANSCRIPT_PARSER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../session" && pwd)/parse_transcript.py"

# transcript_compact <path> [k]: stdout = last k turns as "[role] text" joined by blank lines.
# Empty output (no path / unreadable / no text turns) is a valid "nothing to review" signal.
transcript_compact() {
  local path="$1" k="${2:-40}"
  [ -n "$path" ] && [ -f "$path" ] || return 0
  python3 "$_TRANSCRIPT_PARSER" --tail-text "$k" "$path" 2>/dev/null
}

# Allow `bash lib/transcript.sh <path> [k]` for manual inspection / the fixture test.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  transcript_compact "${1:-}" "${2:-40}"
fi

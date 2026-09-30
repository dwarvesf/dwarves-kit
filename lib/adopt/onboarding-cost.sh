#!/usr/bin/env bash
# onboarding-cost.sh <transcript.jsonl> -- print turns, tokens and whether the agent read the
# full kit contract. Reads two transcript shapes:
#   omp:         turn_start events, assistant message_end usage.totalTokens, toolCall with
#                arguments.path
#   Claude Code: assistant messages (deduped by message id), usage token fields, tool_use
#                named Read/WebFetch with input.file_path / input.url
# "contract read: yes" means a read-type call whose target is an AGENTS.md path or URL. The
# targets are listed so a human can tell the installed contract from a repo-local file.
set -uo pipefail

f="${1:-}"
[ -n "$f" ] && [ -f "$f" ] || { echo "usage: onboarding-cost.sh <transcript.jsonl>" >&2; exit 64; }
command -v jq >/dev/null 2>&1 || { echo "onboarding-cost: jq not found" >&2; exit 1; }

jq -rs '
  def uniq_msgs: (map(select(.id != null)) | unique_by(.id)) + map(select(.id == null));
  ([.[] | select(.type == "turn_start")] | length) as $omp_turns
  | ([.[] | select(.type == "assistant") | .message] | uniq_msgs) as $cc
  | ([.[] | select(.type == "message_end" and .message.role == "assistant") | .message.usage.totalTokens // 0] | add // 0) as $omp_tokens
  | ([$cc[] | .usage // {} | (.input_tokens // 0) + (.output_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)] | add // 0) as $cc_tokens
  | ([.. | objects
      | select((.type == "toolCall" or .type == "tool_use") and ((.name // "") | test("^(read|Read|WebFetch|webfetch)$")))
      | (.arguments // .input // {}) | (.path // .file_path // .url // "")
      | select(test("(^|/)AGENTS\\.md([:?#].*)?$"))] | unique) as $targets
  | "turns \(if $omp_turns > 0 then $omp_turns else ($cc | length) end)",
    "tokens \(if $omp_turns > 0 then $omp_tokens else $cc_tokens end)",
    "contract read: \(if ($targets | length) > 0 then "yes" else "no" end)",
    ($targets[] | "contract target: \(.)")
' "$f"

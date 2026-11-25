#!/usr/bin/env bash
# agent-lessons.sh - print the repo lesson index for a coding agent.
# The Claude Code SessionStart hook in .claude/settings.json runs it, and plain stdout from that
# hook becomes context. Any agent can run it by hand.
# The hook output is capped at 10,000 characters, so the index stays under 8,000 and this script
# cuts at a whole line below 9,000 and says so.
# Always exits 0: a missing index must never block a session. bash 3.2 safe.
limit=9000
root="$(cd "$(dirname "$0")/.." && pwd)"
index="$root/.claude/memory/MEMORY.md"

[ -f "$index" ] || exit 0
size="$(wc -c < "$index" | tr -d ' ')"
if [ "$size" -le "$limit" ]; then
  cat "$index"
  exit 0
fi

LC_ALL=C awk -v max="$limit" '{ n += length($0) + 1; if (n > max) exit; print }' "$index"
echo
echo "agent-lessons: the index is $size characters and this output stops below $limit. Read the rest in .claude/memory/MEMORY.md and shorten that file to under 8,000 characters."
exit 0

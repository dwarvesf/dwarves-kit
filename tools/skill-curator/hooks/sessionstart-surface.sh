#!/usr/bin/env bash
# sessionstart-surface.sh: SessionStart hook. Emits a one-line self-improvement-loop status as
# additionalContext (staged-memory count + skill-draft count + 7-day loop spend). Read-only; fast;
# exit 0 always. Never blocks or writes.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/surface.sh
. "$HERE/../lib/surface.sh"

# Honor the enabled switch; if disabled, surface nothing (still valid JSON-less exit 0).
[ "$(cfg enabled true)" = "true" ] || exit 0

line="$(surface_line 2>/dev/null)"
[ -n "$line" ] || exit 0

# SessionStart additionalContext contract: JSON on stdout.
jq -nc --arg c "$line" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}' 2>/dev/null \
  || printf '%s\n' "$line"   # fall back to plain text if jq somehow fails
exit 0

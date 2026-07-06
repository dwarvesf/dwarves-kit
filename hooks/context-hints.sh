#!/usr/bin/env bash
# context-hints.sh, UserPromptSubmit hook, function-named port of ops-toolkit's
# cc-context-hooks (kit-foldin design note, was cc-context-hooks). Thin bash shim so
# settings.json/hooks.json can invoke it uniformly with the rest of hooks/*.sh; the
# actual logic is the co-located context-hints.py (stdlib-only, no deps to vendor).
#
# Coexists with the kit's SessionStart context-readiness.sh, different event,
# different purpose (session-startup state vs. per-prompt hints). Not merged.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/context-hints.py" "$@"

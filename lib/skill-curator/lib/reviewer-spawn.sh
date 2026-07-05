#!/usr/bin/env bash
# Thin detached wrapper run by the hook: review one payload, then remove the temp payload file.
# Kept separate from reviewer-run.sh so the latter stays a pure, testable unit that never deletes
# its own input. Always exits 0.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pf="${1:-}"
bash "$HERE/reviewer-run.sh" "$pf"
[ -n "$pf" ] && rm -f "$pf" 2>/dev/null || true
exit 0

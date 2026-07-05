#!/usr/bin/env bash
# harvest.sh -- PreCompact / SessionEnd hook, function-named port of ops-toolkit's
# cc-harvest (kit-foldin design note, was cc-harvest). Thin bash shim; the actual
# logic is the co-located harvest.py (stdlib-only, no deps to vendor). Modes (no
# args, --lab-log, --cleanup, --stop-trigger) are dispatched inside harvest.py;
# settings.json/hooks.json pass the mode as an argv flag. Always exits 0: a harvest
# never blocks a compaction/session-end/stop.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/harvest.py" "$@" || true
exit 0

#!/usr/bin/env bash
# backlog-stage.sh -- SessionEnd hook, function-named port of ops-toolkit's cc-backlog
# (kit-foldin design note, was cc-backlog). Thin bash shim; the actual logic is the
# co-located backlog-stage.py (stdlib-only, no deps to vendor). Always exits 0: a
# harvest never blocks a session end.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/backlog-stage.py" "$@" || true
exit 0

#!/usr/bin/env bash
# citation-guard.sh -- Stop hook, function-named port of ops-toolkit's cc-citation-guard
# (kit-foldin design note). Thin bash shim; the actual logic is the co-located
# citation-guard.py (stdlib-only, no deps to vendor). Exit code is load-bearing:
# a strict-mode block (exit 2) must pass through untouched, so this uses exec, not a
# wrapped call whose own exit code could shadow the Python process's.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/citation-guard.py" "$@"

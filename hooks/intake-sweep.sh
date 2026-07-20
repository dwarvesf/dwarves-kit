#!/usr/bin/env bash
# intake-sweep.sh -- thin shim over intake-sweep.py (backlog-stage.sh precedent).
# Sweeps a consumer's declared "review later" sources (_meta/intake-sources.json)
# into the backlog staging funnel. Config-gated no-op; always exits 0.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/intake-sweep.py" "$@" || true
exit 0

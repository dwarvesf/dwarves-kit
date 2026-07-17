#!/usr/bin/env bash
# Runs the board-sync python suite (core planner + the three spoke adapters,
# fake transports only, no network). uv supplies pytest; the engine itself is
# stdlib-only.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec uv run --no-project --with pytest -- \
  pytest "$KIT_ROOT/lib/sync/tests" -q

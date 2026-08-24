#!/usr/bin/env bash
# Runs the webcheck python suite (three tiers + the SSRF guards + the WEB_DRIFT_SITES
# resolver). Offline: every fetch is monkeypatched, no network. uv supplies pytest;
# the module itself is stdlib-only.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec uv run --no-project --with pytest -- \
  pytest "$KIT_ROOT/lib/webcheck/tests" -q

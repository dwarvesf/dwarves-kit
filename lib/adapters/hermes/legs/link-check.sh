#!/bin/bash
# link check leg: compare each linked profile's skill stamp with this kit and record it for the brief.
# `board sweep` runs it last, after the health leg, as `"$BASH" <this script>` (lib/adapters/README.md,
# legs). It always runs. Observational: a failure here prints one line and never fails the sweep.
set -u

HERMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"  # physical: the adapter directory may be a symlink
python3 "$HERMES_DIR/link.py" check --record --health-state-file "$SWEEP_HEALTH_STATE" >/dev/null 2>&1 || echo "  hermes link check failed (non-fatal)"
exit 0

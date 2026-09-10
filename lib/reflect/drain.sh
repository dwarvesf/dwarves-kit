#!/usr/bin/env bash
# drain.sh -- bash entry for `learn drain` (SPEC-196), forwards to the Python
# implementation. The staging-file grammar (`## [state] title` blocks + `- Field: value`
# lines, date parsing) is already proven in this exact codebase in Python
# (hooks/backlog-stage.py writes it, lib/board/bin/add-backlog reads it); drain.py/
# staging-format.py reuse that choice rather than reimplementing markdown-block parsing
# in bash/awk. This wrapper exists so `learn.sh`'s dispatch stays uniform with
# weekend-batch.sh (`exec bash "$LEARN_DIR/<verb>.sh" "$@"`).
set -euo pipefail
DRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DRAIN_DIR/drain.py" "$@"

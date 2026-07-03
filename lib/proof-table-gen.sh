#!/usr/bin/env bash
# proof-table-gen.sh -- thin launcher for the proof-of-done confirmation-table
# generator (SPEC-132). Resolves the kit's durable log dir the exact way
# lib/gate-ledger.sh does (sources lib/kit-log-dir.sh, so there is ONE resolver, not
# a second copy), then delegates ledger-parsing + table rendering to the sibling
# Python module -- bash-3.2 (the macOS CI runner's default /bin/bash, the same
# constraint lib/orchestrate.sh already codes around) has no associative arrays,
# which the phase -> outcome lookup needs; Python is the portable fit here, the same
# call lib/handoff-gen already makes for lib/handoff/handoff_gen.py.
#
# Usage: bash lib/proof-table-gen.sh <rid> [out-path]
#   <rid>       a gate-ledger rid (bash lib/gate-ledger.sh rid)
#   [out-path]  default: docs/runs/<rid>.md (a generated path; refuses proof-of-done.md)
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/kit-log-dir.sh
source "$KIT_ROOT/lib/kit-log-dir.sh" || { echo "FATAL: lib/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true

export KIT_ROOT
export KIT_LOG_DIR
KIT_LOG_DIR="$(kit_resolve_log_dir)"

exec python3 "$KIT_ROOT/lib/proof-table-gen.py" "$@"

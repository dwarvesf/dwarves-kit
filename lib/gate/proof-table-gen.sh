#!/usr/bin/env bash
# proof-table-gen.sh -- thin launcher for the proof-of-done confirmation-table
# generator (SPEC-132). Resolves the kit's durable log dir the exact way
# lib/gate/gate-ledger.sh does (sources lib/telemetry/kit-log-dir.sh, so there is ONE resolver, not
# a second copy), then delegates ledger-parsing + table rendering to the sibling
# Python module -- bash-3.2 (the macOS CI runner's default /bin/bash, the same
# constraint lib/queue/orchestrate.sh already codes around) has no associative arrays,
# which the phase -> outcome lookup needs; Python is the portable fit here, the same
# call lib/goal/handoff-gen already makes for lib/goal/handoff/handoff_gen.py.
#
# Usage: bash lib/gate/proof-table-gen.sh <rid> [out-path]
#   <rid>       a gate-ledger rid (bash lib/gate/gate-ledger.sh rid)
#   [out-path]  default: docs/runs/<rid>.md (a generated path; refuses proof-of-done.md)
set -euo pipefail

# SCRIPT_ROOT = where this script + its libs live (always the real repo); used to source
# libs and locate the .py. KIT_ROOT = the LOGICAL kit root the generator confines output
# under (docs/runs) and derives the default out-path from. KIT_ROOT defaults to SCRIPT_ROOT
# but honors a pre-set env override (SPEC-134 test seam), so the SPEC-134 path confinement
# can be exercised against a throwaway docs/runs without polluting the real repo. Libs are
# always sourced from SCRIPT_ROOT, so a fake KIT_ROOT can never break sourcing.
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"  # repo root = two levels above lib/gate/
KIT_ROOT="${KIT_ROOT:-$SCRIPT_ROOT}"
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$SCRIPT_ROOT/lib/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true

export KIT_ROOT
export KIT_LOG_DIR
KIT_LOG_DIR="$(kit_resolve_log_dir)"

exec python3 "$SCRIPT_ROOT/lib/gate/proof-table-gen.py" "$@"

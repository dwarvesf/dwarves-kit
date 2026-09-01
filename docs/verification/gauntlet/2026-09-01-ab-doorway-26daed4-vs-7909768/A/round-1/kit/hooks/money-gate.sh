#!/usr/bin/env bash
# money-gate.sh -- PreToolUse(Edit|Write|MultiEdit) hook, function-named port of
# ops-toolkit's cc-money-gate (kit-foldin). Thin bash shim; the logic is the
# co-located money-gate.py (stdlib-only). Inert unless the consumer sets
# MONEY_GATE_REPOS (the kit ships no tenant repo names); MONEY_GATE_STRICT=1 upgrades
# log-only to an ask-to-confirm decision. Always exits 0: the decision travels in
# the JSON, never the exit code.
set -euo pipefail
[ -n "${MONEY_GATE_REPOS:-}" ] || exit 0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/money-gate.py" "$@" || true
exit 0

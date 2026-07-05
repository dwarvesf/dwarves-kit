#!/usr/bin/env bash
# parse-transcript.sh -- thin launcher for the shared JSONL turn-parser
# (lib/session/parse_transcript.py, kit-foldin SG-03). The parsing logic itself
# is Python (both callers -- session-observe, session-recall -- are Python;
# shelling JSONL parsing out to bash per-line would mean re-implementing
# `json.loads` in bash or a jq subprocess per line, slower and a second
# implementation of the exact routine this file exists to de-duplicate). This
# launcher exists so the parser is invocable and testable as a standalone shell
# unit -- same shape as lib/gate/proof-table-gen.sh's bash-launcher-over-python
# pattern -- without forcing either Python CLI to shell out to it (they `import`
# the sibling .py module directly; see each tool's bin/ for the import shim).
#
# Usage: bash lib/session/parse-transcript.sh <transcript.jsonl>
#   Prints one JSON object per successfully-parsed line to stdout (NDJSON).
#   A malformed line is skipped, never fatal. Missing/unreadable path -> a
#   one-line stderr message + exit 1 (never a raw Python traceback). No arg
#   -> usage + exit 2.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/parse_transcript.py" "$@"

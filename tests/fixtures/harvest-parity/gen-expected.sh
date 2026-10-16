#!/usr/bin/env bash
# gen-expected.sh [rev] -- regenerate expected.jsonl from the Python harvest at a pinned revision, run
# through that revision's own shim, so a Python crash reads the way the shim surfaced it. The bash
# port must reproduce every line; hooks/harvest.py itself is gone from HEAD. The Python loads
# hooks/harvest_sweep.py for its operator and sweep verbs (and that module loads the shared
# transcript parser), so those ride along from the same rev. A crash-* case is one the Python died
# on: the shim swallowed it (`|| true`), so the golden is a silent exit 0 plus whatever the Python
# had already written, which is what the port does too.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-b9306b37}"
# shellcheck source=../../lib/hook-parity.sh
source "$KIT_ROOT/tests/lib/hook-parity.sh"
HP_KIT_ROOT="$KIT_ROOT" HP_EXTRA_FILES="hooks/harvest_sweep.py lib/session/parse_transcript.py lib/config/kit-config.sh" \
  hp_gen_expected "$REV" harvest "$HERE/cases.jsonl" "$HERE/expected.jsonl"
# A Python traceback carries the scratch path of the run, so the golden keeps the crash as a silent exit 0:
# the stderr is blanked, every other field stays as the Python left it. The operator verbs now run in
# hooks/harvest_sweep.py, so a usage line names that script (a recorded rename).
tmp="$(mktemp "${TMPDIR:-/tmp}/harvest-expected.XXXXXX")"
jq -c 'if (.stderr | startswith("Traceback")) then .stderr = "" else . end | .stderr |= sub("usage: harvest\\.py"; "usage: harvest_sweep.py")' "$HERE/expected.jsonl" > "$tmp" && mv -f "$tmp" "$HERE/expected.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"

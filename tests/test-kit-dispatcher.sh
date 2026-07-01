#!/usr/bin/env bash
# test-kit-dispatcher.sh -- SPEC-090 keystone: the `kit` dispatcher resolves the
# current lib/ and dispatches to it, independent of install location/version.
set -euo pipefail

KIT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/bin/kit"
fail=0
check() { # <desc> <actual-exit-already-run>  (call as: run; check "desc" $?)
  if [ "$2" -eq 0 ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# 1. --lib resolves to a real dir containing the known scripts
lib="$("$KIT" --lib)"; rc=$?
check "--lib exits 0" $rc
[ -d "$lib" ] && [ -f "$lib/lane-classify.sh" ]; check "--lib points at a lib/ with lane-classify.sh ($lib)" $?

# 2. dispatch: `kit lane-classify classify ...` returns a non-empty lane
lane="$("$KIT" lane-classify classify "add a config value")"; rc=$?
check "dispatch lane-classify exits 0" $rc
[ -n "$lane" ]; check "dispatch returns a non-empty lane ('$lane')" $?

# 3. unknown script fails cleanly (non-zero, no exec)
if "$KIT" no-such-script-xyz >/dev/null 2>&1; then bad=0; else bad=1; fi
[ "$bad" -eq 1 ]; check "unknown script exits non-zero" $?

# 4. --help prints usage
"$KIT" --help 2>/dev/null | grep -q 'kit <script>'; check "--help prints usage" $?

if [ "$fail" -eq 0 ]; then echo "PASS: kit dispatcher"; else echo "SOME TESTS FAILED"; exit 1; fi

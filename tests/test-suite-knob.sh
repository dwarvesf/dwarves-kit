#!/usr/bin/env bash
# test-suite-knob.sh -- the [test] suite knob: default, override, and the dev-loop docs that read it.
set -u
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" -eq 0 ]; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }
has() { grep -qF -- "$2" "$KIT_DIR/$1"; echo $?; }

T="$(mktemp -d "${TMPDIR:-/tmp}/suite-knob.XXXXXX")"
trap 'mv -f "$T" "$T.done"' EXIT
source "$KIT_DIR/lib/config/kit-config.sh"
export KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$T/op" KIT_PROJECT_ROOT="$T/proj"
mkdir -p "$T/op" "$T/proj"

echo "=== test.suite resolves ==="
assert "default is full" "$([ "$(kit_config_get test.suite)" = full ] && echo 0 || echo 1)"
printf '[test]\nsuite = "affected"\n' > "$T/proj/.kit.toml"
assert "a project .kit.toml can set affected" "$([ "$(kit_config_get test.suite)" = affected ] && echo 0 || echo 1)"

echo "=== dev-loop docs read the knob ==="
assert "execute.md Full suite step reads test.suite" "$(has commands/execute.md 'kit_config_get test.suite full')"
assert "execute.md names bin/test-affected" "$(has commands/execute.md 'bin/test-affected')"
assert "execute.md negative control stays narrow" "$(has commands/execute.md 'never the whole suite')"
assert "verify.md skips system-verifier under affected" "$(has commands/verify.md 'SKIPPED: full suite runs on the schedule (test.suite=affected)')"
assert "ship.md narrows tests under affected" "$(has commands/ship.md 'kit_config_get test.suite full')"

echo ""
echo "=== $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

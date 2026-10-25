#!/usr/bin/env bash
# test-gauntlet-remote-key.sh -- run-remote.sh with a remote runner_host refuses to start
# (exit 65, before any ssh) while gauntlet.probe_key_ref is empty or a placeholder, and
# gets past that guard once the operator file sets a ref. The shipped kit.toml leaves the
# ref empty. Hermetic: ssh is a stub on PATH; no network, no 1P.
# Run: bash tests/test-gauntlet-remote-key.sh
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
assert_true() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
mkdir -p "$T/bin"
printf '#!/bin/bash\necho "$@" >> "%s/ssh.log"\ncat >/dev/null\nexit 99\n' "$T" > "$T/bin/ssh"
chmod +x "$T/bin/ssh"

echo "== shipped default is empty =="
SHIPPED="$(grep -E '^probe_key_ref' "$KIT_DIR/kit.toml" | sed -E 's/^probe_key_ref[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
assert_true "kit.toml ships an empty probe_key_ref" "$([ -z "$SHIPPED" ]; echo $?)"

run_remote() { # $1 = operator config DIR (holds kit.toml); kit-root is the checkout's shipped kit.toml
  PATH="$T/bin:$PATH" GAUNTLET_RUNNER_HOST=fake-host KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$1" \
    bash "$KIT_DIR/tests/gauntlet/cleanroom/run-remote.sh" user doorway "$T/out" 2>&1
}

echo "== empty ref: exit 65, clear error, no ssh =="
: > "$T/ssh.log"
OUT="$(run_remote "$T/none")"; RC=$?
assert_true "exits 65" "$([ "$RC" -eq 65 ]; echo $?)"
assert_true "error names probe_key_ref" "$(printf '%s' "$OUT" | grep -q 'gauntlet.probe_key_ref is unset'; echo $?)"
assert_true "ssh never called" "$([ ! -s "$T/ssh.log" ]; echo $?)"

echo "== placeholder ref: exit 65 =="
mkdir -p "$T/ph" "$T/real"
printf '[gauntlet]\nprobe_key_ref = "op://<vault>/<item>/credential"\n' > "$T/ph/kit.toml"
run_remote "$T/ph" >/dev/null; RC=$?
assert_true "placeholder exits 65" "$([ "$RC" -eq 65 ]; echo $?)"

echo "== real ref: passes the guard (reaches ssh) =="
printf '[gauntlet]\nprobe_key_ref = "op://example-vault/example-item/credential"\n' > "$T/real/kit.toml"
: > "$T/ssh.log"
run_remote "$T/real" >/dev/null; RC=$?
assert_true "does not exit 65" "$([ "$RC" -ne 65 ]; echo $?)"
assert_true "ssh reached" "$([ -s "$T/ssh.log" ]; echo $?)"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

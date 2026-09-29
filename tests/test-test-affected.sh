#!/usr/bin/env bash
# test-test-affected.sh -- bin/test-affected in a throwaway git repo: the selection mapping,
# the always-meta rule, UNCOVERED, the pass cache (hit, miss after a source edit, FAIL never
# cached, --no-cache, unusable cache fails closed).
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TA="$KIT_DIR/bin/test-affected"
PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
has() { grep -qF -- "$2" <<<"$1" && ok "$3" || { bad "$3 (missing '$2' in: $1)"; }; }
hasnt() { grep -qF -- "$2" <<<"$1" && bad "$3 (unexpected '$2' in: $1)" || ok "$3"; }

W="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$W/logs" TA_MARK="$W/mark"
unset KIT_LEDGER_DIR
trap 'chmod -R u+rwx "$W" 2>/dev/null; rm -rf "$W"' EXIT
R="$W/repo"; mkdir -p "$R/tests" "$R/lib/x" "$R/lib/y" "$R/docs"; cd "$R"
git init -q -b main . && git config user.email t@t && git config user.name t
echo 1.0.0 > VERSION
printf 'echo ok-a\n' > lib/x/a.sh
printf 'echo ok-b\n' > lib/x/b.sh
printf 'exit 0\n'    > lib/x/f.sh
printf 'echo orphan\n' > lib/y/orphan.sh
printf '#!/bin/bash\necho run-meta >> "$TA_MARK"\nexit 0\n'                  > tests/test-meta.sh
printf '#!/bin/bash\necho run-a >> "$TA_MARK"\nbash lib/x/a.sh\n'            > tests/test-a.sh
printf '#!/bin/bash\necho run-b >> "$TA_MARK"\nbash lib/x/b.sh\n'            > tests/test-b.sh
printf '#!/bin/bash\necho run-f >> "$TA_MARK"\nbash lib/x/f.sh\n'            > tests/test-f.sh
git add -A && git commit -qm init
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b work

echo "== nothing changed =="
out="$(bash "$TA" 2>&1)"; has "$out" "no changes" "clean tree selects nothing"

echo "== mapping (--list, default base origin/main, uncommitted change) =="
echo "# edit" >> lib/x/a.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-a.sh  (references lib/x/a.sh)" "changed lib file maps to the test naming it"
hasnt "$out" "tests/test-b.sh" "unrelated test not selected"
has   "$out" "tests/test-meta.sh  (always)" "test-meta always selected when anything changed"
[ ! -e "$TA_MARK" ] && ok "--list runs nothing" || bad "--list ran a test"

echo "== changed test maps to itself; UNCOVERED is not a failure =="
echo "# edit" >> tests/test-b.sh
echo "# edit" >> lib/y/orphan.sh
out="$(bash "$TA" --list 2>&1)"
has "$out" "tests/test-b.sh  (self)" "changed test file maps to itself"
has "$out" "UNCOVERED lib/y/orphan.sh" "file no test names is UNCOVERED"
out="$(bash "$TA" 2>&1)"; rc=$?
has "$out" "UNCOVERED lib/y/orphan.sh" "UNCOVERED shown on a real run"
[ "$rc" = 0 ] && ok "UNCOVERED does not fail the run" || bad "rc=$rc with only UNCOVERED"
git checkout -q -- lib/y/orphan.sh tests/test-b.sh

echo "== cache: hit on second run, miss after editing a referenced source =="
rm -rf "$W/logs"
out="$(bash "$TA" 2>&1)"
has "$out" "PASS tests/test-a.sh" "first run executes"
out="$(bash "$TA" 2>&1)"
has   "$out" "CACHED tests/test-a.sh" "second run is a cache hit"
has   "$out" "CACHED tests/test-meta.sh" "meta is cached too"
echo "# edit2" >> lib/x/a.sh
out="$(bash "$TA" 2>&1)"
has   "$out" "PASS tests/test-a.sh" "edited referenced source misses the cache"
hasnt "$out" "CACHED tests/test-a.sh" "no stale CACHED after the edit"

echo "== --no-cache =="
out="$(bash "$TA" --no-cache 2>&1)"
has   "$out" "PASS tests/test-a.sh" "--no-cache re-runs a cached test"
hasnt "$out" "CACHED" "--no-cache never prints CACHED"

echo "== FAIL is never cached =="
git checkout -q -- lib/x/a.sh
printf 'exit 1\n' > lib/x/f.sh
out="$(bash "$TA" 2>&1)"; rc=$?
has "$out" "FAIL tests/test-f.sh" "failing test reports FAIL"
[ "$rc" != 0 ] && ok "non-zero exit on FAIL" || bad "exit 0 despite FAIL"
out="$(bash "$TA" 2>&1)"
has   "$out" "FAIL tests/test-f.sh" "second run FAILs again"
hasnt "$out" "CACHED tests/test-f.sh" "FAIL was not cached"

echo "== unusable cache fails closed =="
git checkout -q -- lib/x/f.sh
echo "# edit3" >> lib/x/a.sh
bash "$TA" >/dev/null 2>&1
chmod 000 "$W/logs/test-cache"
out="$(bash "$TA" 2>&1)"; rc=$?
chmod 755 "$W/logs/test-cache"
has   "$out" "PASS tests/test-a.sh" "unreadable cache runs the test"
hasnt "$out" "CACHED" "unreadable cache skips nothing"

echo ""; echo "test-test-affected: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

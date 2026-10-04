#!/usr/bin/env bash
# test-test-affected.sh -- bin/test-affected in a throwaway git repo: the selection mapping,
# the test-meta input rule, UNCOVERED, the pass cache (hit, miss after a source edit, FAIL never
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
printf 'echo readme\n' > README.md; printf 'echo dr\n' > docs/README.md
printf 'echo ab\n' > lib/x/ab.sh; printf 'echo long\n' > lib/x/longname.sh
printf '#!/bin/bash\ngrep -q readme README.md\n'      > tests/test-readme.sh
printf '#!/bin/bash\ngrep -q dr docs/README.md\n'     > tests/test-docsreadme.sh
printf '#!/bin/bash\necho ab.sh\n' > tests/test-short.sh
printf '#!/bin/bash\necho longname.sh\n'               > tests/test-long.sh
mkdir -p lib/mod; printf 'echo m\n' > lib/mod/mm.sh
printf '#!/bin/bash\nexit 0\n' > tests/test-mod-thing.sh
printf '#!/bin/bash\n# lib/x/b.sh appears only in this comment\nexit 0\n' > tests/test-cmt.sh
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
hasnt "$out" "tests/test-meta.sh" "test-meta not picked by a change to a path it does not read"
[ ! -e "$TA_MARK" ] && ok "--list runs nothing" || bad "--list ran a test"

echo "== narrowed selection =="
git stash -q -u
echo "# edit" >> README.md
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-readme.sh  (references README.md)" "root README.md selects a suite naming the path README.md"
hasnt "$out" "tests/test-docsreadme.sh" "a suite naming only docs/README.md is not selected by README.md"
git checkout -q -- README.md
echo "# edit" >> lib/x/ab.sh
out="$(bash "$TA" --list 2>&1)"
hasnt "$out" "tests/test-short.sh" "5-char basename (ab.sh) alone does not select"
has   "$out" "UNCOVERED lib/x/ab.sh" "short-basename source with no path reference is UNCOVERED"
git checkout -q -- lib/x/ab.sh
echo "# edit" >> lib/x/longname.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-long.sh  (references lib/x/longname.sh)" "long basename still selects by basename"
git checkout -q -- lib/x/longname.sh
echo "# edit" >> lib/mod/mm.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-mod-thing.sh  (module lib/mod)" "lib/<mod>/ change picks tests/test-<mod>*.sh"
hasnt "$out" "UNCOVERED lib/mod/mm.sh" "a module-picked file is not UNCOVERED"
git checkout -q -- lib/mod/mm.sh
echo "# edit" >> lib/x/b.sh
out="$(bash "$TA" --list 2>&1)"
hasnt "$out" "tests/test-cmt.sh" "a comment-only mention does not select"
has   "$out" "tests/test-b.sh  (references lib/x/b.sh)" "a code mention still selects"
git checkout -q -- lib/x/b.sh
git stash pop -q 2>/dev/null || true

echo "== test-meta: picked only by a path it reads =="
# It used to ride every diff (~200s of a 253s run). A lib/wrap + test-wrap diff is not one of
# its inputs; commands/, docs/FEATURES.md and a `# kit-verb:` lib file are.
git stash -q -u
mkdir -p lib/wrap commands docs lib/z
printf 'echo w\n' > lib/wrap/wrap.sh; printf '#!/bin/bash\nbash lib/wrap/wrap.sh\n' > tests/test-wrap-x.sh
printf -- '---\nname: c\n---\n' > commands/c.md; printf '# F\n' > docs/FEATURES.md
printf '#!/bin/bash\n# kit-verb: zz | a verb\necho z\n' > lib/z/verb.sh
git add -A && git commit -qm meta-fixtures && git update-ref refs/remotes/origin/main HEAD
echo "# edit" >> lib/wrap/wrap.sh; echo "# edit" >> tests/test-wrap-x.sh
out="$(bash "$TA" --list 2>&1)"
hasnt "$out" "tests/test-meta.sh" "lib/wrap/*.sh + tests/test-wrap*.sh diff does not pick test-meta"
has   "$out" "tests/test-wrap-x.sh  (self)" "the wrap diff still picks its own suite"
git checkout -q -- lib/wrap/wrap.sh tests/test-wrap-x.sh
echo "# edit" >> commands/c.md
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta.sh  (reads commands/c.md)" "a commands/ change picks test-meta"
git checkout -q -- commands/c.md
echo "# edit" >> docs/FEATURES.md
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta.sh  (reads docs/FEATURES.md)" "a docs/FEATURES.md change picks test-meta"
git checkout -q -- docs/FEATURES.md
echo "# edit" >> lib/z/verb.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta.sh  (reads lib/z/verb.sh)" "a lib file declaring a kit-verb picks test-meta"
git checkout -q -- lib/z/verb.sh
git stash pop -q 2>/dev/null || true

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

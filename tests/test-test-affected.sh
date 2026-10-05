#!/usr/bin/env bash
# test-test-affected.sh -- bin/test-affected in a throwaway git repo: the selection mapping,
# run/source versus mention for a source basename, kit.toml picked by changed section or key,
# the test-meta input rule, UNCOVERED, the pass cache (hit, miss after a source edit, FAIL never
# cached, --no-cache, unusable cache fails closed).
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TA="$KIT_DIR/bin/test-affected"
# bin/test-affected appends to the per-host timing history and may warn on load: keep both off the real host.
HIST_TMP="$(mktemp -d)"; export KIT_SUITE_TIMES_FILE="$HIST_TMP/suite-times.tsv" KIT_LOAD_WARN=100000
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
printf '#!/bin/bash\ncd lib/x && bash longname.sh\n'  > tests/test-longrun.sh
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
has   "$out" "tests/test-longrun.sh  (references lib/x/longname.sh)" "a suite that runs a long basename (bash longname.sh) selects"
hasnt "$out" "tests/test-long.sh" "a suite that only echoes the basename does not select"
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

echo "== test-meta: area suites picked by the path they read =="
# The group used to ride one runner pick (all eight areas, ~200s of a 253s run). A path now picks
# only the areas that read it by glob or scan (meta_areas), plus any suite that names it; a meta
# input no area is attributed falls back to the runner, never to nothing.
git stash -q -u
mkdir -p lib/wrap commands docs lib/z lib/board docs/verification
printf 'echo w\n' > lib/wrap/wrap.sh; printf '#!/bin/bash\nbash lib/wrap/wrap.sh\n' > tests/test-wrap-x.sh
printf -- '---\nname: c\n---\n' > commands/c.md; printf '# F\n' > docs/FEATURES.md
printf '#!/bin/bash\n# kit-verb: zz | a verb\necho z\n' > lib/z/verb.sh
printf '#!/bin/bash\n# kit-verb: dd | goes away\necho d\n' > lib/z/dropped.sh
printf 'echo u\n' > lib/board/unnamed.sh; printf 'echo n\n' > lib/board/named.sh
printf '# proof\n' > docs/verification/p.md; printf '# reg\n' > lib/board/notes.md
for a in plugin-hooks contract agents-commands spec-depth review-verifiers vmodel-dispatch goal-ledger docs-registry; do
  printf '#!/bin/bash\necho run-%s >> "$TA_MARK"\nexit 0\n' "$a" > "tests/test-meta-$a.sh"
done
printf '#!/bin/bash\necho run-goal >> "$TA_MARK"\nbash lib/board/named.sh\n' > tests/test-meta-goal-ledger.sh
git add -A && git commit -qm meta-fixtures && git update-ref refs/remotes/origin/main HEAD
echo "# edit" >> lib/wrap/wrap.sh; echo "# edit" >> tests/test-wrap-x.sh
out="$(bash "$TA" --list 2>&1)"
hasnt "$out" "tests/test-meta" "lib/wrap/*.sh + tests/test-wrap*.sh diff picks no test-meta suite"
has   "$out" "tests/test-wrap-x.sh  (self)" "the wrap diff still picks its own suite"
git checkout -q -- lib/wrap/wrap.sh tests/test-wrap-x.sh
echo "# edit" >> commands/c.md
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-agents-commands.sh  (reads commands/c.md)" "a commands/ change picks the agents-commands area"
has   "$out" "tests/test-meta-docs-registry.sh  (reads commands/c.md)" "a commands/ change picks docs-registry (registry input)"
hasnt "$out" "tests/test-meta-spec-depth.sh" "a commands/ change does not pick an area that names no command by glob"
hasnt "$out" "tests/test-meta-goal-ledger.sh" "a commands/ change does not pick goal-ledger"
hasnt "$out" "tests/test-meta.sh" "an attributed path does not pick the runner"
git checkout -q -- commands/c.md
echo "# edit" >> docs/FEATURES.md
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-docs-registry.sh  (reads docs/FEATURES.md)" "a docs/FEATURES.md change picks docs-registry"
hasnt "$out" "tests/test-meta-contract.sh" "a docs/FEATURES.md change does not pick contract"
git checkout -q -- docs/FEATURES.md
echo "# edit" >> lib/z/verb.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-docs-registry.sh  (reads lib/z/verb.sh)" "a lib file declaring a kit-verb picks docs-registry"
hasnt "$out" "tests/test-meta-plugin-hooks.sh" "a kit-verb lib file does not pick plugin-hooks"
git checkout -q -- lib/z/verb.sh
printf '#!/bin/bash\necho d\n' > lib/z/dropped.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-docs-registry.sh  (reads lib/z/dropped.sh)" "a lib file that dropped its kit-verb header still picks docs-registry (base copy counts)"
git checkout -q -- lib/z/dropped.sh
echo "# edit" >> lib/board/unnamed.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta.sh  (reads lib/board/unnamed.sh (no area attributed))" "a meta input no area is attributed falls back to the runner"
git checkout -q -- lib/board/unnamed.sh
echo "# edit" >> lib/board/named.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-goal-ledger.sh  (references lib/board/named.sh)" "an area suite naming the path is picked by reference"
hasnt "$out" "tests/test-meta.sh" "a path an area names does not pick the runner"
git checkout -q -- lib/board/named.sh
echo "# edit" >> lib/board/notes.md
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-plugin-hooks.sh  (reads lib/board/notes.md)" "a markdown file under lib/ is read by the *.md scan (plugin-hooks)"
hasnt "$out" "tests/test-meta-docs-registry.sh" "a lib markdown file does not pick docs-registry"
git checkout -q -- lib/board/notes.md
echo "# edit" >> docs/verification/p.md
out="$(bash "$TA" --list 2>&1)"
hasnt "$out" "tests/test-meta" "a dated archive doc (docs/verification/) is read by no area scan"
has   "$out" "UNCOVERED docs/verification/p.md" "an archive doc nobody names is UNCOVERED, not forced onto the runner"
git checkout -q -- docs/verification/p.md
printf '#!/bin/bash\nexit 0\n' > tests/test-hooks.sh
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-meta-docs-registry.sh  (reads tests/test-hooks.sh)" "a changed tests/test-hooks.sh (named by docs-registry) picks docs-registry"
rm -f tests/test-hooks.sh
git stash pop -q 2>/dev/null || true

echo "== source basename: run or source picks, a mention does not =="
git stash -q -u
mkdir -p lib/p
printf 'echo h\n' > lib/p/helper-lib.sh
printf '#!/bin/bash\ngrep -q helper-lib.sh docs/notes.txt\n'           > tests/test-greps.sh
printf '#!/bin/bash\ncd lib/p && source helper-lib.sh\n'                > tests/test-sources.sh
printf '#!/bin/bash\n. "$LIBDIR/helper-lib.sh"\n'                       > tests/test-dotvar.sh
printf '#!/bin/bash\ncd lib/p && ./helper-lib.sh\n'                     > tests/test-calls.sh
printf '#!/bin/bash\nbash "$KIT_DIR/lib/p/helper-lib.sh"\n'             > tests/test-bypath.sh
printf '#!/bin/bash\ngrep -q "lib/p/helper-lib.sh" docs/notes.txt\n'    > tests/test-pathgrep.sh
printf '#!/bin/bash\n# source helper-lib.sh\nexit 0\n'                  > tests/test-comment.sh
git add -A && git commit -qm run-fixtures && git update-ref refs/remotes/origin/main HEAD
echo "# edit" >> lib/p/helper-lib.sh
out="$(bash "$TA" --list 2>&1)"
hasnt "$out" "tests/test-greps.sh" "a suite that only greps the basename is not picked"
hasnt "$out" "tests/test-comment.sh" "a comment that sources the basename is not picked"
has   "$out" "tests/test-sources.sh  (references lib/p/helper-lib.sh)" "a suite that sources the basename is picked"
has   "$out" "tests/test-dotvar.sh  (references lib/p/helper-lib.sh)" "a suite that dot-sources \$VAR/<basename> is picked"
has   "$out" "tests/test-calls.sh  (references lib/p/helper-lib.sh)" "a suite that calls the basename directly is picked"
has   "$out" "tests/test-bypath.sh  (references lib/p/helper-lib.sh)" "a suite that runs the full path is picked"
has   "$out" "tests/test-pathgrep.sh  (references lib/p/helper-lib.sh)" "a suite that names the full repo path is picked even in a grep"
git checkout -q -- lib/p/helper-lib.sh
git stash pop -q 2>/dev/null || true

echo "== kit.toml: picked by the changed section or key =="
git stash -q -u
printf '# preamble\n\n[test]\nsuite = "full"\nload_warn = 16\n\n[review]\napply_findings = true\n' > kit.toml
printf '#!/bin/bash\ngrep -q load_warn "$KIT_DIR/kit.toml"\n'            > tests/test-kt-loadwarn.sh
printf '#!/bin/bash\nsed -n "/^[review]/,/^$/p" "$KIT_DIR/kit.toml"\n'     > tests/test-kt-review.sh
printf '#!/bin/bash\ncp "$KIT_DIR/kit.toml" "$TMPD/kit.toml"\n'          > tests/test-kt-copy.sh
printf '#!/bin/bash\nKIT_LOAD_WARN=5 bash lib/x/a.sh # no kit.toml here\n' > tests/test-kt-env.sh
git add -A && git commit -qm kit-fixtures && git update-ref refs/remotes/origin/main HEAD
sed -i.bak 's/^load_warn = 16/load_warn = 17/' kit.toml && rm -f kit.toml.bak
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-kt-loadwarn.sh  (references kit.toml)" "a [test] load_warn hunk picks the suite naming load_warn"
hasnt "$out" "tests/test-kt-review.sh" "a [test] hunk does not pick a suite naming only [review]"
hasnt "$out" "tests/test-kt-copy.sh" "a [test] hunk does not pick a suite that only copies kit.toml"
git checkout -q -- kit.toml
sed -i.bak 's/^apply_findings = true/apply_findings = false/' kit.toml && rm -f kit.toml.bak
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-kt-review.sh  (references kit.toml)" "a [review] key hunk picks the suite naming [review]"
hasnt "$out" "tests/test-kt-loadwarn.sh" "a [review] hunk does not pick a [test] suite"
git checkout -q -- kit.toml
printf '# extra preamble line\n' | cat - kit.toml > kit.toml.new && mv -f kit.toml.new kit.toml
out="$(bash "$TA" --list 2>&1)"
has   "$out" "tests/test-kt-loadwarn.sh  (references kit.toml)" "an unattributable hunk (above every section) falls back: suite one"
has   "$out" "tests/test-kt-review.sh  (references kit.toml)" "an unattributable hunk falls back: suite two"
has   "$out" "tests/test-kt-copy.sh  (references kit.toml)" "an unattributable hunk falls back: a copy-only suite"
git checkout -q -- kit.toml
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

echo "== timeouts: per-suite data file, env override, TIMEOUT is not FAIL =="
mkdir -p "$W/tabin" "$W/lib/telemetry"
cp "$TA" "$W/tabin/test-affected"; cp "$KIT_DIR/lib/telemetry/kit-log-dir.sh" "$W/lib/telemetry/" 2>/dev/null || true
TA2="$W/tabin/test-affected"
git checkout -q -- . 2>/dev/null || true
git stash -q -u 2>/dev/null || true
printf '#!/bin/bash\nsleep 6\nbash lib/x/a.sh\n' > tests/test-a.sh
echo "# edit4" >> lib/x/a.sh
printf '# header\ntest-a 1\ntest-b 99\n' > "$W/tabin/test-affected.timeouts"
out="$(bash "$TA2" --no-cache 2>&1)"; rc=$?
has   "$out" "TIMEOUT tests/test-a.sh (limit 1s)" "a suite over its listed limit prints TIMEOUT with the limit"
hasnt "$out" "FAIL tests/test-a.sh" "a timeout is never reported as FAIL"
has   "$out" "1 timeout" "the summary counts the timeout"
[ "$rc" != 0 ] && ok "a timeout exits non-zero" || bad "exit 0 despite TIMEOUT"
out="$(TEST_AFFECTED_TIMEOUT_SECS=30 bash "$TA2" --no-cache 2>&1)"; rc=$?
has   "$out" "PASS tests/test-a.sh" "TEST_AFFECTED_TIMEOUT_SECS overrides the data file"
printf '# header\ntest-b 99\n' > "$W/tabin/test-affected.timeouts"
out="$(bash "$TA2" --no-cache 2>&1)"
has   "$out" "PASS tests/test-a.sh" "a suite with no entry gets the 300s default"
printf '#!/bin/bash\nexit 1\n' > tests/test-a.sh
printf '# header\ntest-a 1\n' > "$W/tabin/test-affected.timeouts"
out="$(bash "$TA2" --no-cache 2>&1)"
has   "$out" "FAIL tests/test-a.sh" "a red suite inside its limit is still FAIL"
hasnt "$out" "TIMEOUT" "a red suite is not reported as TIMEOUT"
git checkout -q -- . 2>/dev/null || true
git stash pop -q 2>/dev/null || true

echo ""; echo "test-test-affected: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

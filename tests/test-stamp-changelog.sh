#!/usr/bin/env bash
# test-stamp-changelog.sh -- the changelog group of the team stamp: the seeded CHANGELOG.md,
# scripts/release-notes.sh (awk only) and its generated test, stamped into scratch repos.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-changelog.XXXXXX")" || exit 1
KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
EM="$(printf '\342\200\224')"; EN="$(printf '\342\200\223')"
TPL=templates/team-stamp
SEED="$TPL/files/CHANGELOG.md.tpl"
SCR="$TPL/files/scripts/release-notes.sh.tpl"
TST="$TPL/files/scripts/test-release-notes.sh.tpl"
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
stamp() { # stamp <repo> [flags]: the changelog group with fixed non-tag values
  local r="$1"; shift
  bash lib/stamp.sh --only changelog --default-branch master --owner testowner "$@" "$r"
}

# 1. manifest
M="$TPL/manifest.d/60-changelog.tsv"
expect "manifest exists" [ -f "$M" ]
expect "manifest: every row has five tab-separated columns" bash -c "grep -v '^#' '$M' | grep -v '^\$' | awk -F'\t' 'NF != 5 { exit 1 }'"
expect "manifest: CHANGELOG.md is a seed row" bash -c "grep -v '^#' '$M' | awk -F'\t' '\$1 == \"seed\" && \$3 == \"CHANGELOG.md\" { f = 1 } END { exit !f }'"
expect "manifest: the script declares TAGS and TAGS_ERE, its test declares TAGS" bash -c "grep -v '^#' '$M' | awk -F'\t' '\$3 == \"scripts/release-notes.sh\" && \$5 == \"TAGS,TAGS_ERE\" { a = 1 } \$3 == \"scripts/test-release-notes.sh\" && \$5 == \"TAGS\" { b = 1 } END { exit !(a && b) }'"

# 2. stamp with two custom tags
R1="$(newrepo)"
stamp "$R1" --tags app,lib >"$WORK/s1.out" 2>&1
expect "stamp the changelog group, custom tags" [ $? -eq 0 ]
for f in CHANGELOG.md scripts/release-notes.sh scripts/test-release-notes.sh; do
  expect "created: $f" [ -f "$R1/$f" ]
done
expect "both scripts are executable" bash -c "[ -x '$R1/scripts/release-notes.sh' ] && [ -x '$R1/scripts/test-release-notes.sh' ]"
expect "CHANGELOG: starts with a Changelog heading" bash -c "[ \"\$(awk 'NR == 1' '$R1/CHANGELOG.md')\" = '# Changelog' ]"
expect "CHANGELOG: ends with the [Unreleased] heading" bash -c "[ \"\$(awk 'END { print }' '$R1/CHANGELOG.md')\" = '## [Unreleased]' ]"
expect "CHANGELOG: lists every stamped tag, dev included" bash -c "grep -q 'app: lib: dev:' '$R1/CHANGELOG.md'"
expect "CHANGELOG: names dev as the team-tooling tag kept out of public notes" bash -c "grep -q '\`dev:\` is the team-tooling tag' '$R1/CHANGELOG.md' && grep -q 'release-notes.sh' '$R1/CHANGELOG.md'"
expect "CHANGELOG: no {{KEY}} left in any stamped file" bash -c "! grep -q '{{' '$R1/CHANGELOG.md' '$R1/scripts/release-notes.sh' '$R1/scripts/test-release-notes.sh'"
expect "script: the tag list and the ERE are the stamped ones" bash -c "grep -q \"^TAGS='app,lib,dev'\$\" '$R1/scripts/release-notes.sh' && grep -q \"^TAGS_ERE='app|lib|dev'\$\" '$R1/scripts/release-notes.sh'"

# 3. the generated test passes, for several tag lists
(cd "$R1" && bash scripts/test-release-notes.sh) >"$WORK/t1.out" 2>&1
expect "generated test passes with tags app,lib" [ $? -eq 0 ]
expect "generated test ran many cases" bash -c "[ \"\$(grep -c '^PASS' '$WORK/t1.out')\" -ge 60 ]"
R2="$(newrepo)"
stamp "$R2" >"$WORK/s2.out" 2>&1
(cd "$R2" && bash scripts/test-release-notes.sh) >"$WORK/t2.out" 2>&1
expect "generated test passes with the default tags" [ $? -eq 0 ]
expect "default tags: the list is product,dev" bash -c "grep -q \"^TAGS='product,dev'\$\" '$R2/scripts/release-notes.sh'"
R3="$(newrepo)"
stamp "$R3" --tags web,api,cli >"$WORK/s3.out" 2>&1
(cd "$R3" && bash scripts/test-release-notes.sh) >"$WORK/t3.out" 2>&1
expect "generated test passes with three product tags" [ $? -eq 0 ]
expect "three product tags: dev is added last" bash -c "grep -q \"^TAGS='web,api,cli,dev'\$\" '$R3/scripts/release-notes.sh'"

# 4. seed-once: idempotent, never drift-checked, never overwritten
stamp "$R1" --tags app,lib >"$WORK/s4.out" 2>&1
expect "second run prints only unchanged" bash -c "[ -s '$WORK/s4.out' ] && ! grep -v '^unchanged: ' '$WORK/s4.out'"
printf -- '- app: A first entry.\n' >>"$R1/CHANGELOG.md"
stamp "$R1" --tags app,lib --check >"$WORK/c1.out" 2>&1
expect "--check stays clean after the repo edits CHANGELOG.md" [ $? -eq 0 ]
R4="$(newrepo)"
printf '# My own changelog\n' >"$R4/CHANGELOG.md"
stamp "$R4" >"$WORK/s5.out" 2>&1
expect "a repo with a CHANGELOG.md keeps it untouched" bash -c "[ \"\$(cat '$R4/CHANGELOG.md')\" = '# My own changelog' ]"

# 5. the script on the stamped changelog, with python3 and jq absent
NOPY="$WORK/nopy"; mkdir -p "$NOPY"
for tool in bash awk; do ln -sf "$(command -v "$tool")" "$NOPY/$tool"; done
R5="$(newrepo)"
stamp "$R5" --tags app,lib >"$WORK/s6.out" 2>&1
(cd "$R5" && PATH="$NOPY" "$NOPY/bash" scripts/release-notes.sh Unreleased) >"$WORK/n1.out" 2>"$WORK/n1.err"
expect "the fresh changelog has nothing for a user: exit 1" [ $? -eq 1 ]
expect "the refusal is two lines, rule then Fix" bash -c "[ \"\$(wc -l <'$WORK/n1.err' | tr -d ' ')\" -eq 2 ] && awk 'NR == 1' '$WORK/n1.err' | grep -q '^release-notes: ' && awk 'NR == 2' '$WORK/n1.err' | grep -q '^Fix: '"
printf '\n### Added\n\n- app: Public thing.\n- dev: Tooling thing.\n- lib: Library thing.\n' >>"$R5/CHANGELOG.md"
(cd "$R5" && PATH="$NOPY" "$NOPY/bash" scripts/release-notes.sh Unreleased) >"$WORK/n2.out" 2>"$WORK/n2.err"
expect "with entries and no python3 on PATH: exit 0" [ $? -eq 0 ]
expect "the notes keep the product tags and drop dev" bash -c "grep -q '^- app: Public thing\.\$' '$WORK/n2.out' && grep -q '^- lib: Library thing\.\$' '$WORK/n2.out' && ! grep -q 'dev:' '$WORK/n2.out'"
printf -- '- Untagged line.\n' >>"$R5/CHANGELOG.md"
(cd "$R5" && PATH="$NOPY" "$NOPY/bash" scripts/release-notes.sh Unreleased) >"$WORK/n3.out" 2>"$WORK/n3.err"
expect "an untagged line is refused" [ $? -eq 1 ]
expect "the untagged refusal names the line and the tags" bash -c "grep -q 'Untagged line' '$WORK/n3.err' && grep -q '(app, lib, dev)' '$WORK/n3.err'"

# 6. text of the templates
for f in "$SEED" "$SCR" "$TST"; do
  expect "$f: no kit path and no home path" bash -c "! grep -Eq '$KIT_PATTERN' '$f'"
  expect "$f: no em or en dash" bash -c "! grep -q -e '$EM' -e '$EN' '$f'"
  expect "$f: no bare 40 or 64 hex run" bash -c "! grep -Eq '[0-9a-f]{40}' '$f'"
done
expect "$SCR: no python3 or jq command" bash -c "! grep -v '^ *#' '$SCR' | grep -Eq 'python3|(^|[^-A-Za-z])jq '"
for f in "$SCR" "$TST"; do
  expect "$f: no GNU-only construct" bash -c "! grep -v '^ *#' '$f' | grep -Eq 'grep -P|sed -r|readarray|mapfile|declare -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)'"
done
expect "the script's header says it needs awk, bash and coreutils only" bash -c "grep -q 'awk, bash and coreutils only' '$SCR'"
if command -v shellcheck >/dev/null 2>&1; then
  expect "shellcheck -S warning on the stamped scripts" shellcheck -S warning "$R1/scripts/release-notes.sh" "$R1/scripts/test-release-notes.sh" "$R3/scripts/release-notes.sh" "$R3/scripts/test-release-notes.sh"
else
  echo "note: shellcheck not installed, skipped"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

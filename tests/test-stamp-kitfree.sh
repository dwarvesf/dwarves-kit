#!/usr/bin/env bash
# test-stamp-kitfree.sh -- stamp a group into a temp repo and prove the result is kit-free.
# Usage: bash tests/test-stamp-kitfree.sh <group | fixture | all>
#   fixture  the fixture tree under tests/fixtures/team-stamp (what test-stamp.sh drives)
#   all      every group under templates/team-stamp/manifest.d (vacuous pass when none exist yet)
#   <group>  one manifest group, by the name after "NN-" in its manifest.d file
# Checks, on the stamped repo:
#   1. no generated file matches a kit-path pattern or the home path;
#   2. every generated scripts/test-*.sh passes with PATH holding only plain tools, HOME an empty
#      temp dir, no kit variable set, and no kit binary reachable.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
GROUP="${1:-}"
[ -n "$GROUP" ] || { echo "usage: bash tests/test-stamp-kitfree.sh <group|fixture|all>" >&2; exit 64; }

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'

ONLY=(); unset STAMP_TEMPLATES
case "$GROUP" in
  fixture) export STAMP_TEMPLATES="$ROOT/tests/fixtures/team-stamp";;
  all)
    ls "$ROOT"/templates/team-stamp/manifest.d/*.tsv >/dev/null 2>&1 || { echo "ok - no groups yet, nothing to stamp"; exit 0; };;
  *)
    ls "$ROOT"/templates/team-stamp/manifest.d/*-"$GROUP".tsv >/dev/null 2>&1 || { echo "NOT ok - no manifest group named '$GROUP'" >&2; exit 1; }
    ONLY=(--only "$GROUP");;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/stamp-kitfree.XXXXXX")" || exit 1
REPO="$WORK/repo"; mkdir -p "$REPO" "$WORK/home" "$WORK/bin"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init 2>/dev/null

if bash "$ROOT/lib/stamp.sh" ${ONLY[@]+"${ONLY[@]}"} --default-branch master --owner testowner --tags app,lib --product-paths app/,pkg/ --door-paths 'docs/legal/*' --door-approver reviewer --decision-tag decision --board-file docs/BOARD.md "$REPO" >"$WORK/stamp.out" 2>&1; then
  ok "stamp $GROUP into a temp repo"
else
  no "stamp $GROUP into a temp repo"; sed 's/^/    /' "$WORK/stamp.out"; echo "$PASS passed, $FAIL failed"; exit 1
fi

# 1. grep every file the lock lists
LOCK="$REPO/.claude/team-stamp.lock"
files="$(awk '$1=="file"{print $2}' "$LOCK")"
bad=0; count=0
for f in $files; do
  count=$((count + 1))
  if grep -Eq "$KIT_PATTERN" "$REPO/$f" || grep -qF "$HOME" "$REPO/$f"; then
    bad=1; echo "    kit path in $f: $(grep -En "$KIT_PATTERN" "$REPO/$f" | head -n 1 | cut -c1-100)"
  fi
done
[ "$count" -gt 0 ] && [ "$bad" -eq 0 ] && ok "no generated file ($count) names a kit path or the home path" || no "kit path found in a generated file"

# 2. run every generated test with the kit absent
for tool in bash sh git jq python3 awk sed grep egrep fgrep sort uniq wc tr cut head tail cat cp mv rm mkdir rmdir ls ln chmod touch date dirname basename \
  mktemp diff cmp find xargs env sleep tee readlink uname id expr test true false printf od shasum sha256sum stat tar gzip realpath seq yes comm paste fold nl rev tac shellcheck actionlint; do
  p="$(command -v "$tool" 2>/dev/null)" || continue
  case "$p" in /*) ln -sf "$p" "$WORK/bin/$tool";; esac
done
for kitbin in gate classify wrap board stamp; do
  PATH="$WORK/bin" command -v "$kitbin" >/dev/null 2>&1 && { no "the stripped PATH reaches a kit binary: $kitbin"; }
done
[ ! -e "$WORK/home/.claude/dwarves-kit" ] && ok "HOME holds no kit directory"

ran=0
for t in "$REPO"/scripts/test-*.sh; do
  [ -f "$t" ] || continue
  ran=$((ran + 1))
  if env -i PATH="$WORK/bin" HOME="$WORK/home" TMPDIR="$WORK" \
       GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
       GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
       "$WORK/bin/bash" "$t" >"$WORK/t.out" 2>&1; then
    ok "kit-free run: ${t#"$REPO"/}"
  else
    no "kit-free run: ${t#"$REPO"/}"; { grep -iE "FAIL|not ok" "$WORK/t.out" | head -n 10; tail -n 3 "$WORK/t.out"; } | sed 's/^/    /'
  fi
done
[ "$ran" -gt 0 ] || ok "no generated scripts/test-*.sh in this group"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

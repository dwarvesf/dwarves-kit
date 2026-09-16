#!/usr/bin/env bash
# test-gitattributes-union.sh -- the repo's own `.gitattributes` and what it buys.
#
# The kit shipped every union mechanism (wrap's carry-across-pull, the union re-merge, the
# board dedupe) and no `.gitattributes` of its own, so `_meta/BACKLOG.md` was never declared
# merge=union HERE. Two parallel sessions adding a board row therefore collided by hand: one
# sitting resolved the same stash-pop conflict four times. These cases pin the declaration and
# the two collisions it clears, each with the no-declaration control beside it.
#
# Run: bash tests/test-gitattributes-union.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$KIT_DIR/bin/wrap"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$({ trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$3"; echo $?)"; }
chk_no()  { chk "$1" "$({ trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$3" && echo 1 || echo 0)"; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-attr-test.XXXXXX")"
TMPD="$(cd "$TMPD" && pwd)"
trap 'rm -rf "$TMPD"' EXIT

# The operator's real config must never reach a case that did not ask for it.
KIT_CONFIG_OPERATOR="$TMPD/no-operator-config"; export KIT_CONFIG_OPERATOR
KNOB_ON="$TMPD/knob-on"; mkdir -p "$KNOB_ON"
printf '[wrap]\npull_past_dirty = true\n' > "$KNOB_ON/kit.toml"

gitc() { git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }

# A board shaped like the kit's own: a prose header, no `---` separator anywhere, one table
# whose rows every session appends to. The missing separator is the point: the anchor rule
# alone would carry a row to line 1, above the title.
BOARD_HEAD=$'# Task Backlog\n\nOne table row per work item.\n\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n'
board() { printf '%s' "$BOARD_HEAD"; printf '| %s | %s | src | queued |\n' "$@"; }

# build <name> <with-attributes 0|1> -- a bare origin plus a clone on main.
build() {
  local name="$1" attrs="$2" work="$TMPD/work-$1" clone="$TMPD/clone-$1"
  mkdir -p "$work/_meta"
  git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  # The declaration under test is the repo's REAL file, never a paraphrase of it.
  [ "$attrs" = 1 ] && cp "$KIT_DIR/.gitattributes" "$work/.gitattributes"
  board ID-001 first > "$work/_meta/BACKLOG.md"
  printf 'unrelated\n' > "$work/README.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/bare-$name"
  git clone -q "$TMPD/bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
}

# advance <name> -- an upstream session appends ITS row and pushes.
advance() {
  local push="$TMPD/push-$1"
  git clone -q "$TMPD/bare-$1" "$push"; gitc "$push"
  board ID-001 first ID-002 upstream > "$push/_meta/BACKLOG.md"
  git -C "$push" commit -qam upstream
  git -C "$push" push -q origin main
}

# dirty <clone> -- a sibling session's uncommitted row, at the same table tail.
dirty() { board ID-001 first ID-003 sibling > "$1/_meta/BACKLOG.md"; }

echo "=== the repo declares its append-only files merge=union ==="
chk "the .gitattributes file is tracked" \
  "$(git -C "$KIT_DIR" ls-files --error-unmatch .gitattributes >/dev/null 2>&1; echo $?)"
for f in _meta/BACKLOG.md _meta/backlog-staging.md docs/implementation-notes/x.md; do
  chk "check-attr says union for ${f}" \
    "$([ "$(git -C "$KIT_DIR" check-attr merge -- "$f")" = "${f}: merge: union" ]; echo $?)"
done
chk "a source file is left alone" \
  "$([ "$(git -C "$KIT_DIR" check-attr merge -- lib/wrap/wrap.sh)" = "lib/wrap/wrap.sh: merge: unspecified" ]; echo $?)"

echo "=== case 1: a dirty board row survives the wrap pull ==="
build carry 1; advance carry
C="$TMPD/clone-carry"; dirty "$C"
TIP="$(git -C "$TMPD/bare-carry" rev-parse main)"
out="$(KIT_CONFIG_OPERATOR="$KNOB_ON" "$WRAP" apply --apply "$C" 2>&1)"; rc=$?
chk "carry: apply exits 0" "$rc"
chk_no "carry: the pull did not fail" "$out" "FAILED pull --ff-only"
chk "carry: HEAD reached the upstream tip" \
  "$([ "$(git -C "$C" rev-parse HEAD)" = "$TIP" ]; echo $?)"
chk "carry: the upstream row landed" \
  "$(grep -qF '| ID-002 | upstream |' "$C/_meta/BACKLOG.md"; echo $?)"
chk "carry: the sibling's row survived" \
  "$(grep -qF '| ID-003 | sibling |' "$C/_meta/BACKLOG.md"; echo $?)"
chk "carry: line 1 is still the title, not a carried row" \
  "$([ "$(sed -n 1p "$C/_meta/BACKLOG.md")" = "# Task Backlog" ]; echo $?)"
# Placement, not just survival: the carried row lands at the table tail, where the union
# driver puts it and where `board capture` had it. Contiguity is what says it is still a table.
chk "carry: the carried row is last, as a union merge orders it" \
  "$([ "$(grep '^| ID-' "$C/_meta/BACKLOG.md" | tail -1)" = "| ID-003 | sibling | src | queued |" ]; echo $?)"
chk "carry: the three rows are contiguous" \
  "$([ "$(grep -n '^| ID-' "$C/_meta/BACKLOG.md" | cut -d: -f1 | tr '\n' ' ')" = "7 8 9 " ]; echo $?)"
chk_has "carry: the row is still uncommitted" "$(git -C "$C" diff --name-only)" "_meta/BACKLOG.md"
chk "carry: and never staged" "$([ -z "$(git -C "$C" diff --cached --name-only)" ]; echo $?)"
chk "carry: no stash was left behind" "$([ "$(git -C "$C" stash list | grep -c '')" = "0" ]; echo $?)"

echo "--- negative control: the same repo with no union declaration"
build nocarry 0; advance nocarry
N="$TMPD/clone-nocarry"; dirty "$N"
N_HEAD="$(git -C "$N" rev-parse HEAD)"
out="$(KIT_CONFIG_OPERATOR="$KNOB_ON" "$WRAP" apply --apply "$N" 2>&1)"; rc=$?
chk "control: apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "control: the pop conflict is what the operator hand-resolved" "$out" "POP CONFLICT"
chk "control: the conflict markers are in the board" \
  "$(grep -q '^<<<<<<<' "$N/_meta/BACKLOG.md"; echo $?)"
chk "control: the run's stash is kept" \
  "$([ "$(git -C "$N" stash list | grep -c 'wrap-pull-past-dirty-')" = "1" ]; echo $?)"

echo "=== case 2: two branches adding a row merge without a conflict ==="
build merge 1
M="$TMPD/clone-merge"
git -C "$M" checkout -q -b feat/a
board ID-001 first ID-010 branch-a > "$M/_meta/BACKLOG.md"
git -C "$M" commit -qam "row a"
git -C "$M" checkout -q main
git -C "$M" checkout -q -b feat/b
board ID-001 first ID-011 branch-b > "$M/_meta/BACKLOG.md"
git -C "$M" commit -qam "row b"
git -C "$M" merge feat/a --no-edit -q >/dev/null 2>&1; rc=$?
chk "merge: the branch merge succeeded" "$rc"
chk "merge: no conflict markers" "$(grep -q '^<<<<<<<' "$M/_meta/BACKLOG.md" && echo 1 || echo 0)"
chk "merge: branch a's row is present" "$(grep -qF '| ID-010 | branch-a |' "$M/_meta/BACKLOG.md"; echo $?)"
chk "merge: branch b's row is present" "$(grep -qF '| ID-011 | branch-b |' "$M/_meta/BACKLOG.md"; echo $?)"
chk "merge: the base row is present exactly once" \
  "$([ "$(grep -cF '| ID-001 | first |' "$M/_meta/BACKLOG.md")" = "1" ]; echo $?)"

echo "--- negative control: the same two branches with no union declaration"
build nomerge 0
NM="$TMPD/clone-nomerge"
git -C "$NM" checkout -q -b feat/a
board ID-001 first ID-010 branch-a > "$NM/_meta/BACKLOG.md"
git -C "$NM" commit -qam "row a"
git -C "$NM" checkout -q main
git -C "$NM" checkout -q -b feat/b
board ID-001 first ID-011 branch-b > "$NM/_meta/BACKLOG.md"
git -C "$NM" commit -qam "row b"
git -C "$NM" merge feat/a --no-edit -q >/dev/null 2>&1; rc=$?
chk "merge control: the merge refuses" "$([ "$rc" -ne 0 ]; echo $?)"
chk "merge control: the board carries conflict markers" \
  "$(grep -q '^<<<<<<<' "$NM/_meta/BACKLOG.md"; echo $?)"

echo
echo "  $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1

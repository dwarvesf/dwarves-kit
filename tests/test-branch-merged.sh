#!/usr/bin/env bash
# test-branch-merged.sh -- lib/gate/branch-merged.sh: branch_merged and its options, driven against a
# scratch repo and a gh shim. The default answer is the ladder grammar every wrap caller reads;
# --need pr, --tip, --prs-json and --numbers narrow it and never widen it.
# modules under test (the test-affected cache key greps this line):
# lib/gate/branch-merged.sh
# Run: bash tests/test-branch-merged.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars) 2>/dev/null
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-branch-merged.XXXXXX")" || exit 1
TMPD="$(cd "$TMPD" && pwd -P)"
trap 'chmod -R u+w "$TMPD" 2>/dev/null; rm -rf "$TMPD"' EXIT
export HOME="$TMPD/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

PASS=0; FAIL=0
chk() { if [ "$2" -eq 0 ] 2>/dev/null; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }
eq() { if [ "$2" = "$3" ]; then chk "$1" 0; else echo "    want: $3"; echo "    got:  $2"; chk "$1" 1; fi; }
starts() { case "$2" in "$3"*) chk "$1" 0 ;; *) echo "    want prefix: $3"; echo "    got:         $2"; chk "$1" 1 ;; esac; }

# gh shim: `pr list --head <b> --state merged` answers $SHIM/merged-<b>; mode ok|fail|garbage|empty.
SHIM="$TMPD/shim"; mkdir -p "$SHIM" "$TMPD/bin"
cat > "$TMPD/bin/gh" <<'EOF'
#!/usr/bin/env bash
S="${GH_SHIM_DIR:?}"
[ "${1:-}" = auth ] && exit 0
head=""
while [ $# -gt 0 ]; do case "$1" in --head) head="${2:-}"; shift 2 ;; *) shift ;; esac; done
case "$(cat "$S/mode" 2>/dev/null || echo ok)" in
  fail) exit 1 ;; garbage) echo 'not json'; exit 0 ;; empty) exit 0 ;;
esac
cat "$S/merged-$(printf '%s' "$head" | tr -c 'A-Za-z0-9' '_')" 2>/dev/null || echo '[]'
EOF
chmod +x "$TMPD/bin/gh"
export GH_SHIM_DIR="$SHIM" PATH="$TMPD/bin:$PATH"
setm() { printf '%s' "$2" > "$SHIM/merged-$1"; }
mode() { printf '%s' "$1" > "$SHIM/mode"; }
row() { # row <number> <head> <oid> <base> [cross] [mergedAt-null]
  local m='"2026-01-01T00:00:00Z"'; [ -n "${6:-}" ] && m=null
  printf '{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"%s","isCrossRepository":%s,"mergedAt":%s}' "$1" "$2" "$3" "$4" "${5:-false}" "$m"
}

source "$KIT_DIR/lib/gate/branch-merged.sh"

# --- fixture: master plus four local branches, none pushed
BARE="$TMPD/bare"; R="$TMPD/clone"
git init -q --bare -b master "$BARE"; git clone -q "$BARE" "$R" 2>/dev/null
git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
git -C "$R" checkout -q -b master 2>/dev/null
echo base > "$R/f"; git -C "$R" add f; git -C "$R" commit -qm "chore: base"
mk() { git -C "$R" checkout -q -b "$1" master; echo "$2" > "$R/$3"; git -C "$R" add "$3"; git -C "$R" commit -qm "feat: $1"; git -C "$R" checkout -q master; }
mk anc 1 anc.txt; mk abs 1 abs.txt; mk sq a sq.txt; mk sqmore a sqm.txt
git -C "$R" merge -q --no-edit anc >/dev/null 2>&1                       # anc: ancestor of master
echo 1 > "$R/abs.txt"; git -C "$R" add abs.txt; git -C "$R" commit -qm "feat: abs again"   # abs: same bytes, new commit
echo a > "$R/sq.txt"; git -C "$R" add sq.txt; git -C "$R" commit -qm "feat: squash of sq"
echo later >> "$R/sq.txt"; git -C "$R" commit -qam "fix: later"          # sq: not absorbed any more
echo a > "$R/sqm.txt"; git -C "$R" add sqm.txt; git -C "$R" commit -qm "feat: squash of sqmore"
echo later >> "$R/sqm.txt"; git -C "$R" commit -qam "fix: later again"
git -C "$R" push -q origin master; git -C "$R" fetch -q origin
SQ="$(git -C "$R" rev-parse sq)"
git -C "$R" checkout -q sqmore; echo extra > "$R/x"; git -C "$R" add x; git -C "$R" commit -qm "feat: after the PR"; git -C "$R" checkout -q master
SQM="$(git -C "$R" rev-parse sqmore)"; SQM_HEAD="$(git -C "$R" rev-parse sqmore~1)"
bm() { branch_merged "$@"; }

echo "=== default mode: ancestor, absorbed, then the PR rung ==="
mode ok; setm sq "[$(row 1 sq "$SQ" master)]"
eq "ancestor"                    "$(bm "$R" master ok anc)"      "SAFE ancestor ancestor of origin/master"
eq "absorbed content"            "$(bm "$R" master ok abs)"      "SAFE absorbed content already on origin/master"
eq "merged PR at the exact tip"  "$(bm "$R" master ok sq)"       "SAFE squash squash-merged per gh"
setm sqmore "[$(row 2 sqmore "$SQM_HEAD" master)]"
eq "a commit past the PR head"   "$(bm "$R" master ok sqmore)"   "LEAVE tip $SQM_HEAD"
setm sq "[$(row 1 sq "$SQ" stack-base)]"
eq "PR merged into another base" "$(bm "$R" master ok sq)"       "LEAVE base stack-base"
setm sq '[]'
eq "no PR"                       "$(bm "$R" master ok sq)"       "LEAVE none no merged PR found for this head"
eq "gh not ok"                   "$(bm "$R" master unauthenticated sq)" "LEAVE nogh (gh unauthenticated)"
eq "gh not ok keeps ancestor"    "$(bm "$R" master unauthenticated anc)" "SAFE ancestor ancestor of origin/master"

echo "=== --need pr: only a merged PR at the exact tip can say SAFE ==="
setm sq "[$(row 1 sq "$SQ" master)]"
eq "pr: exact-tip PR"            "$(bm --need pr "$R" master ok sq)"  "SAFE squash squash-merged per gh"
setm anc '[]'; setm abs '[]'
eq "pr: ancestor with no PR"     "$(bm --need pr "$R" master ok anc)" "LEAVE none no merged PR found for this head"
eq "pr: absorbed with no PR"     "$(bm --need pr "$R" master ok abs)" "LEAVE none no merged PR found for this head"
setm sqmore "[$(row 2 sqmore "$SQM_HEAD" master)]"
starts "pr: tip past the PR head" "$(bm --need pr "$R" master ok sqmore)" "LEAVE tip "
eq "pr: --tip names the PR head" "$(bm --need pr --tip "$SQM_HEAD" "$R" master ok sqmore)" "SAFE squash squash-merged per gh"
setm sq "[$(row 1 sq "$SQ" stack-base)]"
eq "pr: another base"            "$(bm --need pr "$R" master ok sq)"  "LEAVE base stack-base"
starts "pr: gh not ok"           "$(bm --need pr "$R" master unavailable sq)" "LEAVE nogh"
for m in fail garbage empty; do
  mode "$m"
  eq "pr: gh '$m' keeps the branch" "$(bm --need pr "$R" master ok sq)" "LEAVE none no merged PR found for this head"
done
mode ok

echo "=== --prs-json: a caller-supplied list, strict about the head name ==="
J="$TMPD/prs.json"
tip="$SQ"
printf '[%s]' "$(row 1 sq "$tip" master)" > "$J";                       eq "json: exact row"       "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "SAFE squash squash-merged per gh"
printf '[%s]' "$(row 1 other "$tip" master)" > "$J";                    starts "json: another head's row ignored" "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "LEAVE none"
printf '[{"number":1,"headRefOid":"%s","baseRefName":"master","mergedAt":"2026-01-01T00:00:00Z"}]' "$tip" > "$J"
starts "json: a row without headRefName never counts" "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "LEAVE none"
printf '[%s]' "$(row 1 sq "$tip" master true)" > "$J";                  starts "json: a fork row never counts" "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "LEAVE none"
printf '[%s]' "$(row 1 sq "$tip" master false null)" > "$J";            starts "json: no mergedAt never counts" "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "LEAVE none"
printf '[%s]' "$(row 1 sq "$tip" stack-base)" > "$J";                   eq "json: another base"    "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "LEAVE base stack-base"
printf 'not json' > "$J";                                               starts "json: unusable list" "$(bm --need pr --prs-json "$J" "$R" master ok sq)" "LEAVE none"
starts "json: missing file"      "$(bm --need pr --prs-json "$TMPD/none.json" "$R" master ok sq)" "LEAVE none"
printf '[%s]' "$(row 1 sq "$tip" master)" > "$J"
starts "json: gh not ok"         "$(bm --need pr --prs-json "$J" "$R" master unauthenticated sq)" "LEAVE nogh"

echo "=== gh path: a fork's same-named merged PR never counts ==="
setm sq "[$(row 1 sq "$SQ" master true)]"
starts "fork row from gh"        "$(bm --need pr "$R" master ok sq)" "LEAVE none"

echo "=== --numbers: the merged PRs that speak for the tip ==="
setm sq "[$(row 7 sq "$SQ" master),$(row 8 sq "$SQ" master)]"
out="$(bm --numbers --need pr "$R" master ok sq)"; rc=$?
eq "numbers: both PRs" "$(printf '%s' "$out" | tr '\n' ' ')" "7 8"; eq "numbers: exit 0" "$rc" "0"
setm sq "[$(row 7 sq "$SQ" stack-base)]"
bm --numbers --need pr "$R" master ok sq >/dev/null; eq "numbers: another base is none (exit 1)" "$?" "1"
setm sq '[]'
bm --numbers --need pr "$R" master ok sq >/dev/null; eq "numbers: no PR is none (exit 1)" "$?" "1"
setm sq "[$(row 7 sq "$SQ" master)]"
bm --numbers --need pr --tip "$(git -C "$R" rev-parse anc)" "$R" master ok sq >/dev/null; eq "numbers: another tip is none (exit 1)" "$?" "1"
for m in fail garbage empty; do
  mode "$m"; bm --numbers --need pr "$R" master ok sq >/dev/null; eq "numbers: gh '$m' is unreadable (exit 2)" "$?" "2"
done
mode ok
bm --numbers --need pr "$R" master unauthenticated sq >/dev/null; eq "numbers: gh not ok is unreadable (exit 2)" "$?" "2"

echo "=== usage errors print nothing and exit 64 ==="
out="$(bm --need bogus "$R" master ok sq)"; rc=$?; eq "bad --need" "$rc:$out" "64:"
out="$(bm "$R" master ok)"; rc=$?; eq "missing branch" "$rc:$out" "64:"
out="$(bm --nope "$R" master ok sq)"; rc=$?; eq "unknown flag" "$rc:$out" "64:"
out="$(bm --tip)"; rc=$?; eq "flag without a value" "$rc:$out" "64:"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-branch-merged: $PASS passed, $FAIL FAILED"; exit 1; fi
echo "test-branch-merged: all $PASS passed"

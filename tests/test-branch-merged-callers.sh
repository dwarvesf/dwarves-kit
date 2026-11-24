#!/usr/bin/env bash
# test-branch-merged-callers.sh -- the callers that delete on a "merged" answer, driven against
# scratch repos and a gh shim only: `lib/goal/wt.sh close` and the `wrap apply` origin sweep.
# Each caller's refusals are rows here, so a migration onto the shared merged check proves it
# still refuses everything it refused before. Rows labelled known-gap pin a deletion bug that
# the migration closes; the label names the task whose commit flips the row. Both known gaps are now closed.
# modules under test (the test-affected cache key greps this line):
# lib/goal/wt.sh lib/wrap/wrap-common.sh lib/wrap/wrap-apply.sh lib/gate/branch-merged.sh
#
# Isolation: mktemp scratch, fresh HOME, no inherited git env, no real gh, no network.
# Run: bash tests/test-branch-merged-callers.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars) 2>/dev/null
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-merged-callers.XXXXXX")" || exit 1
TMPD="$(cd "$TMPD" && pwd -P)"
trap 'chmod -R u+w "$TMPD" 2>/dev/null; rm -rf "$TMPD"' EXIT
export HOME="$TMPD/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GOAL_REGISTRY_DIR="$TMPD/registry"
export KIT_CONFIG_OPERATOR="$TMPD/no-operator-config"

PASS=0; FAIL=0
chk() { # chk <label> <rc>
  if [ "$2" -eq 0 ] 2>/dev/null; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3"; echo $?)"; }
chk_no()  { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3" && echo 1 || echo 0)"; }

# --------------------------------------------------------------------------- gh shim
# Answers only what wt.sh and the origin sweep ask. Everything it reads sits in $SHIM:
#   mode             ok (default) | fail (exit 1, no output) | garbage (not JSON) | empty (exit 0, no output)
#   merged-<head>    JSON for `pr list --head <head> --state merged` (head with / as _)
#   state-<head>     what `pr list --state all --head <head> --jq` prints; default MERGED when merged-<head> has rows
#   merged-all       JSON for the repo-wide `pr list --state merged --limit N`
#   open             JSON for `pr list --state open` (default [])
SHIM="$TMPD/shim"; mkdir -p "$SHIM" "$TMPD/bin"
cat > "$TMPD/bin/gh" <<'EOF'
#!/usr/bin/env bash
S="${GH_SHIM_DIR:?}"
sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  auth) exit 0 ;;
  api) echo me; exit 0 ;;
  pr) ;;
  *) echo '[]'; exit 0 ;;
esac
verb="${1:-}"; [ $# -gt 0 ] && shift
[ "$verb" = list ] || { echo '{}'; exit 0; }
head=""; state=""; jq=0
while [ $# -gt 0 ]; do
  case "$1" in
    --head) head="${2:-}"; shift 2 ;;
    --state) state="${2:-}"; shift 2 ;;
    --jq) jq=1; shift 2 ;;
    *) shift ;;
  esac
done
mode="$(cat "$S/mode" 2>/dev/null || echo ok)"
case "$mode" in
  fail) exit 1 ;;
  garbage) echo 'not json'; exit 0 ;;
  empty) exit 0 ;;
esac
key="$(printf '%s' "$head" | tr -c 'A-Za-z0-9' '_')"
if [ "$jq" = 1 ]; then
  if [ -f "$S/state-$key" ]; then cat "$S/state-$key"
  elif [ -s "$S/merged-$key" ] && [ "$(cat "$S/merged-$key")" != "[]" ]; then echo MERGED; fi
  exit 0
fi
if [ "$state" = open ]; then cat "$S/open" 2>/dev/null || echo '[]'; exit 0; fi
if [ -n "$head" ]; then cat "$S/merged-$key" 2>/dev/null || echo '[]'; exit 0; fi
cat "$S/merged-all" 2>/dev/null || echo '[]'
EOF
chmod +x "$TMPD/bin/gh"
export GH_SHIM_DIR="$SHIM"
export PATH="$TMPD/bin:$PATH"
shim_reset() { find "$SHIM" -type f -delete; }
shim_set() { printf '%s' "$2" > "$SHIM/$1"; }
pr_row() { # pr_row <number> <head> <oid> <base> [cross] -- one merged-PR record
  printf '{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"%s","isCrossRepository":%s,"mergedAt":"2026-01-01T00:00:00Z"}' \
    "$1" "$2" "$3" "$4" "${5:-false}"
}
gitc() { git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }
URL="git@github.com:acme/scratch.git"

# build_pair <name> -- a bare origin and a clone on master behind a github.com URL, insteadOf routing
# every fetch and push to the bare. Prints the clone path.
build_pair() {
  local n="$1" bare="$TMPD/bare-$1" clone="$TMPD/clone-$1"
  git init -q --bare -b master "$bare"
  git clone -q "$bare" "$clone" 2>/dev/null; gitc "$clone"
  git -C "$clone" checkout -q -b master 2>/dev/null
  echo base > "$clone/f"; git -C "$clone" add f; git -C "$clone" commit -qm "chore: base"
  git -C "$clone" push -q origin master
  git -C "$clone" remote set-url origin "$URL"
  git -C "$clone" config "url.$bare.insteadOf" "$URL"
  printf '%s\n' "$clone"
}

# ===========================================================================
echo "=== wt.sh close: refuses everything but a merged PR (the refusals it has today) ==="
# ===========================================================================
# wt_case <name> -- clone with feat/x = A pushed; master moved on past a squash of A, so the branch is
# neither an ancestor of origin/master nor absorbed. Sets WT_CLONE and A.
wt_case() {
  local c; shim_reset
  c="$(build_pair "$1")"; WT_CLONE="$c"
  git -C "$c" checkout -q -b feat/x
  echo a > "$c/f"; git -C "$c" commit -qam "feat: a"; A="$(git -C "$c" rev-parse HEAD)"
  git -C "$c" push -q origin feat/x
  git -C "$c" checkout -q master
  echo a > "$c/f"; git -C "$c" commit -qam "feat: squash of a"
  echo later >> "$c/f"; git -C "$c" commit -qam "fix: later master work"
  git -C "$c" push -q origin master
  ln -s "$KIT_DIR/lib" "$c/lib"
}
wt_close() { ( cd "$WT_CLONE" && bash "$KIT_DIR/lib/goal/wt.sh" close x feat 2>&1 ); }
wt_has_branch() { git -C "$WT_CLONE" rev-parse -q --verify refs/heads/feat/x >/dev/null; }
wt_origin_has() { git -C "$TMPD/bare-$1" show-ref --verify --quiet refs/heads/feat/x; }

wt_case w1
out="$(wt_close)"; rc=$?
chk "wt close: no PR at all refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"
chk_has "wt close: no PR names the refusal" "$out" "refusing to close"
chk "wt close: no PR leaves origin's branch" "$(wt_origin_has w1; echo $?)"

wt_case w2; shim_set state-feat_x OPEN   # an open PR is never in the merged list
out="$(wt_close)"; rc=$?
chk "wt close: an OPEN PR refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"

wt_case w3; shim_set state-feat_x CLOSED
out="$(wt_close)"; rc=$?
chk "wt close: a CLOSED PR refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"

for m in fail garbage empty; do
  wt_case "w4$m"; shim_set merged-feat_x "[$(pr_row 1 feat/x "$A" master)]"; shim_set mode "$m"
  out="$(wt_close)"; rc=$?
  chk "wt close: a gh answer of '$m' refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"
  chk "wt close: '$m' leaves origin's branch" "$(wt_origin_has "w4$m"; echo $?)"
done

wt_case w5; shim_set merged-feat_x "[$(pr_row 1 feat/x "$A" master)]"
out="$(wt_close)"; rc=$?
chk "wt close: a merged PR at the exact tip closes" "$([ "$rc" -eq 0 ] && ! wt_has_branch; echo $?)"
chk "wt close: the exact-tip close deletes origin's branch" "$(! wt_origin_has w5; echo $?)"

# The branch holds a commit its merged PR never carried: wt.sh used to close it and lose the commit.
wt_case w6; shim_set merged-feat_x "[$(pr_row 1 feat/x "$A" master)]"
git -C "$WT_CLONE" checkout -q feat/x; echo unpushed > "$WT_CLONE/g"; git -C "$WT_CLONE" add g
git -C "$WT_CLONE" commit -qm "feat: made after the PR merged"; B="$(git -C "$WT_CLONE" rev-parse HEAD)"
git -C "$WT_CLONE" checkout -q master
out="$(wt_close)"; rc=$?
chk "wt close: a commit the merged PR never carried refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"
chk_has "wt close: the refusal names LEAVE tip and the PR head" "$out" "LEAVE tip $A"
chk "wt close: the unpushed commit is still reachable from the branch" "$([ "$(git -C "$WT_CLONE" rev-parse refs/heads/feat/x)" = "$B" ]; echo $?)"
chk "wt close: origin's branch is untouched" "$(wt_origin_has w6; echo $?)"

wt_case w7; shim_set merged-feat_x "[$(pr_row 1 feat/x "$A" stack-base)]"
out="$(wt_close)"; rc=$?
chk "wt close: a PR merged into another base refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"
chk_has "wt close: the other base is named" "$out" "LEAVE base stack-base"

wt_case w8; shim_set merged-feat_x "[$(pr_row 1 feat/x "$A" master true)]"
out="$(wt_close)"; rc=$?
chk "wt close: a fork's merged PR refuses" "$([ "$rc" -ne 0 ] && wt_has_branch; echo $?)"

# ===========================================================================
echo "=== wrap apply origin sweep: deletes only a merged PR's exact tip (the refusals it has today) ==="
# ===========================================================================
# sweep_repo <name> -- a bare origin holding master plus one branch per class; prints the clone path.
SWEEP_BRANCHES="gone otherbase moved nopr openhead openbase fork"
sweep_repo() {
  local n="$1" c b; c="$(build_pair "$n")"
  for b in $SWEEP_BRANCHES; do
    git -C "$c" checkout -q -b "$b" master; echo "$b" > "$c/$b.txt"; git -C "$c" add -A
    git -C "$c" commit -qm "feat: $b"; git -C "$c" push -q origin "$b"
  done
  # moved gains a commit after its PR merged; nopr is merged by plain ancestry (no PR record).
  git -C "$c" checkout -q moved
  echo more >> "$c/moved.txt"; git -C "$c" commit -qam "fix: more"; git -C "$c" push -q origin moved
  git -C "$c" checkout -q master
  git -C "$c" merge -q --no-edit nopr >/dev/null 2>&1; git -C "$c" push -q origin master
  git -C "$c" fetch -q origin
  printf '%s\n' "$c"
}
tip_of() { git -C "$TMPD/bare-$1" rev-parse "refs/heads/$2"; }
sweep_rows() { # sweep_rows <name> -- the merged list for every class
  local n="$1" t; t() { tip_of "$n" "$1"; }
  shim_reset
  shim_set merged-all "[$(pr_row 1 gone "$(t gone)" master),$(pr_row 2 otherbase "$(t otherbase)" stack-base),$(pr_row 3 moved "$(git -C "$TMPD/bare-$n" rev-parse refs/heads/moved~1)" master),$(pr_row 4 openhead "$(t openhead)" master),$(pr_row 5 openbase "$(t openbase)" master),$(pr_row 6 fork "$(t fork)" master true),$(pr_row 7 master "$(t master)" master)]"
  shim_set open "[{\"number\":20,\"headRefName\":\"openhead\",\"baseRefName\":\"develop\"},{\"number\":21,\"headRefName\":\"child\",\"baseRefName\":\"openbase\"}]"
}
sweep_run() { # sweep_run <name> <APPLY> [own-branches-newline]
  local c="$TMPD/clone-$1"
  bash -c '
    export KIT_CONFIG_ROOT="$1"
    source "$1/lib/config/kit-config.sh"; source "$1/lib/wrap/wrap-common.sh"; source "$1/lib/wrap/wrap-apply.sh"
    APPLY="$3"; OWN_SET="${4:-}"; OWN_BRANCHES="${4:-}"; FAILURES=0
    _apply_origin_branches "$2" master ok' _ "$KIT_DIR" "$c" "$2" "${3:-}" 2>&1 </dev/null
}
alive() { git -C "$TMPD/bare-$1" show-ref --verify --quiet "refs/heads/$2"; }

s1="$(sweep_repo s1)"; sweep_rows s1
out="$(sweep_run s1 1 | sed 's/^/    /')"
chk "sweep: a merged PR at the exact origin tip is deleted" "$(! alive s1 gone; echo $?)"
chk "sweep: master is never deleted" "$(alive s1 master; echo $?)"
chk "sweep: a tip past the PR head is kept" "$(alive s1 moved; echo $?)"
chk "sweep: a branch with no PR record is kept (plain ancestry is not a PR)" "$(alive s1 nopr; echo $?)"
chk "sweep: a branch with an open PR as head is kept" "$(alive s1 openhead; echo $?)"
chk "sweep: a branch with an open PR based on it is kept" "$(alive s1 openbase; echo $?)"
chk "sweep: a cross-repository PR is ignored" "$(alive s1 fork; echo $?)"
# The sweep once had no base check: a PR merged into another base qualified.
chk "sweep: a PR merged into a non-default base is kept" "$(alive s1 otherbase; echo $?)"

s2="$(sweep_repo s2)"; sweep_rows s2
out="$(sweep_run s2 0)"
chk_has "sweep dry run names the exact-tip branch" "$out" "gone"
chk "sweep dry run deletes nothing" "$(alive s2 gone; echo $?)"

for m in fail garbage empty; do
  s3="$(sweep_repo "s3$m")"; sweep_rows "s3$m"; shim_set mode "$m"
  out="$(sweep_run "s3$m" 1)"
  chk_has "sweep: a gh answer of '$m' skips the sweep" "$out" "SKIP origin sweep"
  chk "sweep: '$m' deletes nothing" "$(alive "s3$m" gone; echo $?)"
done

s3o="$(sweep_repo s3open)"; sweep_rows s3open; shim_set open 'not json'
out="$(sweep_run s3open 1)"
chk_has "sweep: an unreadable open-PR list skips the sweep" "$out" "SKIP origin sweep"
chk "sweep: an unreadable open-PR list deletes nothing" "$(alive s3open gone; echo $?)"

s4="$(sweep_repo s4)"; sweep_rows s4
out="$(sweep_run s4 1 "otherbase")"
chk "sweep --own: an unnamed branch is kept" "$(alive s4 gone; echo $?)"

s5="$(sweep_repo s5)"; sweep_rows s5
git -C "$s5" remote set-url origin "$TMPD/bare-s5"
out="$(sweep_run s5 1)"
chk_has "sweep: a non-GitHub origin skips the sweep" "$out" "origin is not a GitHub remote"
chk "sweep: a non-GitHub origin deletes nothing" "$(alive s5 gone; echo $?)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-branch-merged-callers: $PASS passed, $FAIL FAILED"; exit 1; fi
echo "test-branch-merged-callers: all $PASS passed"

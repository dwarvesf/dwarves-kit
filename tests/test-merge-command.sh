#!/usr/bin/env bash
# test-merge-command.sh -- the project merge command (`[merge] command`, lib/config/merge-command.sh):
# the resolver, `wrap merge`, `wrap land` and `lib/goal/stack-merge.sh` all merge through it when it
# is set, a refusal stops the flow with the command's own message, and nothing falls back to the
# plain squash. mega-merge's cases live in tests/test-mega-merge.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/config/merge-command.sh lib/config/kit-config.sh lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/goal/stack-merge.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

export MC_LOG="$TMPD/mc-script.log"

# mc_script <ok|refuse> -- the body of scripts/pr-merge.sh. "ok" logs its arguments and, when a
# land case wired the gh stub's landing vars, pushes the branch to the remote's main the way
# GitHub's squash would. "refuse" prints a refusal on stderr and exits 7.
mc_script() {
  case "$1" in
    ok) cat <<'SH'
#!/usr/bin/env bash
printf 'ran pr=%s env_pr=%s head=%s cwd=%s\n' "$1" "${KIT_MERGE_PR:-}" "${KIT_MERGE_HEAD_COMMIT:-}" "$(pwd -P)" >> "$MC_LOG"
if [ -n "${GH_STUB_LAND_REPO:-}" ]; then
  git -C "$GH_STUB_LAND_REPO" push -q "$GH_STUB_LAND_REMOTE" "$GH_STUB_LAND_BRANCH:refs/heads/main"
fi
exit 0
SH
    ;;
    refuse) cat <<'SH'
#!/usr/bin/env bash
printf 'ran pr=%s\n' "$1" >> "$MC_LOG"
echo "pr-merge: REFUSED: PR $1 is a one-way door and has no second approval" >&2
exit 7
SH
    ;;
  esac
}

# mc_repo <name> <key yes|no> <script ok|refuse> -- a bare remote plus a clone on main. With key=yes the
# .kit.toml sets [merge] command on the default branch; scripts/pr-merge.sh is committed either way.
mc_repo() {
  local name="$1" key="$2" mode="$3" work="$TMPD/mw-$1" bare="$TMPD/mbare-$1" clone="$TMPD/mclone-$1"
  mkdir -p "$work/scripts"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/a.txt"
  [ "$key" = yes ] && printf '[merge]\ncommand = "bash scripts/pr-merge.sh"\n' > "$work/.kit.toml"
  mc_script "$mode" > "$work/scripts/pr-merge.sh"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$bare"
  git clone -q "$bare" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  printf '%s\n' "$clone"
}

# mc_pr <clone> <bare> <n> -- branch feat/wrap with one commit, PR <n> open on it, its content already on
# the remote's main (standing in for the squash a merge performs on GitHub's side, as test-wrap-merge does).
mc_pr() {
  local clone="$1" bare="$2" n="$3" oid
  git -C "$clone" checkout -q -b feat/wrap origin/main
  echo "wrap the session" > "$clone/wrap-note.txt"
  git -C "$clone" add -A; git -C "$clone" commit -qm "wrap the session"
  oid="$(git -C "$clone" rev-parse feat/wrap)"
  git -C "$clone" checkout -q main
  git -C "$clone" push -q "$bare" "feat/wrap:refs/heads/main"
  export GH_STUB_OPEN_PRS="[{\"number\":$n,\"title\":\"wrap the session\",\"headRefName\":\"feat/wrap\"}]"
  export "GH_STUB_PR_$n=$(printf '{"number":%s,"title":"wrap the session","headRefName":"feat/wrap","headRefOid":"%s","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$n" "$oid")"
  MC_OID="$oid"
}

# ===========================================================================
echo "=== resolver: the committed .kit.toml on the default branch wins; a dirty tree and a PR branch do not ==="
# ===========================================================================
source "$KIT_DIR/lib/config/merge-command.sh"
R1="$(mc_repo r1 yes ok)"
cmd="$(kit_merge_command "$R1")"; rc=$?
chk "key committed on the default branch: found" "$rc"
chk_has "key committed on the default branch: the value" "$cmd" "bash scripts/pr-merge.sh"
R2="$(mc_repo r2 no ok)"
kit_merge_command "$R2" >/dev/null; rc=$?
chk "key unset: exit 1, nothing printed" "$([ "$rc" -eq 1 ]; echo $?)"
printf '[merge]\ncommand = "bash scripts/evil.sh"\n' > "$R2/.kit.toml"
kit_merge_command "$R2" >/dev/null; rc=$?
chk "key only in the working tree: ignored (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
git -C "$R2" checkout -q -b feat/edit; git -C "$R2" add -A; git -C "$R2" commit -qm "edit the merge command"
kit_merge_command "$R2" >/dev/null; rc=$?
chk "key committed only on a PR branch: ignored (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
printf '[merge]\ncommand = "bash scripts/evil.sh"\n' > "$R1/.kit.toml"
cmd="$(kit_merge_command "$R1")"
chk_has "key edited in the working tree: the committed value still wins" "$cmd" "bash scripts/pr-merge.sh"
git -C "$R1" checkout -q -- .kit.toml
OPD="$TMPD/mc-operator"; mkdir -p "$OPD"; printf '[merge]\ncommand = "bash ops/operator-merge.sh"\n' > "$OPD/kit.toml"
cmd="$(KIT_CONFIG_OPERATOR="$OPD" kit_merge_command "$R2")"
chk_has "operator kit.toml supplies it when the project sets none" "$cmd" "bash ops/operator-merge.sh"
cmd="$(KIT_CONFIG_OPERATOR="$OPD" kit_merge_command "$R1")"
chk_has "the project (committed) wins over the operator" "$cmd" "bash scripts/pr-merge.sh"
kit_merge_exec "$R1" "echo hi" "notanumber" >/dev/null 2>&1; rc=$?
chk "kit_merge_exec rejects a non-numeric PR (exit 64)" "$([ "$rc" -eq 64 ]; echo $?)"

# By slug: a gh shim answers the contents read; every other call goes to the harness stub.
mkdir -p "$TMPD/shim"
cat > "$TMPD/shim/gh" <<SH
#!/usr/bin/env bash
case "\$*" in
  *contents/.kit.toml*)
    case "\${MC_SLUG_MODE:-}" in
      set) printf '[merge]\ncommand = "bash scripts/pr-merge.sh"\n'; exit 0 ;;
      none) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      *) echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1 ;;
    esac ;;
esac
exec "$TMPD/stub/gh" "\$@"
SH
chmod +x "$TMPD/shim/gh"
cmd="$(PATH="$TMPD/shim:$PATH" MC_SLUG_MODE=set kit_merge_command_slug owner/name main)"; rc=$?
chk "slug: key set on the default branch: found" "$rc"
chk_has "slug: the value" "$cmd" "bash scripts/pr-merge.sh"
PATH="$TMPD/shim:$PATH" MC_SLUG_MODE=none kit_merge_command_slug owner/name main >/dev/null; rc=$?
chk "slug: no .kit.toml (404): unset, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
PATH="$TMPD/shim:$PATH" MC_SLUG_MODE=err kit_merge_command_slug owner/name main >/dev/null; rc=$?
chk "slug: any other read failure: exit 2, never read as unset" "$([ "$rc" -eq 2 ]; echo $?)"

# ===========================================================================
echo "=== wrap merge --apply: the project command merges, the plain merge is never called ==="
# ===========================================================================
M1="$(mc_repo m1 yes ok)"; mc_pr "$M1" "$TMPD/mbare-m1" 31
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$("$WRAP" merge --apply "$M1" 2>&1)"; rc=$?
chk "key set: merge --apply exits 0" "$rc"
chk_has "key set: the command is announced with the PR number" "$out" "running the project merge command: bash scripts/pr-merge.sh 31"
chk_has "key set: the verified merge is reported" "$out" "merged #31"
chk "key set: gh pr merge is never called" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "key set: the command ran exactly once" "$([ "$(grep -c '^ran ' "$MC_LOG")" -eq 1 ]; echo $?)"
chk_has "key set: the command got the PR number and the gated head" "$(cat "$MC_LOG")" "ran pr=31 env_pr=31 head=${MC_OID}"
chk_has "key set: the command ran in the repo checkout" "$(cat "$MC_LOG")" "cwd=$(cd "$M1" && pwd -P)"
chk "key set: GitHub was still asked whether the PR is MERGED" "$(grep -q '^pr view 31 .*state,mergeCommit' "$GH_STUB_CALLS"; echo $?)"

M2="$(mc_repo m2 yes refuse)"; mc_pr "$M2" "$TMPD/mbare-m2" 32
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$("$WRAP" merge --apply "$M2" 2>&1)"; rc=$?
chk "refusal: merge --apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "refusal: the command's own message is shown" "$out" "pr-merge: REFUSED: PR 32 is a one-way door and has no second approval"
chk_has "refusal: the verb names the refusal" "$out" "REFUSED merge #32: the project merge command exited 7; no other way to merge was tried"
chk "refusal: gh pr merge is never called (no fallback)" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "refusal: the command ran exactly once (no retry)" "$([ "$(grep -c '^ran ' "$MC_LOG")" -eq 1 ]; echo $?)"
chk_no "refusal: no merged line" "$out" "merged #32"

M3="$(mc_repo m3 no ok)"; mc_pr "$M3" "$TMPD/mbare-m3" 33
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$("$WRAP" merge --apply "$M3" 2>&1)"; rc=$?
chk "key unset: merge --apply exits 0" "$rc"
chk "key unset: gh pr merge is called exactly once, as before" "$([ "$(grep -c '^pr merge 33 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "key unset: the project script never runs" "$([ ! -s "$MC_LOG" ]; echo $?)"
chk_no "key unset: no project-command line" "$out" "project merge command"

M4="$(mc_repo m4 no ok)"; mc_pr "$M4" "$TMPD/mbare-m4" 34
printf '[merge]\ncommand = "bash scripts/pr-merge.sh"\n' > "$M4/.kit.toml"
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$("$WRAP" merge --apply "$M4" 2>&1)"; rc=$?
chk "key only in the working tree: the plain merge runs" "$([ "$(grep -c '^pr merge 34 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "key only in the working tree: the script never runs" "$([ ! -s "$MC_LOG" ]; echo $?)"

# by slug: no checkout to run it in
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$(PATH="$TMPD/shim:$PATH" MC_SLUG_MODE=set GH_STUB_REMOTE_DEFAULT=main "$WRAP" merge --apply --pr 34 --repo owner/name 2>&1)"; rc=$?
chk "slug, key set: merge refused (exit 2)" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "slug, key set: says why" "$out" "a merge by slug has no checkout to run it in"
chk "slug, key set: gh pr merge never called" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/shim:$PATH" MC_SLUG_MODE=err GH_STUB_REMOTE_DEFAULT=main "$WRAP" merge --apply --pr 34 --repo owner/name 2>&1)"; rc=$?
chk "slug, unreadable key: merge refused (exit 2)" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "slug, unreadable key: refuses the plain merge" "$out" "refusing to fall back to the plain merge"
chk "slug, unreadable key: gh pr merge never called" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
: > "$GH_STUB_CALLS"
PATH="$TMPD/shim:$PATH" MC_SLUG_MODE=none GH_STUB_REMOTE_DEFAULT=main "$WRAP" merge --apply --pr 34 --repo owner/name >/dev/null 2>&1
chk "slug, no .kit.toml (404): the plain merge runs" "$(grep -q '^pr merge 34 ' "$GH_STUB_CALLS"; echo $?)"

# ===========================================================================
echo "=== wrap land: the project command merges; a refusal leaves the PR open and tries nothing else ==="
# ===========================================================================
# land_fixture <name> <key> <script> -- a clone plus a worktree on feat/land with one commit.
land_fixture() {
  local c; c="$(mc_repo "$1" "$2" "$3")"
  git -C "$c" worktree add -q -b feat/land "$c/wt" main >/dev/null 2>&1
  echo land > "$c/wt/landed.txt"
  git -C "$c/wt" add -A; git -C "$c/wt" commit -qm "feat: the landed change"
  printf '%s\n' "$c"
}
L1="$(land_fixture l1 yes ok)"; L1WT="$(cd "$L1/wt" && pwd -P)"; L1TIP="$(git -C "$L1WT" rev-parse HEAD)"
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$L1WT" GH_STUB_LAND_REMOTE="$TMPD/mbare-l1" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$L1WT" 2>&1)"; rc=$?
chk "land, key set: exits 0" "$rc"
chk_has "land, key set: the command is announced" "$out" "running the project merge command: bash scripts/pr-merge.sh 42"
chk "land, key set: gh pr merge is never called" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk_has "land, key set: the command got the pushed head" "$(cat "$MC_LOG")" "ran pr=42 env_pr=42 head=${L1TIP}"
chk_has "land, key set: the tree is still verified" "$out" "tree verified"
chk "land, key set: the worktree is tidied away" "$([ ! -e "$L1WT" ]; echo $?)"

L2="$(land_fixture l2 yes refuse)"; L2WT="$(cd "$L2/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=43 GH_STUB_LAND_REPO="$L2WT" GH_STUB_LAND_REMOTE="$TMPD/mbare-l2" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$L2WT" 2>&1)"; rc=$?
chk "land, refusal: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land, refusal: the command's own message is shown" "$out" "pr-merge: REFUSED: PR 43 is a one-way door and has no second approval"
chk_has "land, refusal: the verb names it" "$out" "MERGE REFUSED #43: the project merge command exited 7; no other way to merge was tried, PR left open"
chk "land, refusal: gh pr merge is never called" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "land, refusal: the command ran once" "$([ "$(grep -c '^ran ' "$MC_LOG")" -eq 1 ]; echo $?)"
chk "land, refusal: the worktree is left in place" "$([ -d "$L2WT" ]; echo $?)"
chk_no "land, refusal: no merged line" "$out" "merged #43"

L3="$(land_fixture l3 yes refuse)"; L3WT="$(cd "$L3/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=44 GH_STUB_LAND_REPO="$L3WT" GH_STUB_LAND_REMOTE="$TMPD/mbare-l3" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  GH_STUB_PR_44='{"number":44,"title":"x","headRefName":"feat/land","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","statusCheckRollup":[],"headRefOid":"0000000000000000000000000000000000000000"}' \
  "$WRAP" land "$L3WT" 2>&1)"; rc=$?
chk "land, refusal on a CONFLICTING PR: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_no "land, refusal on a CONFLICTING PR: no merge-in cycle starts" "$out" "is CONFLICTING: merging"
chk "land, refusal on a CONFLICTING PR: the command ran once" "$([ "$(grep -c '^ran ' "$MC_LOG")" -eq 1 ]; echo $?)"

L4="$(land_fixture l4 no ok)"; L4WT="$(cd "$L4/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; : > "$MC_LOG"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=45 GH_STUB_LAND_REPO="$L4WT" GH_STUB_LAND_REMOTE="$TMPD/mbare-l4" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$L4WT" 2>&1)"; rc=$?
chk "land, key unset: exits 0" "$rc"
chk "land, key unset: gh pr merge is called once, as before" "$([ "$(grep -c '^pr merge 45 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "land, key unset: the script never runs" "$([ ! -s "$MC_LOG" ]; echo $?)"

# ===========================================================================
echo "=== stack-merge: the project command merges each link, a refusal stops the chain ==="
# ===========================================================================
SM="$KIT_DIR/lib/goal/stack-merge.sh"
mkdir -p "$TMPD/smgh"
cat > "$TMPD/smgh/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPD/sm-gh.log"
case "\$1 \$2" in
  "pr view") case "\$*" in *headRefName*) echo feat/link ;; *baseRefName*) echo main ;; esac ;;
  "pr list") : ;;
esac
exit 0
SH
chmod +x "$TMPD/smgh/gh"
# stack-merge reconciles the link's branch first; a repo where origin/<base> is already an
# ancestor of origin/<branch> skips straight to the merge.
S1="$(mc_repo s1 yes ok)"
git -C "$S1" push -q origin main:refs/heads/feat/link
git -C "$S1" fetch -q origin
: > "$TMPD/sm-gh.log"; : > "$MC_LOG"
out="$(cd "$S1" && PATH="$TMPD/smgh:$PATH" bash "$SM" next 51 2>&1)"; rc=$?
chk "stack-merge, key set: exits 0" "$rc"
chk_has "stack-merge, key set: merges through the project command" "$out" "through the project merge command: bash scripts/pr-merge.sh 51"
chk "stack-merge, key set: the command ran with the PR number" "$(grep -q '^ran pr=51' "$MC_LOG"; echo $?)"
chk "stack-merge, key set: gh pr merge never called" "$(grep -q '^pr merge' "$TMPD/sm-gh.log" && echo 1 || echo 0)"
out="$(cd "$S1" && PATH="$TMPD/smgh:$PATH" bash "$SM" next 51 --dry-run 2>&1)"; rc=$?
chk_has "stack-merge --dry-run, key set: prints the project command" "$out" "DRY: bash scripts/pr-merge.sh 51"

S2="$(mc_repo s2 yes refuse)"
git -C "$S2" push -q origin main:refs/heads/feat/link
git -C "$S2" fetch -q origin
: > "$TMPD/sm-gh.log"; : > "$MC_LOG"
out="$(cd "$S2" && PATH="$TMPD/smgh:$PATH" bash "$SM" chain 52 53 2>&1)"; rc=$?
chk "stack-merge, refusal: exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "stack-merge, refusal: the command's own message is shown" "$out" "pr-merge: REFUSED: PR 52 is a one-way door"
chk_has "stack-merge, refusal: names the stop" "$out" "the project merge command refused #52; no other way to merge was tried, stopping the chain"
chk "stack-merge, refusal: gh pr merge never called" "$(grep -q '^pr merge' "$TMPD/sm-gh.log" && echo 1 || echo 0)"
chk "stack-merge, refusal: the chain stops at the first link" "$([ "$(grep -c '^ran ' "$MC_LOG")" -eq 1 ]; echo $?)"

S3="$(mc_repo s3 no ok)"
git -C "$S3" push -q origin main:refs/heads/feat/link
git -C "$S3" fetch -q origin
: > "$TMPD/sm-gh.log"; : > "$MC_LOG"
out="$(cd "$S3" && PATH="$TMPD/smgh:$PATH" bash "$SM" next 54 2>&1)"; rc=$?
chk "stack-merge, key unset: exits 0" "$rc"
chk "stack-merge, key unset: gh pr merge called once, as before" "$([ "$(grep -c '^pr merge 54 --squash --delete-branch' "$TMPD/sm-gh.log")" -eq 1 ]; echo $?)"
chk "stack-merge, key unset: the script never runs" "$([ ! -s "$MC_LOG" ]; echo $?)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-merge-command: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-merge-command: all $PASS passed"

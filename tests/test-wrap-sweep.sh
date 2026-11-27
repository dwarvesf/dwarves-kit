#!/usr/bin/env bash
# test-wrap-sweep.sh -- sub-goal 01 (batched GraphQL + fallback + local refs) and
# sub-goal 02 (`wrap sweep` discovery, JSON contract wrap-sweep/1, per-repo locks,
# error isolation, `wrap.workspace_rm` seam, and post-merge sweep in `land` / `merge`).
# Shares tests/lib/wrap-stub.sh (offline local bare origins + stub gh only).
# modules under test (the test-affected cache key greps this line):
# lib/gate/branch-merged.sh lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-sweep.sh lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

export PATH="$TMPD/stub:$PATH"
export GH_STUB_CALLS="$TMPD/gh.calls"
export XDG_STATE_HOME="$TMPD/state"
export KIT_WRAP_SKIP_BUSY_CHECK=1
mkdir -p "$XDG_STATE_HOME"

sw_mk_repo() { # sw_mk_repo <path> [github_slug]
  local dir="$1" slug="${2:-}"
  local seed="$TMPD/seed-$(basename "$dir")-$$-$RANDOM"
  local bare="$TMPD/bare-$(basename "$dir")-$$-$RANDOM.git"
  mkdir -p "$seed" "$(dirname "$dir")"
  git -C "$seed" init -q
  git -C "$seed" config user.email t@t
  git -C "$seed" config user.name t
  git -C "$seed" config commit.gpgsign false
  git -C "$seed" symbolic-ref HEAD refs/heads/main
  echo base > "$seed/a.txt"
  git -C "$seed" add a.txt
  git -C "$seed" commit -qm "chore: base"
  git clone -q --bare "$seed" "$bare"
  git clone -q "$bare" "$dir"
  git -C "$dir" config user.email t@t
  git -C "$dir" config user.name t
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" remote set-head origin main >/dev/null 2>&1
  if [ -n "$slug" ]; then
    git -C "$dir" remote set-url origin "https://github.com/${slug}.git"
    git -C "$dir" config "url.${bare}.insteadOf" "https://github.com/${slug}.git"
  fi
  printf '%s\n' "$bare"
}

sw_validate_json() { # sw_validate_json <json_file>
  jq -e '
    .schema == "wrap-sweep/1" and
    (.mode == "dry-run" or .mode == "apply") and
    (.started_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    ((.duration_ms | type) == "number" and (.duration_ms >= 0)) and
    (.roots | type == "array") and
    (.repos | type == "array") and
    all(.repos[];
      ((.path | type) == "string") and
      ((.default_branch | type) == "string" or .default_branch == null) and
      ((.skipped | type) == "string" or .skipped == null) and
      ((.error | type) == "string" or .error == null) and
      (.rows | type == "array") and
      all(.rows[];
        (.kind == "worktree" or .kind == "branch" or .kind == "origin_branch") and
        ((.path | type) == "string" or .path == null) and
        ((.branch | type) == "string" or .branch == null) and
        (.verdict == "removed" or .verdict == "would_remove" or .verdict == "keep" or .verdict == "error") and
        ((.reason | type) == "string") and
        ((.pr | type) == "number" or .pr == null) and
        ((.pr_state == "MERGED" or .pr_state == "OPEN" or .pr_state == "CLOSED") or .pr_state == null) and
        ((.dirty | type) == "boolean" or .dirty == null) and
        ((.holder | type) == "number" or .holder == null) and
        ((.own_commits | type) == "number" or .own_commits == null) and
        ((.workspace_rm == "ok" or .workspace_rm == "failed" or .workspace_rm == "timeout") or .workspace_rm == null)
      )
    ) and
    (.summary | keys_unsorted | sort == ["errors","keep","removed","repos","skipped","would_remove"])
  ' "$1" >/dev/null 2>&1
}

# ===========================================================================
echo "=== 01 speed: batched GraphQL lookup + fallback parity ==="
# ===========================================================================
R_SPD="$TMPD_P/spd-repo"
BARE_SPD="$(sw_mk_repo "$R_SPD" "o/spd")"
git -C "$R_SPD" checkout -q -b feat/sq-wt main
echo sq > "$R_SPD/sq.txt"; git -C "$R_SPD" add sq.txt; git -C "$R_SPD" commit -qm "feat: sq-wt"
SQ_TIP="$(git -C "$R_SPD" rev-parse HEAD)"
git -C "$R_SPD" push -q origin feat/sq-wt
git -C "$R_SPD" checkout -q main
# Squash-equivalent doesn't hold because main adds a different commit; only gh proves it.
echo other > "$R_SPD/other.txt"; git -C "$R_SPD" add other.txt; git -C "$R_SPD" commit -qm "chore: advance"
git -C "$R_SPD" push -q origin main
git -C "$R_SPD" worktree add -q "$TMPD_P/wt-sq" feat/sq-wt

git -C "$R_SPD" checkout -q -b feat/unmerged main
echo u > "$R_SPD/u.txt"; git -C "$R_SPD" add u.txt; git -C "$R_SPD" commit -qm "feat: unmerged"
git -C "$R_SPD" checkout -q main

export GH_STUB_MERGED_ALL="[{\"number\":55,\"headRefName\":\"feat/sq-wt\",\"headRefOid\":\"${SQ_TIP}\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\",\"isCrossRepository\":false}]"
export GH_STUB_MERGED_feat_sq_wt="$GH_STUB_MERGED_ALL"
export GH_STUB_OPEN_PRS='[{"number":56,"title":"unmerged","headRefName":"feat/unmerged","baseRefName":"main"}]'

: > "$GH_STUB_CALLS"
out_gql="$(GH_STUB_GRAPHQL=1 "$WRAP" apply --worktrees "$R_SPD" 2>&1)"; rc_gql=$?
calls_gql="$(cat "$GH_STUB_CALLS")"
chk "speed: batched graphql apply exits 0" "$rc_gql"
chk "speed: exactly 1 gh auth status call" "$([ "$(printf '%s\n' "$calls_gql" | grep -c '^auth status')" -eq 1 ]; echo $?)"
chk "speed: exactly 1 gh api graphql call" "$([ "$(printf '%s\n' "$calls_gql" | grep -c '^api graphql')" -eq 1 ]; echo $?)"
chk "speed: 0 gh pr list --state merged calls" "$([ "$(printf '%s\n' "$calls_gql" | grep -c 'pr list.*--state merged')" -eq 0 ]; echo $?)"

: > "$GH_STUB_CALLS"
out_fb="$(GH_STUB_GRAPHQL_RC=1 "$WRAP" apply --worktrees "$R_SPD" 2>&1)"; rc_fb=$?
calls_fb="$(cat "$GH_STUB_CALLS")"
chk "speed: fallback apply exits 0" "$rc_fb"
chk "speed: fallback produces identical output to batched path" "$([ "$out_gql" = "$out_fb" ]; echo $?)"
chk "speed: fallback invoked gh pr list --state merged" "$([ "$(printf '%s\n' "$calls_fb" | grep -c 'pr list.*--state merged')" -ge 1 ]; echo $?)"

# ===========================================================================
echo "=== 02 discovery: depth 0/1/2, non-repo, wrap.sweep_roots fence ==="
# ===========================================================================
EST="$TMPD_P/estate"
mkdir -p "$EST/org1/app1" "$EST/direct-clean" "$EST/empty-dir"
B_APP1="$(sw_mk_repo "$EST/org1/app1" "org1/app1")"
B_DIR="$(sw_mk_repo "$EST/direct-clean")"
git -C "$EST/org1/app1" checkout -q -b feat/merged-b main
echo b > "$EST/org1/app1/b.txt"; git -C "$EST/org1/app1" add b.txt; git -C "$EST/org1/app1" commit -qm "feat: b"
git -C "$EST/org1/app1" checkout -q main
git -C "$EST/org1/app1" merge -q --no-ff --no-edit feat/merged-b
git -C "$EST/org1/app1" push -q origin main
git -C "$EST/org1/app1" worktree add -q "$EST/wt-app1-merged" feat/merged-b

# Project .kit.toml must never supply wrap.sweep_roots
PROJ_SW="$TMPD_P/proj-sweep"
mkdir -p "$PROJ_SW"
printf '[wrap]\nsweep_roots = "%s"\n' "$EST" > "$PROJ_SW/.kit.toml"
err_proj="$(cd "$PROJ_SW" && KIT_PROJECT_ROOT="$PROJ_SW" "$WRAP" sweep --json 2>&1)"; rc=$?
chk "project .kit.toml cannot set wrap.sweep_roots (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "usage error names wrap.sweep_roots" "$err_proj" "wrap.sweep_roots"
chk_no "usage error prints no JSON" "$err_proj" "wrap-sweep/1"

# Operator kit.toml sets wrap.sweep_roots
OP_CFG="$TMPD_P/op-cfg"; mkdir -p "$OP_CFG"
printf '[wrap]\nsweep_roots = "%s %s"\n' "$EST" "$EST/empty-dir" > "$OP_CFG/kit.toml"
SW_JSON="$TMPD/sweep-disc.json"
KIT_CONFIG_OPERATOR="$OP_CFG" GH_STUB_GRAPHQL=1 "$WRAP" sweep --worktrees --json > "$SW_JSON" 2>"$TMPD/sweep-disc.err"; rc=$?
chk "sweep --worktrees --json exits 0" "$rc"
chk "sweep JSON passes wrap-sweep/1 schema check" "$(sw_validate_json "$SW_JSON"; echo $?)"
chk "sweep JSON sees app1 and skipped empty-dir" \
  "$(jq -e '([.repos[] | select(.path | endswith("/app1"))] | length) == 1 and ([.repos[] | select(.skipped == "not a git repo")] | length) == 1' "$SW_JSON" >/dev/null 2>&1; echo $?)"
chk "sweep JSON filtered out clean repo direct-clean" \
  "$(jq -e '([.repos[] | select(.path | endswith("/direct-clean"))] | length) == 0' "$SW_JSON" >/dev/null 2>&1; echo $?)"
chk "sweep JSON app1 worktree verdict is would_remove" \
  "$(jq -e '.repos[] | select(.path | endswith("/app1")) | .rows[] | select(.kind == "worktree") | .verdict == "would_remove"' "$SW_JSON" >/dev/null 2>&1; echo $?)"

# Explicit clean repo root is still included when named directly
SW_EX="$TMPD/sweep-explicit.json"
"$WRAP" sweep --json "$EST/direct-clean" > "$SW_EX" 2>/dev/null; rc=$?
chk "explicit clean repo exits 0" "$rc"
chk "explicit clean repo appears in repos[]" \
  "$(jq -e '(.repos | length) == 1 and .repos[0].skipped == null and (.repos[0].rows | length) == 0' "$SW_EX" >/dev/null 2>&1; echo $?)"

# ===========================================================================
echo "=== 02 locking: skipped=locked, exit 3 when all locked, signal cleanup ==="
# ===========================================================================
if command -v shasum >/dev/null 2>&1; then
  sha_app1="$(printf '%s' "$EST/org1/app1" | shasum -a 1 | awk '{print $1}')"
else
  sha_app1="$(printf '%s' "$EST/org1/app1" | sha1sum | awk '{print $1}')"
fi
LOCK_DIR="$XDG_STATE_HOME/wrap/locks/$sha_app1"
mkdir -p "$LOCK_DIR"
SW_LOCK="$TMPD/sweep-lock.json"
"$WRAP" sweep --worktrees --json "$EST/org1/app1" > "$SW_LOCK" 2>/dev/null; rc=$?
chk "all-locked sweep exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk "all-locked JSON is valid and says skipped=locked" \
  "$(sw_validate_json "$SW_LOCK" && jq -e '.repos[0].skipped == "locked" and .summary.skipped == 1' "$SW_LOCK" >/dev/null 2>&1; echo $?)"

# Mixed: one locked + one unlocked -> exit 0
SW_MIX="$TMPD/sweep-mix.json"
"$WRAP" sweep --worktrees --json "$EST/org1/app1" "$EST/direct-clean" > "$SW_MIX" 2>/dev/null; rc=$?
chk "mixed locked+unlocked sweep exits 0" "$rc"
chk "mixed JSON reports skipped=1 and 2 repos" \
  "$(jq -e '.summary.repos == 2 and .summary.skipped == 1' "$SW_MIX" >/dev/null 2>&1; echo $?)"
rm -rf "$LOCK_DIR"

# SIGTERM cleanup: killing an active sweep cleans up its lock directory
SIG_BIN="$TMPD/sig-bin"; mkdir -p "$SIG_BIN"
cat > "$SIG_BIN/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = auth ] && exit 0
sleep 10
STUB
chmod +x "$SIG_BIN/gh"
PATH="$SIG_BIN:$PATH" "$WRAP" sweep --worktrees --json "$EST/org1/app1" >/dev/null 2>&1 &
sw_pid=$!
w_i=0
while [ ! -d "$LOCK_DIR" ] && [ "$w_i" -lt 40 ]; do sleep 0.05; w_i=$(( w_i + 1 )); done
chk "active sweep created lock dir" "$([ -d "$LOCK_DIR" ]; echo $?)"
kill -TERM "$sw_pid" 2>/dev/null || true
wait "$sw_pid" 2>/dev/null || true
chk "SIGTERM cleaned up lock dir" "$([ ! -d "$LOCK_DIR" ]; echo $?)"

# ===========================================================================
echo "=== 02 per-repo error isolation: broken remote -> exit 2, sibling still runs ==="
# ===========================================================================
R_BROKEN="$TMPD_P/broken-repo"
sw_mk_repo "$R_BROKEN" >/dev/null
git -C "$R_BROKEN" remote set-url origin "$TMPD_P/nonexistent-remote.git"
SW_ERR="$TMPD/sweep-err.json"
GH_STUB_GRAPHQL=1 "$WRAP" sweep --worktrees --json "$R_BROKEN" "$EST/org1/app1" > "$SW_ERR" 2>/dev/null; rc=$?
chk "broken repo + healthy sibling exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk "broken repo JSON validates and has error=git fetch failed" \
  "$(sw_validate_json "$SW_ERR" && jq -e '([.repos[] | select(.error != null and (.error | startswith("git fetch failed:")))] | length) == 1 and .summary.errors == 1' "$SW_ERR" >/dev/null 2>&1; echo $?)"
chk "healthy sibling still produced rows despite broken repo" \
  "$(jq -e '.repos[] | select(.path | endswith("/app1")) | (.rows | length) >= 1' "$SW_ERR" >/dev/null 2>&1; echo $?)"

# ===========================================================================
echo "=== 02 apply + wrap.workspace_rm seam (ok / failed / timeout / root-only) ==="
# ===========================================================================
SEAM_LOG="$TMPD/workspace_rm.log"
SEAM_SCRIPT="$TMPD/wrm-ok.sh"
cat > "$SEAM_SCRIPT" <<EOF
#!/usr/bin/env bash
printf '%s\t%s\n' "\$1" "\$2" >> "$SEAM_LOG"
exit 0
EOF
chmod +x "$SEAM_SCRIPT"

cat > "$OP_CFG/kit.toml" <<EOF
[wrap]
workspace_rm = "$SEAM_SCRIPT"
EOF

# Project .kit.toml must not override workspace_rm
printf '[wrap]\nworkspace_rm = "echo pwned"\n' > "$EST/org1/app1/.kit.toml"

SW_APP="$TMPD/sweep-apply.json"
KIT_CONFIG_OPERATOR="$OP_CFG" KIT_PROJECT_ROOT="$EST/org1/app1" GH_STUB_GRAPHQL=1 "$WRAP" sweep --apply --worktrees --json "$EST/org1/app1" > "$SW_APP" 2>/dev/null; rc=$?
chk "sweep --apply --worktrees exits 0" "$rc"
chk "sweep --apply JSON validates and reports removed + workspace_rm=ok" \
  "$(sw_validate_json "$SW_APP" && jq -e '.mode == "apply" and .summary.removed >= 1 and (.repos[0].rows[] | select(.kind == "worktree") | .verdict == "removed" and .workspace_rm == "ok")' "$SW_APP" >/dev/null 2>&1; echo $?)"
chk "workspace_rm seam fired once with <wt> <repo>" \
  "$([ "$(wc -l < "$SEAM_LOG" | tr -d ' ')" -eq 1 ] && grep -qF "$EST/wt-app1-merged	$EST/org1/app1" "$SEAM_LOG"; echo $?)"
chk "lock was cleaned up after sweep --apply" "$([ ! -d "$LOCK_DIR" ]; echo $?)"

# Failing seam -> workspace_rm="failed", removal stands, exit 0
SEAM_FAIL="$TMPD/wrm-fail.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SEAM_FAIL"; chmod +x "$SEAM_FAIL"
printf '[wrap]\nworkspace_rm = "%s"\n' "$SEAM_FAIL" > "$OP_CFG/kit.toml"
git -C "$EST/org1/app1" checkout -q -b feat/merged-fail main
echo bf > "$EST/org1/app1/bf.txt"; git -C "$EST/org1/app1" add bf.txt; git -C "$EST/org1/app1" commit -qm "feat: bf"
git -C "$EST/org1/app1" checkout -q main
git -C "$EST/org1/app1" merge -q --no-ff --no-edit feat/merged-fail
git -C "$EST/org1/app1" push -q origin main
git -C "$EST/org1/app1" worktree add -q "$EST/wt-app1-fail" feat/merged-fail
SW_FAIL="$TMPD/sweep-seam-fail.json"
KIT_CONFIG_OPERATOR="$OP_CFG" "$WRAP" sweep --apply --worktrees --json "$EST/org1/app1" > "$SW_FAIL" 2>/dev/null; rc=$?
chk "failing workspace_rm still exits 0" "$rc"
chk "failing workspace_rm still removed worktree and recorded failed" \
  "$([ ! -e "$EST/wt-app1-fail" ] && jq -e '.repos[0].rows[] | select(.kind == "worktree") | .verdict == "removed" and .workspace_rm == "failed"' "$SW_FAIL" >/dev/null 2>&1; echo $?)"

# Timing out seam -> workspace_rm="timeout", removal stands, exit 0
SEAM_TO="$TMPD/wrm-to.sh"
printf '#!/usr/bin/env bash\nsleep 5\n' > "$SEAM_TO"; chmod +x "$SEAM_TO"
printf '[wrap]\nworkspace_rm = "%s"\n' "$SEAM_TO" > "$OP_CFG/kit.toml"
git -C "$EST/org1/app1" checkout -q -b feat/merged-to main
echo bt > "$EST/org1/app1/bt.txt"; git -C "$EST/org1/app1" add bt.txt; git -C "$EST/org1/app1" commit -qm "feat: bt"
git -C "$EST/org1/app1" checkout -q main
git -C "$EST/org1/app1" merge -q --no-ff --no-edit feat/merged-to
git -C "$EST/org1/app1" push -q origin main
git -C "$EST/org1/app1" worktree add -q "$EST/wt-app1-to" feat/merged-to
SW_TO="$TMPD/sweep-seam-to.json"
WRAP_WORKSPACE_RM_TIMEOUT=1 KIT_CONFIG_OPERATOR="$OP_CFG" "$WRAP" sweep --apply --worktrees --json "$EST/org1/app1" > "$SW_TO" 2>/dev/null; rc=$?
chk "timed-out workspace_rm still exits 0" "$rc"
chk "timed-out workspace_rm still removed worktree and recorded timeout" \
  "$([ ! -e "$EST/wt-app1-to" ] && jq -e '.repos[0].rows[] | select(.kind == "worktree") | .verdict == "removed" and .workspace_rm == "timeout"' "$SW_TO" >/dev/null 2>&1; echo $?)"

# ===========================================================================
echo "=== 02 post-merge sweep in wrap land and wrap merge --apply ==="
# ===========================================================================
# 1) wrap land removes a sibling already-merged worktree and triggers workspace_rm
R_PM="$TMPD_P/pm-land"
B_PM="$(sw_mk_repo "$R_PM" "o/pm")"
git -C "$R_PM" checkout -q -b feat/sibling-done main
echo sib > "$R_PM/sib.txt"; git -C "$R_PM" add sib.txt; git -C "$R_PM" commit -qm "feat: sib"
git -C "$R_PM" checkout -q main
git -C "$R_PM" merge -q --no-ff --no-edit feat/sibling-done
git -C "$R_PM" push -q origin main
git -C "$R_PM" worktree add -q "$TMPD_P/wt-sibling" feat/sibling-done

git -C "$R_PM" worktree add -q -b feat/to-land "$TMPD_P/wt-to-land" main
echo landme > "$TMPD_P/wt-to-land/landme.txt"
git -C "$TMPD_P/wt-to-land" add landme.txt
git -C "$TMPD_P/wt-to-land" commit -qm "feat: landme"

: > "$SEAM_LOG"
printf '[wrap]\nworkspace_rm = "%s"\n' "$SEAM_SCRIPT" > "$OP_CFG/kit.toml"
body_f="$TMPD/land-body.md"; printf 'Test body\n' > "$body_f"
out_land="$(KIT_CONFIG_OPERATOR="$OP_CFG" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_LAND_REPO="$TMPD_P/wt-to-land" GH_STUB_LAND_REMOTE="$B_PM" \
  GH_STUB_LAND_BRANCH=feat/to-land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$TMPD_P/wt-to-land" --title "feat: landme" --body-file "$body_f" 2>&1)"; rc=$?
chk "wrap land exits 0 with post-merge sweep" "$rc"
chk "wrap land keeps LAND: as last stdout line" "$(printf '%s\n' "$out_land" | tail -1 | grep -q '^LAND: merged #'; echo $?)"
chk "post-merge sweep after land removed sibling merged worktree" "$([ ! -e "$TMPD_P/wt-sibling" ]; echo $?)"
chk "workspace_rm fired for both landed and sibling worktrees" "$([ "$(wc -l < "$SEAM_LOG" | tr -d ' ')" -eq 2 ]; echo $?)"

# 2) wrap merge --apply removes a sibling already-merged worktree
R_PMM="$TMPD_P/pm-merge"
B_PMM="$(sw_mk_repo "$R_PMM" "o/pmm")"
git -C "$R_PMM" checkout -q -b feat/sib-merge main
echo sm > "$R_PMM/sm.txt"; git -C "$R_PMM" add sm.txt; git -C "$R_PMM" commit -qm "feat: sm"
git -C "$R_PMM" checkout -q main
git -C "$R_PMM" merge -q --no-ff --no-edit feat/sib-merge
git -C "$R_PMM" push -q origin main
git -C "$R_PMM" worktree add -q "$TMPD_P/wt-sib-merge" feat/sib-merge

git -C "$R_PMM" checkout -q -b feat/pr-open main
echo prm > "$R_PMM/prm.txt"; git -C "$R_PMM" add prm.txt; git -C "$R_PMM" commit -qm "feat: prm"
PRM_OID="$(git -C "$R_PMM" rev-parse HEAD)"
git -C "$R_PMM" push -q origin feat/pr-open
git -C "$R_PMM" checkout -q main
# Advance bare remote on merge when gh pr merge runs? In stub, state,mergeCommit reads bare HEAD,
# so push feat/pr-open onto bare main as squash-test or set GH_STUB_VIEW_STATE + tree verify:
git -C "$B_PMM" branch -f main feat/pr-open

export GH_STUB_OPEN_PRS="[{\"number\":77,\"title\":\"feat: prm\",\"headRefName\":\"feat/pr-open\",\"baseRefName\":\"main\",\"headRefOid\":\"${PRM_OID}\",\"isDraft\":false}]"
export GH_STUB_PR_77="{\"number\":77,\"state\":\"OPEN\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"headRefName\":\"feat/pr-open\",\"headRefOid\":\"${PRM_OID}\",\"baseRefName\":\"main\",\"isDraft\":false,\"isCrossRepository\":false,\"author\":{\"login\":\"me\"},\"statusCheckRollup\":[]}"
out_merge="$(KIT_CONFIG_OPERATOR="$OP_CFG" "$WRAP" merge --apply --pr 77 "$R_PMM" 2>&1)"; rc=$?
chk "wrap merge --apply exits 0 with post-merge sweep" "$rc"
chk "post-merge sweep after merge removed sibling merged worktree" "$([ ! -e "$TMPD_P/wt-sib-merge" ]; echo $?)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-sweep: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-sweep: all $PASS passed"

#!/usr/bin/env bash
# test-wrap-session.sh -- the read-only session gather: schema, PR checks, deploy state,
# the sweep seam and its apply dry-run fallback, and the no-write contract.
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-session.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

jqok() { printf '%s' "$2" | jq -e "$3" >/dev/null 2>&1; chk "$1" "$?"; }

# ===========================================================================
echo "=== usage and invalid repos ==="
# ===========================================================================
out="$("$WRAP" session 2>&1)"; rc=$?
chk "session with no arguments exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "session usage names --json" "$out" "session --json"
out="$("$WRAP" session --json "$TMPD/no-such-repo" 2>/dev/null)"; rc=$?
chk "an invalid repo still exits 0 with JSON" "$rc"
jqok "the invalid repo is a row, not a crash" "$out" '.schema == "wrap-session/1" and .repos[0].is_repo == false and .repos[0].github_slug == null and .summary.invalid_repos == 1'

# ===========================================================================
echo "=== one fixture repo through the sweep JSON seam ==="
# ===========================================================================
make_clone session-main rmain main main
clone="$TMPD/clone-session-main"
mkdir -p "$clone/_meta"
cat > "$clone/_meta/BACKLOG.md" <<'BOARD'
| ID | Title | State |
|---|---|---|
| DK-101 | wrap session gather | executing |
| DK-102 | old shipped row | shipped |
BOARD
fake="$TMPD/fake-wrap"
cat > "$fake" <<FAKE
#!/usr/bin/env bash
if [ "\${1:-}" = sweep ]; then
  cat "$KIT_DIR/tests/fixtures/wrap-sweep-fixture.json"
  exit 0
fi
echo "unexpected fake wrap call: \$*" >&2
exit 64
FAKE
chmod +x "$fake"
before="$( { git -C "$clone" branch --show-current; git -C "$clone" rev-parse HEAD; git -C "$clone" status --short; git -C "$clone" worktree list --porcelain; } 2>/dev/null )"
out="$(WRAP_SESSION_WRAP_BIN="$fake" GH_STUB_PR_7='{"number":7,"title":"wrap the session","headRefName":"feat/wrap","headRefOid":"deadbeefcafe1234567890abcdef1234567890ab","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"},{"name":"lint","conclusion":"SKIPPED"}],"isDraft":false}' "$WRAP" session --json "$clone" 2>"$TMPD/session.err")"; rc=$?
after="$( { git -C "$clone" branch --show-current; git -C "$clone" rev-parse HEAD; git -C "$clone" status --short; git -C "$clone" worktree list --porcelain; } 2>/dev/null )"
chk "session exits 0" "$rc"
jqok "stdout is one wrap-session document" "$out" 'type == "object" and .schema == "wrap-session/1"'
jqok "the document carries the follow mode config" "$out" '.config.follow_mode != null and .config.build_lanes != null'
jqok "the checkout row carries branch counts and worktrees" "$out" '.repos[0].checkout.branch == "main" and (.repos[0].checkout.ahead|type) == "number" and (.repos[0].checkout.worktrees|length) >= 3'
jqok "active board rows are present and terminal rows are omitted" "$out" '[.repos[0].board.rows[].id] == ["DK-101"]'
jqok "handoff state is structured" "$out" '(.repos[0].handoffs.lines|type) == "array" and (.repos[0].handoffs.exit_code|type) == "number"'
jqok "the own open PR carries its check totals and gate" "$out" '.repos[0].pull_requests.open_own[0].number == 7 and .repos[0].pull_requests.open_own[0].checks.total == 2 and .repos[0].pull_requests.open_own[0].gate == "OK"'
jqok "the sweep JSON seam is used unchanged" "$out" '.repos[0].sweep.format == "json" and .repos[0].sweep.document.schema == "wrap-sweep/1" and .repos[0].sweep.document.summary.would_remove == 3'
jqok "the top summary aggregates PRs and sweep rows" "$out" '.summary.repos == 1 and .summary.open_own_prs == 1 and .summary.sweep_would_remove == 3 and .summary.sweep_rows == 6'
chk "the gather changes neither checkout state nor worktree inventory" "$([ "$before" = "$after" ]; echo $?)"
chk_no "the gather does not print human lines on stdout" "$out" "SKIP worktree"

# ===========================================================================
echo "=== pending checks stay data, never a block ==="
# ===========================================================================
pending_pr='{"number":7,"title":"wrap the session","headRefName":"feat/wrap","headRefOid":"deadbeefcafe1234567890abcdef1234567890ab","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"UNSTABLE","reviewDecision":"APPROVED","statusCheckRollup":[{"status":"IN_PROGRESS"},{"conclusion":"SUCCESS"}],"isDraft":false}'
out="$(WRAP_SESSION_WRAP_BIN="$fake" GH_STUB_PR_7="$pending_pr" "$WRAP" session --json "$clone" 2>/dev/null)"; rc=$?
chk "a pending PR still exits 0" "$rc"
jqok "pending checks are counted in the document" "$out" '.repos[0].pull_requests.open_own[0].checks.pending == 1 and .summary.pending_prs == 1'

# ===========================================================================
echo "=== deploy state on a GitHub slug ==="
# ===========================================================================
make_clone session-deploy rmain main main
dep="$TMPD/clone-session-deploy"
git -C "$dep" remote set-url origin https://github.com/acme/widgets.git
mkdir -p "$TMPD/gh-deploy"
cat > "$TMPD/gh-deploy/gh" <<'GHDEP'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "api repos/acme/widgets/commits/"*"/check-runs")
    printf '%s\n' '{"check_runs":[{"name":"deploy","status":"completed","conclusion":"success","html_url":"https://example.test/run/1","id":2}]}'
    exit 0 ;;
esac
exec "${GH_DEPLOY_DELEGATE}" "$@"
GHDEP
chmod +x "$TMPD/gh-deploy/gh"
merged='[{"number":9,"title":"landed","headRefName":"feat/landed","mergedAt":"2026-01-02T00:00:00Z","mergeCommit":{"oid":"abc123"},"author":{"login":"me"}}]'
out="$(PATH="$TMPD/gh-deploy:$PATH" GH_DEPLOY_DELEGATE="$TMPD/stub/gh" GH_STUB_MERGED_ALL="$merged" WRAP_SESSION_WRAP_BIN="$fake" "$WRAP" session --json "$dep" 2>/dev/null)"; rc=$?
chk "the deploy gather exits 0" "$rc"
jqok "a successful check-run on the merge sha is deploy success" "$out" '.repos[0].pull_requests.merged_recent[0].number == 9 and .repos[0].pull_requests.deploys[0].state == "success" and .repos[0].pull_requests.deploys[0].merge_sha == "abc123"'
jqok "the GitHub slug and PR links are first-class fields" "$out" '.repos[0].github_slug == "acme/widgets" and .repos[0].pull_requests.open_own[0].url == "https://github.com/acme/widgets/pull/7" and .repos[0].pull_requests.merged_recent[0].url == "https://github.com/acme/widgets/pull/9"'

# ===========================================================================
echo "=== fallback and degraded gh states ==="
# ===========================================================================
gd_common="$(git -C "$clone" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
refs_before="$(git -C "$clone" for-each-ref 2>/dev/null)"
index_before="$(stat -c %Y "$clone/.git/index" 2>/dev/null || stat -f %m "$clone/.git/index" 2>/dev/null)"
if [ -e "$gd_common/FETCH_HEAD" ]; then fh_before=yes; else fh_before=no; fi
out="$("$WRAP" session --json "$clone" 2>/dev/null)"; rc=$?
refs_after="$(git -C "$clone" for-each-ref 2>/dev/null)"
index_after="$(stat -c %Y "$clone/.git/index" 2>/dev/null || stat -f %m "$clone/.git/index" 2>/dev/null)"
if [ -e "$gd_common/FETCH_HEAD" ]; then fh_after=yes; else fh_after=no; fi
chk "the fallback gather exits 0" "$rc"
jqok "with wrap sweep present the gather reads its JSON (run with --no-fetch)" "$out" '.repos[0].sweep.format == "json" and .repos[0].sweep.document.schema == "wrap-sweep/1"'
nosweep="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"; printf '#!/bin/sh\nexit 64\n' > "$nosweep"; chmod +x "$nosweep"
out_ns="$(WRAP_SESSION_WRAP_BIN="$nosweep" "$WRAP" session --json "$clone" 2>/dev/null)"; rm -f "$nosweep"
jqok "without wrap sweep the row falls back to read-only inventory text" "$out_ns" '.repos[0].sweep.format == "text" and .repos[0].sweep.document == null and (.repos[0].sweep.text|type) == "string" and (.repos[0].sweep.text | contains("read-only; no fetch"))'
chk "the fallback gather changes no ref" "$([ "$refs_before" = "$refs_after" ]; echo $?)"
chk "the fallback gather neither creates nor removes FETCH_HEAD" "$([ "$fh_before" = "$fh_after" ]; echo $?)"
chk "the fallback gather does not refresh the index" "$([ "$index_before" = "$index_after" ]; echo $?)"
out="$(WRAP_SESSION_WRAP_BIN="$fake" GH_STUB_UNAUTH=1 "$WRAP" session --json "$clone" 2>/dev/null)"; rc=$?
chk "an unauthenticated gh still exits 0" "$rc"
jqok "gh degradation is a field, not a failure" "$out" '.repos[0].pull_requests.gh_state == "unauthenticated" and .repos[0].pull_requests.open_own == []'

out="$(WRAP_SESSION_WRAP_BIN="$fake" "$WRAP" session --json --follow-mode all "$clone" 2>/dev/null)"; rc=$?
chk "the follow-mode override exits 0" "$rc"
jqok "the follow-mode override lands in config" "$out" '.config.follow_mode == "all" and (.config.follow_lanes | test("full"))'

# ===========================================================================
echo "=== live writer facts stay per worktree ==="
# ===========================================================================
make_clone writers rmain main main
wclone="$TMPD/clone-writers"
wself="$TMPD/wt-writers-clean"
wdirty="$TMPD/wt-writers-dirty"
now_epoch="$(date +%s)"
since_epoch=$(( now_epoch - 3600 ))
old_epoch=$(( now_epoch - 86400 ))
echo old >> "$wdirty/wt-dirty.txt"
git -C "$wdirty" add wt-dirty.txt
GIT_AUTHOR_DATE="@$old_epoch +0000" GIT_COMMITTER_DATE="@$old_epoch +0000" git -C "$wdirty" commit -qm old-write
out="$("$WRAP" session --writers --since "$since_epoch" --self "$wself" "$wclone" 2>/dev/null)"; rc=$?
chk "writers exits 0" "$rc"
jqok "writers excludes the session worktree and keeps per-worktree reflog truth" "$out" '.schema == "wrap-writers/1" and (.since|type) == "number" and (.worktrees as $w | ([$w[] | select(.path | endswith("wt-writers-clean"))] | length) == 0 and ([$w[] | select(.branch == "wt-dirty") | .reflog.newer_than_since][0]) == false and ([$w[] | select(.branch == "main") | .reflog.newer_than_since][0]) == true)'
jqok "the old worktree reflog is not hidden by a newer global maximum" "$out" '([.worktrees[] | select(.branch == "wt-dirty") | .reflog.latest_at][0]) < .since'

wgda="$(git -C "$wclone" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
: > "$wgda/index.lock"
out="$("$WRAP" session --writers --since "$since_epoch" --self "$wself" "$wclone" 2>/dev/null)"; rc=$?
text="$("$WRAP" session --writers --text --since "$since_epoch" --self "$wself" "$wclone" 2>/dev/null)"; trc=$?
rm -f "$wgda/index.lock"
chk "writers still exits 0 with an index lock present" "$rc"
jqok "writers reports the lock on its own worktree row" "$out" '([.worktrees[] | select(.branch == "main") | .index_lock.present][0]) == true and ([.worktrees[] | select(.branch == "main") | .foreign_activity][0]) == true and .foreign_activity == true'
chk "writers text fallback exits 0" "$trc"
json_rows="$(printf '%s' "$out" | jq '.worktrees | length' 2>/dev/null)"
text_rows="$(printf '%s\n' "$text" | grep -c '^writer path=')"
chk "writers text fallback carries every worktree row" "$([ "$json_rows" = "$text_rows" ]; echo $?)"
chk_has "writers text fallback carries the lock fact" "$text" "index_lock_present=true"
chk_has "writers text fallback carries the per-row reflog fact" "$text" "reflog_newer_than_since=false"

# ===========================================================================
echo "=== writer marks ignore own writes and never hide the main checkout ==="
# ===========================================================================
wmark="$TMPD/writer-mark.json"
wown="$TMPD/wt-writers-own"
git -C "$wclone" branch own-merge
git -C "$wclone" worktree add "$wown" own-merge >/dev/null 2>&1
echo own-merge > "$wown/own-merge.txt"
git -C "$wown" add own-merge.txt
git -C "$wown" commit -qm own-merge
"$WRAP" session --writers --mark "$wmark" --self "$wself" --self "$wown" "$wclone" >/dev/null 2>&1; rc=$?
chk "writing the writer mark exits 0" "$rc"
jqok "the mark stores every worktree reflog identity" "$(cat "$wmark")" '.schema == "wrap-writer-mark/1" and ([.worktrees[].path] | length) == 5 and ([.worktrees[] | select(.reflog.head != null and .reflog.digest != null)] | length) == 5'
git -C "$wclone" merge -q --ff-only own-merge
out="$("$WRAP" session --writers --check-mark "$wmark" --self "$wself" --self "$wown" "$wclone" 2>/dev/null)"; rc=$?
chk "the pre-mark own-write control exits 0" "$rc"
jqok "an own main-checkout write is visible before the mark moves" "$out" '.foreign_activity == true and ([.worktrees[] | select(.branch == "main" and .reflog.changed_since_mark == true)] | length) == 1'
"$WRAP" session --writers --mark "$wmark" --self "$wself" --self "$wown" "$wclone" >/dev/null 2>&1
out="$("$WRAP" session --writers --check-mark "$wmark" --self "$wself" --self "$wown" "$wclone" 2>/dev/null)"; rc=$?
chk "the own-merge re-check exits 0" "$rc"
jqok "an own merge then a fresh mark gives no foreign activity" "$out" '.foreign_activity == false and ([.worktrees[] | select(.branch == "main" and .reflog.changed_since_mark == false and .foreign_activity == false)] | length) == 1'
jqok "two --self paths are both excluded" "$out" '([.worktrees[] | select(.path | endswith("wt-writers-clean") or endswith("wt-writers-own"))] | length) == 0 and (.self | length) == 2'

wgda="$(git -C "$wclone" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
: > "$wgda/index.lock"
out="$(cd "$wclone" && "$WRAP" session --writers --check-mark "$wmark" "$wclone" 2>/dev/null)"; rc=$?
rm -f "$wgda/index.lock"
chk "the main-checkout lock check exits 0" "$rc"
jqok "running from the main checkout never hides its index lock" "$out" '.foreign_activity == true and ([.worktrees[] | select(.branch == "main" and .index_lock.present == true and .foreign_activity == true)] | length) == 1 and ([.self[] | select(endswith("clone-writers"))] | length) == 1'

git -C "$wdirty" update-ref -m same-head HEAD HEAD
out="$("$WRAP" session --writers --check-mark "$wmark" --self "$wself" --self "$wown" "$wclone" 2>/dev/null)"; rc=$?
chk "the same-head reflog append re-check exits 0" "$rc"
jqok "a reflog append on the same head is foreign through the digest" "$out" '.foreign_activity == true and ([.worktrees[] | select(.branch == "wt-dirty" and .reflog.changed_since_mark == true and .foreign_activity == true)] | length) == 1'

echo foreign > "$wdirty/foreign-write.txt"
git -C "$wdirty" add foreign-write.txt
git -C "$wdirty" commit -qm foreign-write
out="$("$WRAP" session --writers --check-mark "$wmark" --self "$wself" --self "$wown" "$wclone" 2>/dev/null)"; rc=$?
chk "the foreign-worktree re-check exits 0" "$rc"
jqok "a foreign commit in another worktree after the mark is foreign" "$out" '.foreign_activity == true and ([.worktrees[] | select(.branch == "wt-dirty" and .reflog.changed_since_mark == true and .foreign_activity == true)] | length) == 1'
out="$("$WRAP" session --writers --check-mark "$TMPD/no-such-mark" --self "$wself" "$wclone" 2>/dev/null)"; rc=$?
chk "a missing writer mark still exits 0" "$rc"
jqok "a missing writer mark is conservatively foreign" "$out" '.foreign_activity == true and .writer_mark.valid == false and .writer_mark.error == "writer mark missing or invalid"'
out="$("$WRAP" session --writers --mark "$TMPD" --self "$wself" "$wclone" 2>/dev/null)"; rc=$?
chk "an unwritable writer mark still exits 0" "$rc"
jqok "an unwritable writer mark is conservatively foreign" "$out" '.foreign_activity == true and .writer_mark.error == "writer mark write failed"'

# ===========================================================================
echo "=== fetch_error is measured, not hardcoded ==="
# ===========================================================================
jqok "a readable origin ref reports that fetch was not attempted" "$("$WRAP" session --json "$clone" 2>/dev/null)" '.repos[0].fetch_error == "fetch not attempted (read-only gather); origin data may be stale"'
noorigin="$TMPD/no-origin-repo"
mkdir -p "$noorigin"
git -C "$noorigin" init -q
gitc "$noorigin"
echo x > "$noorigin/x.txt"
git -C "$noorigin" add x.txt
git -C "$noorigin" commit -qm base
out="$(WRAP_SESSION_WRAP_BIN="$fake" "$WRAP" session --json "$noorigin" 2>/dev/null)"; rc=$?
chk "a repo without origin still exits 0" "$rc"
jqok "fetch_error reports the missing origin instead of a hardcoded null" "$out" '.repos[0].fetch_error == "no origin remote"'

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-session: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-session: all $PASS passed"

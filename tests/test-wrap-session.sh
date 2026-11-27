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
out="$("$WRAP" session --json "$clone" 2>/dev/null)"; rc=$?
chk "the fallback gather exits 0" "$rc"
jqok "without wrap sweep the row falls back to apply dry-run text" "$out" '.repos[0].sweep.format == "text" and .repos[0].sweep.document == null and (.repos[0].sweep.text|type) == "string"'
out="$(WRAP_SESSION_WRAP_BIN="$fake" GH_STUB_UNAUTH=1 "$WRAP" session --json "$clone" 2>/dev/null)"; rc=$?
chk "an unauthenticated gh still exits 0" "$rc"
jqok "gh degradation is a field, not a failure" "$out" '.repos[0].pull_requests.gh_state == "unauthenticated" and .repos[0].pull_requests.open_own == []'

out="$(WRAP_SESSION_WRAP_BIN="$fake" "$WRAP" session --json --follow-mode all "$clone" 2>/dev/null)"; rc=$?
chk "the follow-mode override exits 0" "$rc"
jqok "the follow-mode override lands in config" "$out" '.config.follow_mode == "all" and (.config.follow_lanes | test("full"))'

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-session: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-session: all $PASS passed"

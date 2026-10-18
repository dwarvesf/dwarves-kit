#!/usr/bin/env bash
# test-wave-converge.sh -- `_wave_converge` records `merged` only for a PR that really merged.
# The default merge hook (mega-merge.sh merge) is a dry run that exits 0, so the hook exit code
# alone must never produce a `merged` event. A stub `gh` stands in for GitHub (MEGA_MERGE_GH) and a
# recorder stands in for the merge hook (WAVE_MERGE_CMD); no network, no real merge.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
# shellcheck source=../lib/queue/orchestrate.sh
source "$ORCH"   # the source guard keeps main from running; exposes _wave_converge

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"; MG="$REPO/mega"
mkdir -p "$MG/goals"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name test
git -C "$REPO" commit -q --allow-empty -m init
cat > "$MG/ROADMAP.md" <<'EOF'
# Mega-goal: converge
## Sub-goals
- [ ] SG-01 alpha , auto , PR #11
EOF
printf '# SG-01: alpha\n**Branch:** feat/alpha\n\n## Touches\n- a.txt\n' > "$MG/goals/01-SG-01.md"

# A recorder hook: logs its argv, exits as MOCK_RC says (default 0).
cat > "$TMP/hook" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$HOOK_LOG"
exit "${MOCK_RC:-0}"
EOF
# A gh stub: `pr view` prints the state in GH_STATE.
cat > "$TMP/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] && { echo "${GH_STATE:-OPEN}"; exit 0; }
exit 1
EOF
chmod +x "$TMP/hook" "$TMP/gh"
export HOOK_LOG="$TMP/hook.log" MEGA_MERGE_GH="$TMP/gh" WAVE_MERGE_CMD="$TMP/hook"

events() { cut -f3 "$MG/.orchestrate/events.log" 2>/dev/null | tr '\n' ' '; }
reset() { rm -rf "$MG/.orchestrate"; : > "$HOOK_LOG"; }

# 1. dry run: hook exits 0, PR still OPEN -> merge-dry-run, never merged, converge still returns 0
reset; GH_STATE=OPEN _wave_converge "$MG" SG-01 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(events)" = "merge-dry-run " ] \
  && pass "dry run: merge-dry-run event, no merged event (rc 0)" || fail "dry run: rc=$rc events='$(events)'"

# 2. the PR reports MERGED (a real merge happened) -> merged event
reset; GH_STATE=MERGED _wave_converge "$MG" SG-01 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(events)" = "merged " ] \
  && pass "PR MERGED: merged event (rc 0)" || fail "PR MERGED: rc=$rc events='$(events)'"
grep -q '^11 ' "$HOOK_LOG" && pass "hook called with the PR number first" || fail "hook argv: $(cat "$HOOK_LOG")"

# 3. a CLOSED (not merged) PR is not a merge either
reset; GH_STATE=CLOSED _wave_converge "$MG" SG-01 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(events)" = "merge-dry-run " ] \
  && pass "PR CLOSED: no merged event" || fail "PR CLOSED: rc=$rc events='$(events)'"

# 4. hook failure -> blocked, never merged
reset; MOCK_RC=3 GH_STATE=MERGED _wave_converge "$MG" SG-01 >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && [ "$(events)" = "blocked " ] \
  && pass "hook failure: blocked event, rc 3" || fail "hook failure: rc=$rc events='$(events)'"

# 5. an unreadable gh (no state) never counts as merged
reset; MEGA_MERGE_GH=/nonexistent/gh _wave_converge "$MG" SG-01 >/dev/null 2>&1
[ "$(events)" = "merge-dry-run " ] && pass "unreadable gh: not merged" || fail "unreadable gh: events='$(events)'"

# 6. the ROADMAP is untouched by a dry run
grep -q '^- \[ \] SG-01 alpha , auto , PR #11$' "$MG/ROADMAP.md" \
  && pass "ROADMAP line unchanged after a dry run" || fail "ROADMAP changed: $(cat "$MG/ROADMAP.md")"

echo "---"; [ "$fails" = 0 ] && echo "All wave-converge tests passed." || echo "$fails failed."
exit "$fails"

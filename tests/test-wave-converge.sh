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

# 7-8. The same-file guard measures each branch against the branch the PRs merge into (origin's
# default), not the run worktree's HEAD. The run branch stays on an old commit while origin/main
# advances; branches cut from the advanced main must not "overlap" on files they only inherited.
# mk_stale_case <name> <fileA> <fileB>: bare origin, a work clone parked on chore/run at the first
# commit, origin/main advanced by commits touching shared files, two sub-goal branches cut from the
# advanced main (each adds its own file). The work clone fetches only the two branches after the
# advance, so its origin/main is stale until converge refreshes it.
mk_stale_case() {
  local name="$1" fa="$2" fb="$3" d="$TMP/$1" i g
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/work" 2>/dev/null
  git clone -q "$d/origin.git" "$d/push" 2>/dev/null
  for g in work push; do
    git -C "$d/$g" config user.email t@example.com; git -C "$d/$g" config user.name test
  done
  git -C "$d/push" checkout -q -b main
  for i in 1 2 3; do echo "v0 $i" > "$d/push/shared$i.txt"; done
  git -C "$d/push" add -A; git -C "$d/push" commit -q -m "chore: base"
  git -C "$d/push" push -q origin main 2>/dev/null
  git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  git -C "$d/work" fetch -q origin 2>/dev/null
  git -C "$d/work" checkout -q -b chore/run origin/main   # the run worktree branch: never advances
  for i in 1 2 3; do
    echo "v1 $i" > "$d/push/shared$i.txt"; git -C "$d/push" commit -q -am "chore: advance $i"
  done
  git -C "$d/push" push -q origin main 2>/dev/null
  git -C "$d/push" checkout -q -b "feat/$name-a"; echo a > "$d/push/$fa"; git -C "$d/push" add -A; git -C "$d/push" commit -q -m "feat: a"
  git -C "$d/push" checkout -q main
  git -C "$d/push" checkout -q -b "feat/$name-b"; echo b > "$d/push/$fb"; git -C "$d/push" add -A; git -C "$d/push" commit -q -m "feat: b"
  git -C "$d/push" push -q origin "feat/$name-a" "feat/$name-b" 2>/dev/null
  git -C "$d/work" fetch -q origin "feat/$name-a:feat/$name-a" "feat/$name-b:feat/$name-b" 2>/dev/null
  mkdir -p "$d/work/mega/goals"
  printf '# Mega-goal: stale\n## Sub-goals\n- [ ] SG-01 alpha , auto , PR #21\n- [ ] SG-02 beta , auto , PR #22\n' > "$d/work/mega/ROADMAP.md"
  printf '# SG-01: alpha\n**Branch:** feat/%s-a\n' "$name" > "$d/work/mega/goals/01-SG-01.md"
  printf '# SG-02: beta\n**Branch:** feat/%s-b\n' "$name" > "$d/work/mega/goals/02-SG-02.md"
}

# 7. disjoint branches off an advanced main: no overlap (fails on a HEAD-based base: the stale
# merge-base makes both branches show main's three advanced files)
mk_stale_case disj a-only.txt b-only.txt
out=$(GH_STATE=OPEN _wave_converge "$TMP/disj/work/mega" SG-01 SG-02 2>&1 >/dev/null); rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'SAME-FILE'; then pass "stale run branch, disjoint sub-goals: no overlap (rc 0)"
else fail "stale run branch, disjoint sub-goals: rc=$rc out='$(printf '%s' "$out" | tr '\n' ' ')'"; fi

# 8. control: two branches that both edit one file are still flagged, and only that file
mk_stale_case same common.txt common.txt
out=$(_wave_converge "$TMP/same/work/mega" SG-01 SG-02 2>&1 >/dev/null); rc=$?
files=$(printf '%s\n' "$out" | sed -n 's/^    //p' | tr '\n' ' ')
[ "$rc" = 1 ] && [ "$files" = "common.txt " ] \
  && pass "same-file edit still flagged: only common.txt (rc 1)" || fail "same-file control: rc=$rc files='$files'"

echo "---"; [ "$fails" = 0 ] && echo "All wave-converge tests passed." || echo "$fails failed."
exit "$fails"

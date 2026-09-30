#!/usr/bin/env bash
# test-board-work.sh -- `board work` (lib/board/work.sh): the join of board rows, mega sub-goals,
# git, orca terminal state and run-ledger rungs.
#
# Every case is hermetic: a temp git repo, a temp DWARVES_KIT_LOG_DIR, the stub orca in
# tests/fixtures/board-work/, and a fixed --now. The live orca and the live ledger are never
# touched. The three named NEGATIVE CONTROLS: an idle terminal past the threshold is PARKED,
# the same row with a young terminal or a working one is not, and the same row with its
# worktree removed is INDETERMINATE and never idle.
#
# Run: bash tests/test-board-work.sh   (exit 0 = all green)
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$KIT_DIR/lib/board/work.sh"
FIX="$KIT_DIR/tests/fixtures/board-work"
STUB="$FIX/orca"
NOW=1800000000

PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }
truthy() { if eval "$2"; then ok "$1"; else bad "$1 (condition false: $2)"; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset KIT_LEDGER_DIR DWARVES_KIT_LOG_DIR ORCA_STUB_MODE ORCA_STUB_LOG ORCA_STUB_PAGE GOAL_REGISTRY_SH GOAL_REGISTRY_DIR ORCA_TIMEOUT_S

# GNU-tools pass: the whole suite reruns with coreutils first on PATH (CI runs GNU tr, sed, awk
# semantics; a BSD-only pass hid a reversed tr range once). Skips visibly when the dir is absent.
GNUBIN=/opt/homebrew/opt/coreutils/libexec/gnubin
if [ -z "${BW_GNU:-}" ]; then
  if [ -d "$GNUBIN" ]; then GNU_RUN=1; else echo "SKIP: GNU-tools pass ($GNUBIN not found)"; GNU_RUN=0; fi
else GNU_RUN=0; fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- helpers -------------------------------------------------------------------------------

W=""; LOGS=""; REPO=""; PAGE=""; SLOG=""
new_case() {
  W="$(mktemp -d "$TMP/case.XXXXXX")"; LOGS="$W/logs"; REPO="$W/repo"; PAGE="$W/page.json"; SLOG="$W/orca.log"
  mkdir -p "$LOGS/runs" "$REPO/_meta"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cp "$FIX/BACKLOG.md" "$REPO/_meta/BACKLOG.md"
  : > "$SLOG"
  page < /dev/null
  mkdir -p "$W/goalreg"
}
g() { git -C "$REPO" "$@"; }
row() { printf '| %s | title of %s | src | %s |\n' "$1" "$1" "$2" >> "$REPO/_meta/BACKLOG.md"; }
draft() {  # <id> <slug> [dir under .claude/goals] [repo]
  local dir="${3:-}" root="${4:-$REPO}" d
  d="$root/.claude/goals${dir:+/$dir}"; mkdir -p "$d"
  sed -e "s/@SLUG@/$2/" -e "s/@ID@/$1/" "$FIX/draft.md" > "$d/$2.md"
}
branch() { g branch "$1"; }
worktree() { g worktree add -q "$2" "$1" 2>/dev/null || g worktree add -q -b "$1" "$2"; }
claim() {  # <slug> <lane> <started>: a goal-registry claim, in the case's private registry dir
  printf 'slug=%s\nlane=%s\nstatus=running\nbranch=master\nstarted=%s\n' "$1" "$2" "$3" > "$W/goalreg/$1.goal"
}
ledger() { printf '%s\n' "$2" > "$LOGS/runs/$1.log"; }
lline() { printf '2026-09-29T13:00:00Z | GATE | %s | %s | note\n' "$1" "$2"; }
# page: rows on stdin as path|branch|status|live|lastOutputMs|agentState[|hostId]
page() {
  jq -Rn --argjson trunc "${TRUNC:-false}" '{ok: true, id: "x", result: {hostScope: {}, totalCount: 0, truncated: $trunc,
    worktrees: [inputs | select(length > 0) | split("|") | {path: .[0], branch: ("refs/heads/" + .[1]), hostId: (.[6] // "local"),
      status: .[2], liveTerminalCount: (.[3] | tonumber), lastOutputAt: (if .[4] == "null" then null else (.[4] | tonumber) end),
      agents: (if .[5] == "-" then [] else [{state: .[5]}] end)}]}}' > "$PAGE"
}
ms_ago() { echo $(( (NOW - $1) * 1000 )); }
run_work() {
  GOAL_REGISTRY_DIR="$W/goalreg" DWARVES_KIT_LOG_DIR="$LOGS" ORCA_BIN="${ORCA_BIN:-$STUB}" ORCA_STUB_PAGE="$PAGE" ORCA_STUB_LOG="$SLOG" \
    bash "$WORK" --repo-root "$REPO" --now "$NOW" "$@"
}
J() { run_work --json "$@"; }
field() { jq -c "$2" <<< "$1"; }              # field <json> <jq expr>
itemof() { jq -c --arg i "$2" '.items[] | select(.item == $i)' <<< "$1"; }

# The one in-progress fixture most cases start from: ID-100 executing, branch feat/alpha,
# worktree $W/wt-alpha, draft slug alpha. Terminal state comes from the caller's page.
inprog() {
  new_case
  row ID-100 executing
  draft ID-100 alpha
  worktree feat/alpha "$W/wt-alpha"
}
alpha_page() { printf '%s|feat/alpha|%s|%s|%s|%s\n' "$W/wt-alpha" "$1" "$2" "$3" "${4:--}" | page; }

# ---- runid_parity --------------------------------------------------------------------------
echo "== runid_parity =="
real_runid="$(grep -m1 '^runid() ' "$KIT_DIR/lib/gate/gate-ledger.sh")"
mine_runid="$(grep -m1 '^runid() ' "$WORK")"
lines_fn="$(grep -m1 '^runid_lines() ' "$WORK")"
names=('feat/x' 'a b/c d' 'fix/foo.bar_baz-1' 'type/ünï cödé/slug' '' 'feat/x;rm -rf' 'a//b' '../up' 'UPPER/Case-1')
par=0; total=0
for n in "${names[@]}"; do
  total=$((total+1))
  a="$(eval "$real_runid"; runid "$n")"; b="$(eval "$mine_runid"; runid "$n")"
  c="$(eval "$lines_fn"; printf '%s\n' "$n" | runid_lines)"
  [ "$a" = "$b" ] && [ "$a" = "$c" ] && par=$((par+1)) || echo "    mismatch on '$n': real='$a' work='$b' lines='$c'"
done
check "runid_parity: work.sh runid and runid_lines equal gate-ledger.sh runid over $total names" "$par" "$total"

# ---- PARKED and its negative controls ------------------------------------------------------
echo "== parked_idle_past_threshold =="
inprog; alpha_page inactive 1 "$(ms_ago 2700)"
out="$(J)"; it="$(itemof "$out" ID-100)"
check "parked: agent state idle" "$(field "$it" .agent.state)" '"idle"'
check "parked: idle_s 2700" "$(field "$it" .agent.idle_s)" 2700
check "parked: flags PARKED only" "$(field "$it" .flags)" '["PARKED"]'
check "parked: rung none, branch and worktree resolved" "$(field "$it" '[.rung,.branch,(.worktree|type)]')" '["none","feat/alpha","string"]'
tbl="$(run_work)"
truthy "parked: table row shows idle 45m and PARKED" "grep -Eq '^ID-100 +wt-alpha +idle 45m +none +- +PARKED\$' <<< \"\$tbl\""

echo "== not_parked_under_threshold (NEGATIVE CONTROL) =="
inprog; alpha_page inactive 1 "$(ms_ago 300)"
it="$(itemof "$(J)" ID-100)"
check "young terminal: idle 300s, no PARKED" "$(field "$it" '[.agent.state,.agent.idle_s,.flags]')" '["idle",300,[]]'
alpha_page inactive 1 "$(ms_ago 2700)"
it="$(itemof "$(J --idle-min 60)" ID-100)"
check "45 min idle with --idle-min 60: no PARKED" "$(field "$it" .flags)" '[]'
it="$(itemof "$(J --idle-min 45)" ID-100)"
check "45 min idle with --idle-min 45: PARKED (threshold is inclusive)" "$(field "$it" .flags)" '["PARKED"]'

echo "== working_never_parked (NEGATIVE CONTROL) =="
inprog; alpha_page working 1 "$(ms_ago 7200)"
it="$(itemof "$(J)" ID-100)"
check "working terminal with old output: working, idle_s null, no PARKED" "$(field "$it" '[.agent.state,.agent.idle_s,.flags]')" '["working",null,[]]'
alpha_page inactive 1 "$(ms_ago 7200)" working
it="$(itemof "$(J)" ID-100)"
check "an agent in state working wins over an inactive status" "$(field "$it" '[.agent.state,.flags]')" '["working",[]]'

echo "== no_worktree_indeterminate (NEGATIVE CONTROL) =="
new_case; row ID-100 executing; draft ID-100 alpha; branch feat/alpha
printf '%s|feat/alpha|inactive|1|%s|-\n' "$W/somewhere" "$(ms_ago 7200)" | page
out="$(J)"; it="$(itemof "$out" ID-100)"
check "no worktree: INDETERMINATE(no-worktree), agent unknown, idle_s null" "$(field "$it" '[.flags,.reasons,.agent.state,.agent.idle_s,.worktree]')" '[["INDETERMINATE"],["no-worktree"],"unknown",null,null]'
tbl="$(run_work)"
truthy "no worktree: table says INDETERMINATE(no-worktree), no idle text, no PARKED" "sed -n 2p <<< \"\$tbl\" | grep -q 'INDETERMINATE(no-worktree)' && ! sed -n 2p <<< \"\$tbl\" | grep -Eq 'idle [0-9]|PARKED'"

echo "== no_draft_indeterminate =="
new_case; row ID-100 executing
out="$(J)"; it="$(itemof "$out" ID-100)"
check "no draft: INDETERMINATE(no-draft), agent unknown" "$(field "$it" '[.flags,.reasons,.agent.state,.branch]')" '[["INDETERMINATE"],["no-draft"],"unknown",null]'

echo "== not_in_orca_no_terminal =="
inprog; printf '%s|feat/other|inactive|1|%s|-\n' "$W/elsewhere" "$(ms_ago 60)" | page
it="$(itemof "$(J)" ID-100)"
check "worktree missing from the orca page: not-in-orca, unknown" "$(field "$it" '[.reasons,.agent.state]')" '[["not-in-orca"],"unknown"]'
alpha_page inactive 0 null
it="$(itemof "$(J)" ID-100)"
check "zero live terminals and no output time: no-terminal, unknown" "$(field "$it" '[.reasons,.agent.state,.agent.idle_s,.flags]')" '[["no-terminal"],"unknown",null,["INDETERMINATE"]]'
alpha_page inactive 1 null
it="$(itemof "$(J)" ID-100)"
check "live terminal but no lastOutputAt: no-terminal, never idle" "$(field "$it" '[.reasons,.agent.state]')" '[["no-terminal"],"unknown"]'
printf '%s|feat/alpha|inactive|1|%s|-|remote-1\n' "$W/wt-alpha" "$(ms_ago 7200)" | page
it="$(itemof "$(J)" ID-100)"
check "a row on a remote host is not read in v1: no-orca, unknown" "$(field "$it" '[.reasons,.agent.state]')" '[["no-orca"],"unknown"]'

echo "== branch fallback (path does not match, branch does) =="
inprog; mkdir -p "$REPO/moved-path" "$W/other-repo/wt-alpha"; printf '%s|feat/alpha|inactive|1|%s|-\n' "$REPO/moved-path" "$(ms_ago 2700)" | page
it="$(itemof "$(J)" ID-100)"
check "orca row under the repo matched by branch when its path differs" "$(field "$it" '[.agent.state,.flags]')" '["idle",["PARKED"]]'
inprog; mkdir -p "$W/other-repo/wt-alpha"; printf '%s|feat/alpha|inactive|1|%s|-\n' "$W/other-repo/wt-alpha" "$(ms_ago 2700)" | page
it="$(itemof "$(J)" ID-100)"
check "NEGATIVE: an orca row of another repo with the same branch is never borrowed" "$(field "$it" '[.reasons,.agent.state,.flags]')" '[["not-in-orca"],"unknown",["INDETERMINATE"]]'
inprog; mkdir -p "$REPO/moved-a" "$REPO/moved-b"; { printf '%s|feat/alpha|inactive|1|%s|-\n' "$REPO/moved-a" "$(ms_ago 2700)"; printf '%s|feat/alpha|inactive|1|%s|-\n' "$REPO/moved-b" "$(ms_ago 100)"; } | page
it="$(itemof "$(J)" ID-100)"
check "NEGATIVE: two branch matches under the repo is ambiguous, no row is borrowed" "$(field "$it" '[.reasons,.agent.state]')" '[["not-in-orca"],"unknown"]'

echo "== symlinked path is canonicalized =="
inprog; ln -s "$W/wt-alpha" "$W/link-alpha"
printf '%s|feat/alpha|inactive|1|%s|-\n' "$W/link-alpha" "$(ms_ago 2700)" | page
it="$(itemof "$(J)" ID-100)"
check "orca row given by a symlink still joins the worktree" "$(field "$it" '[.agent.state,.flags]')" '["idle",["PARKED"]]'
check "worktree in the output is the pwd -P form" "$(field "$it" .worktree)" "\"$(cd "$W/wt-alpha" && pwd -P)\""

echo "== status_unknown_first =="
inprog; alpha_page weird 1 "$(ms_ago 7200)"
it="$(itemof "$(J)" ID-100)"
check "unknown status with a live terminal and old output: unknown, no-terminal, no PARKED" "$(field "$it" '[.agent.state,.reasons,.flags]')" '["unknown",["no-terminal"],["INDETERMINATE"]]'

echo "== clock skew =="
inprog; alpha_page inactive 1 "$(( (NOW + 600) * 1000 ))"
it="$(itemof "$(J)" ID-100)"
check "lastOutputAt in the future: idle_s floors at 0, no PARKED" "$(field "$it" '[.agent.state,.agent.idle_s,.flags]')" '["idle",0,[]]'

echo "== worktrees_scanned_for_drafts =="
new_case; row ID-100 executing
worktree feat/alpha "$W/wt-alpha"; draft ID-100 alpha "" "$W/wt-alpha"
alpha_page inactive 1 "$(ms_ago 2700)"
it="$(itemof "$(J)" ID-100)"
check "draft only under a worktree's .claude/goals resolves" "$(field "$it" '[.reasons,.flags]')" '[[],["PARKED"]]'
new_case; row ID-100 executing; worktree feat/alpha "$W/wt-alpha"; draft ID-100 alpha done
alpha_page inactive 1 "$(ms_ago 2700)"
it="$(itemof "$(J)" ID-100)"
check "draft retired to .claude/goals/done/ is still found" "$(field "$it" '[.reasons,.flags]')" '[[],["PARKED"]]'

echo "== duplicate_id =="
inprog; row ID-100 executing; alpha_page inactive 1 "$(ms_ago 2700)"
out="$(J)"
check "same id twice: one row, INDETERMINATE(duplicate-id)" "$(field "$out" '[(.items | map(select(.item == "ID-100")) | length), .items[0].reasons]')" '[1,["duplicate-id"]]'

echo "== ambiguous_branch =="
new_case; row ID-100 executing; draft ID-100 alpha; branch feat/alpha; branch fix/alpha
it="$(itemof "$(J)" ID-100)"
check "two branches with one slug: INDETERMINATE(ambiguous), no branch picked" "$(field "$it" '[.reasons,.branch,.agent.state]')" '[["ambiguous"],null,"unknown"]'

echo "== orca_absent =="
inprog; alpha_page inactive 1 "$(ms_ago 7200)"; row ID-101 claimed; draft ID-101 beta; worktree feat/beta "$W/wt-beta"
out="$(ORCA_BIN=/nonexistent J)"; rc=$?
check "orca absent: exit 0" "$rc" 0
check "orca absent: orca=absent" "$(field "$out" .orca)" '"absent"'
check "orca absent: every agent unknown and INDETERMINATE" "$(field "$out" '.items | all(.agent.state == "unknown" and (.flags | index("INDETERMINATE")) != null and (.reasons | index("no-orca")) != null)')" true
check "orca absent: never idle, never PARKED" "$(field "$out" '[.items[] | select(.agent.state == "idle" or (.flags | index("PARKED")))] | length')" 0
out="$(ORCA_STUB_MODE=fail J)"; rc=$?
check "orca exits 1: exit 0, orca=error, agents unknown" "$rc $(field "$out" '[.orca, (.items | all(.agent.state == "unknown"))]')" '0 ["error",true]'
out="$(ORCA_STUB_MODE=garbage J)"; rc=$?
check "orca prints non-JSON: exit 0, orca=error" "$rc $(field "$out" .orca)" '0 "error"'
printf '{"result":{"worktrees":"nope"}}\n' > "$PAGE"
out="$(J)"
check "orca JSON of the wrong shape: orca=error" "$(field "$out" .orca)" '"error"'
tbl="$(ORCA_BIN=/nonexistent run_work)"; rc=$?
truthy "orca absent: table renders with exit 0 and names the state" "[ $rc = 0 ] && grep -q '^orca: absent' <<< \"\$tbl\""

echo "== orca_truncated =="
inprog; printf '%s|feat/other|inactive|1|%s|-\n' "$W/elsewhere" "$(ms_ago 60)" | TRUNC=true page
out="$(J)"; tbl="$(run_work)"
check "truncated page: target row is not-in-orca, truncated=true" "$(field "$out" '[.truncated, (.items[0].reasons)]')" '[true,["not-in-orca"]]'
truthy "truncated page: table footer says TRUNCATED" "grep -q 'TRUNCATED' <<< \"\$tbl\""

echo "== done_unseen (NEGATIVE CONTROL) =="
new_case; row ID-200 shipped; draft ID-200 gamma; worktree feat/gamma "$W/wt-gamma"
cp "$FIX/ledgers/shipped.log" "$LOGS/runs/gamma.log"
printf '%s|feat/gamma|inactive|1|%s|-\n' "$W/wt-gamma" "$(ms_ago 60)" | page
it="$(itemof "$(J)" ID-200)"
check "shipped ledger with branch and worktree alive: DONE-UNSEEN, rung shipped" "$(field "$it" '[.flags,.rung]')" '[["DONE-UNSEEN"],"shipped"]'
lline wrap ran >> "$LOGS/runs/gamma.log"
it="$(itemof "$(J)" ID-200)"
check "adding wrap ran changes nothing" "$(field "$it" '[.flags,.rung]')" '[["DONE-UNSEEN"],"shipped"]'
g worktree remove --force "$W/wt-gamma"; g branch -D feat/gamma -q >/dev/null
out="$(J)"
check "worktree and branch removed: the row is gone, even with wrap ran in the ledger" "$(field "$out" '[.items[] | select(.item == "ID-200")] | length')" 0
check "worktree and branch removed: a shipped-ledger row is finished, not counted unchecked" "$(field "$out" .unchecked_shipped)" 0
new_case; row ID-200 shipped; draft ID-200 gamma; branch feat/gamma
cp "$FIX/ledgers/shipped.log" "$LOGS/runs/gamma.log"
it="$(itemof "$(J)" ID-200)"
check "branch alone (no worktree) still shows DONE-UNSEEN, no INDETERMINATE for the missing worktree" "$(field "$it" '[.flags,.worktree]')" '[["DONE-UNSEEN"],null]'
g branch -D feat/gamma -q >/dev/null
out="$(J)"
check "branch removed, no wrap record needed: row gone" "$(field "$out" '[.items[] | select(.item == "ID-200")] | length')" 0
check "branch removed: not counted unchecked either" "$(field "$out" .unchecked_shipped)" 0

echo "== rung_ladder =="
new_case
mk() { row "ID-30$1" executing; draft "ID-30$1" "r$1"; branch "feat/r$1"; }
for i in 0 1 2 3 4 5 6 7 8; do mk $i; done
: > "$LOGS/runs/r0.log"
cp "$FIX/ledgers/validate-skipped.log" "$LOGS/runs/r1.log"
lline validate ran > "$LOGS/runs/r2.log"
lline execute ran > "$LOGS/runs/r3.log"
lline review ran > "$LOGS/runs/r4.log"
lline battery ran > "$LOGS/runs/r5.log"
lline ship ran > "$LOGS/runs/r6.log"
{ lline validate ran; lline review ran; } > "$LOGS/runs/r7.log"
{ lline spec ran; lline validate skipped; lline review skipped; } > "$LOGS/runs/r8.log"
out="$(J)"
got="$(field "$out" '[.items | sort_by(.item)[] | .rung] | join(",")')"
check "rung ladder: empty, skipped, validate, execute, review, battery, ship, highest wins, skips ignored" "$got" '"none,none,validated,built,reviewed,reviewed,shipped,reviewed,none"'

echo "== mega_rows =="
new_case; mkdir -p "$REPO/_meta/megagoals/m1/goals"
cp "$FIX/ROADMAP.md" "$REPO/_meta/megagoals/m1/ROADMAP.md"
printf '# goal\n\n**Branch:** feat/x  (a trailing note)\n' > "$REPO/_meta/megagoals/m1/goals/01-first.md"
worktree feat/x "$W/wt-x"
printf '%s|feat/x|inactive|1|%s|-\n' "$W/wt-x" "$(ms_ago 2700)" | page
out="$(J)"; it="$(itemof "$out" m1/SG-01)"
check "mega SG-01 listed with branch feat/x from the first Branch token" "$(field "$it" '[.origin,.branch,.agent.state,.flags]')" '["mega","feat/x","idle",["PARKED"]]'
check "checked SG-00 is never listed" "$(field "$out" '[.items[] | select(.item == "m1/SG-00")] | length')" 0
printf -- '- [ ] 04-legacy-slug , auto\n- [ ] 2026-09-30 a dated note, not a sub-goal\n' >> "$REPO/_meta/megagoals/m1/ROADMAP.md"
printf '**Branch:** feat/legacy\n' > "$REPO/_meta/megagoals/m1/goals/04-legacy-slug.md"
branch feat/legacy
out="$(J)"
check "legacy NN-slug roadmap line resolves goals/<NN-slug>.md" "$(field "$(itemof "$out" m1/04-legacy-slug)" .branch)" '"feat/legacy"'
check "a date-led roadmap line is not a legacy sub-goal" "$(field "$out" '[.items[] | select(.item | test("2026"))] | length')" 0
mkdir -p "$W/other-megas/m2/goals"
printf -- '- [ ] SG-01 elsewhere\n' > "$W/other-megas/m2/ROADMAP.md"
printf '**Branch:** feat/x\n' > "$W/other-megas/m2/goals/01-a.md"
out="$(J --megagoals-root "$W/other-megas")"
check "--megagoals-root overrides the roadmap location" "$(field "$out" '[.items[].item] | sort | join(",")')" '"m2/SG-01"'

echo "== mega_code_root =="
new_case; mkdir -p "$REPO/_meta/megagoals/m1/goals" "$W/code"
git -C "$W/code" init -q; git -C "$W/code" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$W/code" worktree add -q -b feat/x "$W/wt-code-x"
cp "$FIX/ROADMAP.md" "$REPO/_meta/megagoals/m1/ROADMAP.md"
printf '**Branch:** feat/x\n' > "$REPO/_meta/megagoals/m1/goals/01-first.md"
printf '%s|feat/x|inactive|1|%s|-\n' "$W/wt-code-x" "$(ms_ago 2700)" | page
out="$(J --code-root "$W/code")"; it="$(itemof "$out" m1/SG-01)"
check "branch living only in --code-root resolves and joins its worktree" "$(field "$it" '[.branch,.agent.state,.flags]')" '["feat/x","idle",["PARKED"]]'
out="$(J)"
check "without --code-root the branch is not in this repo: not started, not listed" "$(field "$out" '[.items[] | select(.item == "m1/SG-01")] | length')" 0

echo "== mega_unresolved (NEGATIVE CONTROL) =="
new_case; mkdir -p "$REPO/_meta/megagoals/m1/goals"
printf -- '- [ ] SG-02 no goal file\n- [ ] SG-03 no branch line\n- [ ] SG-04 branch not created yet\n' > "$REPO/_meta/megagoals/m1/ROADMAP.md"
printf '# goal with no branch line\n' > "$REPO/_meta/megagoals/m1/goals/03-nb.md"
printf '**Branch:** feat/not-yet\n' > "$REPO/_meta/megagoals/m1/goals/04-later.md"
out="$(J)"
check "SG-02 and SG-03 are listed INDETERMINATE(no-branch)" "$(field "$out" '[.items[] | select(.item | test("SG-0[23]")) | [.item, .flags, .reasons]] | sort')" '[["m1/SG-02",["INDETERMINATE"],["no-branch"]],["m1/SG-03",["INDETERMINATE"],["no-branch"]]]'
check "SG-04 (Branch names a branch that does not exist) is not listed" "$(field "$out" '[.items[] | select(.item == "m1/SG-04")] | length')" 0

echo "== table_footer =="
inprog; row ID-050 claimed; draft ID-050 early; worktree feat/early "$W/wt-early"
{ printf '%s|feat/alpha|inactive|1|%s|-\n' "$W/wt-alpha" "$(ms_ago 2700)"; printf '%s|feat/early|working|1|null|working\n' "$W/wt-early"; } | page
row ID-101 executing
tbl="$(run_work --idle-min 15)"
check "table header" "$(head -1 <<< "$tbl" | tr -s ' ')" 'ITEM WORKTREE AGENT RUNG LANE FLAGS'
truthy "footer: threshold" "grep -q '^idle threshold: 15 min' <<< \"\$tbl\""
truthy "footer: orca scope" "grep -q '^orca: ok (scope: local worktrees' <<< \"\$tbl\""
truthy "footer: ledger root" "grep -q \"^ledger: $LOGS\$\" <<< \"\$tbl\" || grep -q \"^ledger: $(cd "$LOGS" && pwd -P)\$\" <<< \"\$tbl\""
truthy "footer: legend" "grep -q '^legend: shipped = the ledger holds a ship record' <<< \"\$tbl\""
check "sorted: an unflagged row that sorts earlier by item still comes after the flagged rows" "$(sed -n '2,4p' <<< "$tbl" | cut -d' ' -f1 | tr '\n' ' ')" 'ID-100 ID-101 ID-050 '

echo "== shipped_unchecked_footer =="
new_case; row ID-400 shipped; draft ID-400 delta; row ID-401 shipped
out="$(J)"; tbl="$(run_work)"
check "shipped rows with no branch and no draft are not listed, both counted" "$(field "$out" '[(.items | length), .unchecked_shipped]')" '[0,2]'
truthy "footer counts them" "grep -q '^2 shipped rows unchecked' <<< \"\$tbl\""

echo "== read_only =="
new_case
row ID-100 executing; draft ID-100 alpha; worktree feat/alpha "$W/wt-alpha"
row ID-200 shipped; draft ID-200 gamma; branch feat/gamma; cp "$FIX/ledgers/shipped.log" "$LOGS/runs/gamma.log"
alpha_page inactive 1 "$(ms_ago 2700)"
snap() { { find "$W/repo" "$LOGS" "$W/wt-alpha" -type f 2>/dev/null | sort | xargs shasum; git -C "$REPO" status --porcelain; git -C "$REPO" worktree list --porcelain; } | shasum; }
before="$(snap)"; : > "$SLOG"
run_work > /dev/null; J > /dev/null
after="$(snap)"
check "repo, ledger dir and worktree hash equal before and after" "$after" "$before"
check "stub orca saw only worktree ps --json --limit 500 (one per run)" "$(sort -u "$SLOG")" 'worktree ps --json --limit 500'
check "two runs, two orca calls" "$(wc -l < "$SLOG" | tr -d ' ')" 2

echo "== json_shape =="
new_case
row ID-100 executing; draft ID-100 alpha; worktree feat/alpha "$W/wt-alpha"
row ID-101 executing
row ID-200 shipped; draft ID-200 gamma; branch feat/gamma; cp "$FIX/ledgers/shipped.log" "$LOGS/runs/gamma.log"
mkdir -p "$REPO/_meta/megagoals/m1/goals"; cp "$FIX/ROADMAP.md" "$REPO/_meta/megagoals/m1/ROADMAP.md"
printf '**Branch:** feat/x\n' > "$REPO/_meta/megagoals/m1/goals/01-first.md"; worktree feat/x "$W/wt-x"
{ printf '%s|feat/alpha|inactive|1|%s|-\n' "$W/wt-alpha" "$(ms_ago 2700)"; printf '%s|feat/x|working|1|null|working\n' "$W/wt-x"; } | page
out="$(J)"
A10='(.schema==1) and (.generated_at|type=="number") and (.orca|IN("ok","absent","error")) and (.truncated|type=="boolean") and (.items|type=="array") and all(.items[]; has("item") and has("branch") and has("worktree") and (.agent|has("state") and has("idle_s")) and (.agent.state|IN("working","idle","unknown")) and (.rung|IN("none","validated","built","reviewed","shipped")) and (.origin|IN("board","mega","worktree")) and (.flags|type=="array") and (.reasons|type=="array"))'
jq -e "$A10" <<< "$out" > /dev/null; check "AC10 clause 1: schema, enums, types, keys present" "$?" 0
jq -e 'all(.items[]; ((.agent.state=="idle") == (.agent.idle_s|type=="number")) and (.agent|has("idle_s")))' <<< "$out" > /dev/null; check "AC10 clause 2: idle_s is a number iff idle, key always present" "$?" 0
jq -r '.items[] | select(.worktree != null) | .worktree' <<< "$out" | while IFS= read -r p; do [ "$p" = "$(cd "$p" && pwd -P)" ] && [ "${p#/}" != "$p" ] || echo BAD; done > "$W/canon.out"
check "AC10 clause 3: worktree paths are absolute and equal their pwd -P form" "$(wc -c < "$W/canon.out" | tr -d ' ')" 0
check "top-level keys are exactly the schema-1 set" "$(field "$out" 'keys | join(",")')" '"generated_at,idle_min,items,ledger_root,orca,repo_root,schema,truncated,unchecked_shipped"'
check "item keys are exactly the schema-1 set, even when null" "$(field "$out" '[.items[] | keys | join(",")] | unique')" '["agent,branch,flags,item,lane,origin,reasons,rung,started,worktree"]'
check "reasons is non-empty exactly when INDETERMINATE" "$(field "$out" 'all(.items[]; ((.reasons|length) > 0) == ((.flags|index("INDETERMINATE")) != null))')" true
check "generated_at echoes --now, repo_root is canonical" "$(field "$out" '[.generated_at, .repo_root]')" "[$NOW,\"$(cd "$REPO" && pwd -P)\"]"
check "the fixture holds an idle, a working, an unknown, a null-branch and a null-worktree row" "$(field "$out" '[([.items[].agent.state] | unique | join(",")), any(.items[]; .branch == null), any(.items[]; .worktree == null)]')" '["idle,unknown,working",true,true]'
# through the stable entrypoints
via_bin="$(DWARVES_KIT_LOG_DIR="$LOGS" ORCA_BIN="$STUB" ORCA_STUB_PAGE="$PAGE" bash "$KIT_DIR/bin/board" work --json --repo-root "$REPO" --now "$NOW" --backlog-file "$REPO/_meta/BACKLOG.md")"
check "bin/board work --json reaches the script and matches" "$via_bin" "$out"
truthy "bin/board work --help shows the verb" "bash '$KIT_DIR/bin/board' work --help | grep -q 'board work'"
truthy "board.sh help lists the verb" "bash '$KIT_DIR/lib/board/board.sh' --help | grep -q 'board.sh work'"

echo "== worktree_items and claims =="
new_case
worktree feat/solo "$W/solo"; worktree feat/lone "$W/lone"
row ID-100 executing; draft ID-100 alpha; worktree feat/alpha "$W/alpha"
lline execute ran > "$LOGS/runs/solo.log"
claim solo normal 2026-09-29T15:00:00Z; claim alpha full 2026-09-29T16:00:00Z; claim ghost normal 2026-09-29T17:00:00Z
{ printf '%s|feat/solo|inactive|1|%s|-\n' "$W/solo" "$(ms_ago 2700)"; printf '%s|feat/alpha|working|1|null|working\n' "$W/alpha"; } | page
out="$(J)"
check "an unjoined live worktree lists as its own item, origin worktree, with agent state and rung" "$(field "$(itemof "$out" solo)" '[.origin,.branch,.agent.state,.rung,.flags]')" '["worktree","feat/solo","idle","built",["PARKED"]]'
check "a claim joins by slug to the worktree basename: lane and started attach" "$(field "$(itemof "$out" solo)" '[.lane,.started]')" '["normal","2026-09-29T15:00:00Z"]'
check "a claim also attaches to a worktree joined to a board item" "$(field "$(itemof "$out" ID-100)" '[.origin,.lane,.started]')" '["board","full","2026-09-29T16:00:00Z"]'
check "the joined worktree is not listed a second time" "$(field "$out" '[.items[] | select(.item == "alpha")] | length')" 0
check "the main checkout is never listed" "$(field "$out" '[.items[] | select(.worktree == "'"$(cd "$REPO" && pwd -P)"'")] | length')" 0
check "a worktree missing from the orca page: INDETERMINATE(not-in-orca), never idle, no lane" "$(field "$(itemof "$out" lone)" '[.agent.state,.reasons,.flags,.lane]')" '["unknown",["not-in-orca"],["INDETERMINATE"],null]'
check "NEGATIVE: a claimed slug with no worktree is INDETERMINATE(no-worktree), agent unknown" "$(field "$(itemof "$out" ghost)" '[.origin,.worktree,.agent.state,.flags,.reasons,.lane]')" '["worktree",null,"unknown",["INDETERMINATE"],["no-worktree"],"normal"]'
tbl="$(run_work)"
truthy "table shows the lane" "grep -Eq '^solo +solo +idle 45m +built +normal +PARKED\$' <<< \"\$tbl\""
new_case; worktree feat/solo "$W/solo"; printf '%s|feat/solo|working|1|null|working\n' "$W/solo" | page
check "no registry claims: lane and started are null, no error" "$(field "$(itemof "$(J)" solo)" '[.lane,.started]')" '[null,null]'
check "a worktree's rung with no ledger is none, no flag" "$(field "$(itemof "$(J)" solo)" '[.rung,.flags]')" '["none",[]]'

echo "== orca_timeout =="
inprog; alpha_page inactive 1 "$(ms_ago 2700)"
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  out="$(ORCA_STUB_MODE=hang ORCA_TIMEOUT_S=1 J)"; rc=$?
  check "a hung orca times out: exit 0, orca=error, agents unknown" "$rc $(field "$out" '[.orca, (.items | all(.agent.state == "unknown"))]')" '0 ["error",true]'
else
  echo "  SKIP: orca_timeout (no timeout or gtimeout on PATH)"
fi

echo "== flags and exit codes =="
new_case
run_work --bogus > /dev/null 2>&1; check "unknown flag exits 64" "$?" 64
run_work --idle-min abc > /dev/null 2>&1; check "non-numeric --idle-min exits 64" "$?" 64
run_work --idle-min > /dev/null 2>&1; check "flag missing its value exits 64" "$?" 64
run_work --backlog-file "$W/nope.md" > /dev/null 2>&1; check "unreadable backlog exits 1" "$?" 1
run_work > /dev/null 2>&1; check "an empty board renders with exit 0" "$?" 0

if [ "$GNU_RUN" = 1 ]; then
  echo "== GNU-tools pass (PATH=$GNUBIN first) =="
  gnu_out="$(BW_GNU=1 PATH="$GNUBIN:$PATH" bash "${BASH_SOURCE[0]}" 2>&1)"; gnu_rc=$?
  grep -E '^  FAIL' <<< "$gnu_out"
  tail -1 <<< "$gnu_out"
  check "GNU-tools pass is green" "$gnu_rc" 0
fi

echo
echo "== board work: $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ]

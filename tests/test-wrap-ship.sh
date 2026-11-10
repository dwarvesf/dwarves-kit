#!/usr/bin/env bash
# test-wrap-ship.sh -- the ship verb: start --carry, stage by named path, commit, an explicit-only
# proof override, land. Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# Real git throughout; the gh stub stands in for GitHub; a fixture git hook stands in for the
# ship-gate on land's push.
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh lib/wrap/wrap-ship.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ship_clone <name> [tpl] -- a bare remote plus a clean clone on main (tracked a.txt and
# docs/keep.md; with `tpl` also a PR template). Prints the clone path. The hooks path is
# pinned inside the clone so an operator-level core.hooksPath never reaches a fixture.
ship_clone() {
  local name="$1" work="$TMPD/sw-$1" bare="$TMPD/sbare-$1" clone="$TMPD/sclone-$1"
  mkdir -p "$work/docs"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/a.txt"; echo keep > "$work/docs/keep.md"
  if [ "${2:-}" = tpl ]; then mkdir -p "$work/.github"; echo "## What" > "$work/.github/pull_request_template.md"; fi
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$bare"
  git clone -q "$bare" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" config core.hooksPath "$clone/.git/hooks"
  printf '%s\n' "$clone"
}

# ship_hook <clone> <hook name> <body> -- an executable git hook in the clone's hooks dir.
ship_hook() {
  mkdir -p "$1/.git/hooks"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/.git/hooks/$2"
  chmod +x "$1/.git/hooks/$2"
}

# ship_go <clone> <branch> <args...> -- `wrap ship` with the gh stub wired for the create,
# merge and verify flow: no open PR for the head, #9 as the created number, and `pr merge`
# pushing the worktree's branch to the remote's main the way a real squash would. Stdout and
# stderr land in $SOUT; the exit code in $SRC.
SOUT=""; SRC=0
ship_go() {
  local c="$1" b="$2"; shift 2
  local bare; bare="$(git -C "$c" remote get-url origin)"
  SOUT="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=9 \
    GH_STUB_LAND_REPO="$(cd "$c" && pwd -P)/.claude/worktrees/${b##*/}" GH_STUB_LAND_REMOTE="$bare" \
    GH_STUB_LAND_BRANCH="$b" GH_STUB_LAND_DEF=main \
    "$WRAP" ship "$c" "$b" "$@" 2>&1)"; SRC=$?
}
sw() { printf '%s/.claude/worktrees/%s\n' "$(cd "$1" && pwd -P)" "${2##*/}"; }
last_line() { printf '%s\n' "$SOUT" | tail -n 1; }
ovr_count() { cat "$KIT_LEDGER_DIR"/proof-overrides.log 2>/dev/null | wc -l | tr -d ' '; }
no_branch() { git -C "$1" show-ref --verify --quiet "refs/heads/$2" && echo 1 || echo 0; }

MSG="$TMPD/ship-msg.txt"; printf 'docs: add a note\n' > "$MSG"

# ===========================================================================
echo "=== ship: the happy path (AC-1) ==="
# ===========================================================================
C1="$(ship_clone h1)"
mkdir -p "$C1/docs"; echo "the note" > "$C1/docs/note.md"
ship_go "$C1" docs/ship-ok --carry docs/note.md --message-file "$MSG" --title "docs: add a note"
chk "ship_happy: exits 0" "$([ "$SRC" -eq 0 ]; echo $?)"
chk_has "ship_happy: last line is the SHIP: shipped line" "$(last_line)" "SHIP: shipped #9 ("
chk_has "ship_happy: land's LAND: line comes before it" "$SOUT" "LAND: merged #9"
chk_has "ship_happy: names the worktree" "$SOUT" "ship: worktree $(sw "$C1" docs/ship-ok)"
chk_has "ship_happy: names the commit" "$SOUT" "ship: committed "
chk "ship_happy: origin main holds the carried file" \
  "$([ "$(git -C "$TMPD/sbare-h1" show main:docs/note.md 2>/dev/null)" = "the note" ]; echo $?)"
chk "ship_happy: the worktree is removed" "$([ ! -e "$(sw "$C1" docs/ship-ok)" ]; echo $?)"
chk "ship_happy: the commit is the caller's message" \
  "$([ "$(git -C "$TMPD/sbare-h1" log -1 --format=%s main)" = "docs: add a note" ]; echo $?)"

# ===========================================================================
echo "=== ship: dirt outside --carry stays in the main checkout (AC-2) ==="
# ===========================================================================
C2="$(ship_clone h2)"
mkdir -p "$C2/docs"; echo "the note" > "$C2/docs/note.md"; echo "someone else's" > "$C2/keep-out.txt"
echo "edited" >> "$C2/a.txt"
ship_go "$C2" docs/ship-dirt --carry docs/note.md --message-file "$MSG"
chk "ship_uncarried_dirt_stays: exits 0" "$([ "$SRC" -eq 0 ]; echo $?)"
chk "ship_uncarried_dirt_stays: the uncarried untracked file is still dirty in main" \
  "$([ "$(cat "$C2/keep-out.txt" 2>/dev/null)" = "someone else's" ]; echo $?)"
chk "ship_uncarried_dirt_stays: the uncarried tracked edit is still in main" \
  "$(git -C "$C2" diff --name-only | grep -qx a.txt && echo 0 || echo 1)"
chk "ship_uncarried_dirt_stays: the commit holds exactly the carried path" \
  "$([ "$(git -C "$TMPD/sbare-h2" show --name-only --format= main)" = "docs/note.md" ]; echo $?)"

# ===========================================================================
echo "=== ship: an override is logged only when asked (AC-3, AC-4) ==="
# ===========================================================================
C3="$(ship_clone o3)"
echo "n" > "$C3/note3.md"
n0="$(ovr_count)"
ship_go "$C3" docs/ship-noflag --carry note3.md --message-file "$MSG"
chk "ship_no_flag_logs_nothing: a clean run exits 0" "$([ "$SRC" -eq 0 ]; echo $?)"
chk "ship_no_flag_logs_nothing: the override log did not grow on a clean run" "$([ "$(ovr_count)" = "$n0" ]; echo $?)"
C3B="$(ship_clone o3b)"
echo "n" > "$C3B/note3.md"
ship_hook "$C3B" pre-push 'exit 1'
ship_go "$C3B" docs/ship-noflag-fail --carry note3.md --message-file "$MSG"
chk "ship_no_flag_logs_nothing: a land refusal exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk "ship_no_flag_logs_nothing: the override log did not grow on a refused run" "$([ "$(ovr_count)" = "$n0" ]; echo $?)"

C4="$(ship_clone o4)"
echo "n" > "$C4/note4.md"
SEEN="$TMPD/ship-hook-saw-override"
ship_hook "$C4" pre-push "f=\$(ls \"\$KIT_LEDGER_DIR\"/proof-overrides.log 2>/dev/null); grep -q '| ship-ov | OVERRIDE |' \"\$f\" 2>/dev/null && : > \"$SEEN\"; exit 0"
n0="$(ovr_count)"
export KIT_LEDGER_DIR
ship_go "$C4" docs/ship-ov --carry note4.md --message-file "$MSG" --proof-override "docs only, no behavior"
chk "ship_override_before_push: exits 0" "$([ "$SRC" -eq 0 ]; echo $?)"
chk "ship_override_before_push: exactly one new override line" "$([ "$(ovr_count)" = "$(( n0 + 1 ))" ]; echo $?)"
chk "ship_override_before_push: the line is keyed to the branch slug" \
  "$(grep -q '| ship-ov | OVERRIDE | docs only, no behavior' "$KIT_LEDGER_DIR/proof-overrides.log" && echo 0 || echo 1)"
chk "ship_override_before_push: the line existed when the push ran" "$([ -e "$SEEN" ]; echo $?)"
chk_has "ship_override_before_push: names the slug" "$SOUT" "ship: override logged (slug ship-ov)"

# ===========================================================================
echo "=== ship: argument refusals write nothing (AC-5, AC-6, AC-7) ==="
# ===========================================================================
C5="$(ship_clone a5)"
echo "n" > "$C5/note5.md"
args_clean() { # args_clean <label> <branch> -- no worktree, no branch, the carry file still dirty
  chk "$1: no worktree" "$([ ! -e "$(sw "$C5" "$2")" ]; echo $?)"
  chk "$1: no branch" "$(no_branch "$C5" "$2" | grep -qx 0 && echo 0 || echo 1)"
  chk "$1: the carry file is still in main" "$([ -f "$C5/note5.md" ]; echo $?)"
}
ship_go "$C5" docs/a5-nocarry --message-file "$MSG"
chk "ship_carry_required: no --carry exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
chk_has "ship_carry_required: the line says preflight" "$(last_line)" "SHIP: refused (preflight, exit 64) worktree=none"
args_clean "ship_carry_required (none)" docs/a5-nocarry
ship_go "$C5" docs/a5-bare --carry --message-file "$MSG"
chk "ship_carry_required: a bare --carry exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
chk_has "ship_carry_required: it names the hazard" "$SOUT" "a bare --carry would stage the whole checkout"
args_clean "ship_carry_required (bare)" docs/a5-bare
for bad in /abs/path ../x a/../b '*.md' 'a?b' '[a]' -x . ./ docs/./note5.md; do
  ship_go "$C5" docs/a5-path --carry "$bad" --message-file "$MSG"
  chk "ship_carry_path_refused: '$bad' exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
done
args_clean "ship_carry_path_refused" docs/a5-path
: > "$TMPD/ship-empty.txt"; mkdir -p "$TMPD/ship-dir"
ship_go "$C5" docs/a5-nomsg --carry note5.md
chk "ship_args_refused: a missing --message-file exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$TMPD/ship-absent.txt"
chk "ship_args_refused: an absent message file exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$TMPD/ship-dir"
chk "ship_args_refused: a directory as message file exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$TMPD/ship-empty.txt"
chk "ship_args_refused: an empty message file exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$MSG" --body-file "$TMPD/ship-absent.txt"
chk "ship_args_refused: an absent body file exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$MSG" --proof-override ""
chk "ship_args_refused: an empty override reason exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$MSG" --proof-override "$(printf 'a\nb')"
chk "ship_args_refused: a multi-line override reason exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
for fl in --draft --with-ci "--verify x" "--pick b" --bogus; do
  ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$MSG" $fl
  chk "ship_args_refused: '$fl' exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
done
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$MSG" --title
chk "ship_args_refused: --title with no value exits 64" "$([ "$SRC" -eq 64 ]; echo $?)"
ship_go "$C5" docs/a5-nomsg --carry note5.md --message-file "$MSG" --draft --proof-override "reason"
chk "ship_args_refused: a refused run logged no override" "$([ "$(ovr_count)" = "$(( n0 + 1 ))" ]; echo $?)"
args_clean "ship_args_refused" docs/a5-nomsg
SOUT="$("$WRAP" ship 2>&1)"; SRC=$?
chk "ship_args_refused: no arguments exits 64 with usage" "$([ "$SRC" -eq 64 ]; echo $?)"
chk_has "ship_args_refused: the usage names the verb" "$SOUT" "usage: wrap.sh ship"

# ===========================================================================
echo "=== ship: preflight refusals, before any write (AC-8, AC-9) ==="
# ===========================================================================
C8="$(ship_clone p8)"
ship_go "$C8" docs/ship-clean --carry docs/keep.md --message-file "$MSG"
chk "ship_nothing_to_ship: exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_nothing_to_ship: the SHIP line says preflight" "$(last_line)" "SHIP: refused (preflight, exit 1) worktree=none"
chk_has "ship_nothing_to_ship: names the reason" "$SOUT" "nothing to ship"
chk "ship_nothing_to_ship: no worktree" "$([ ! -e "$(sw "$C8" docs/ship-clean)" ]; echo $?)"
chk "ship_nothing_to_ship: no branch" "$(no_branch "$C8" docs/ship-clean | grep -qx 0 && echo 0 || echo 1)"

C9="$(ship_clone t9 tpl)"
echo "n" > "$C9/note9.md"
ship_go "$C9" docs/ship-tpl --carry note9.md --message-file "$MSG"
chk "ship_template_needs_body: exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_template_needs_body: names the template" "$SOUT" "pull_request_template.md exists, so a title-only PR body is not allowed"
chk "ship_template_needs_body: no worktree" "$([ ! -e "$(sw "$C9" docs/ship-tpl)" ]; echo $?)"
printf '## What\nthe note\n' > "$TMPD/ship-body.md"
: > "$GH_STUB_CALLS"
ship_go "$C9" docs/ship-tpl --carry note9.md --message-file "$MSG" --body-file "$TMPD/ship-body.md"
chk "ship_template_needs_body: with --body-file the run ships" "$([ "$SRC" -eq 0 ]; echo $?)"
chk "ship_template_needs_body: gh pr create got the body file" \
  "$(grep -q 'pr create .*--body-file '"$TMPD_P"'/ship-body.md' "$GH_STUB_CALLS" && echo 0 || echo 1)"

# ===========================================================================
echo "=== ship: start's refusals pass through (AC-10, AC-11) ==="
# ===========================================================================
C10="$(ship_clone s10)"
echo "n" > "$C10/note10.md"
BASE10="$(git -C "$C10" rev-parse main)"
ship_go "$C10" main --carry note10.md --message-file "$MSG"
chk "ship_inherits_start_refusals: the default branch name exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_inherits_start_refusals: start's own message" "$SOUT" "main is the default or a protected branch name"
chk_has "ship_inherits_start_refusals: the step is start" "$(last_line)" "SHIP: refused (start, exit 1) worktree=none"
git -C "$C10" branch docs/exists
ship_go "$C10" docs/exists --carry note10.md --message-file "$MSG"
chk "ship_inherits_start_refusals: an existing branch exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_inherits_start_refusals: start's own message (branch)" "$SOUT" "branch docs/exists already exists in"
chk_has "ship_inherits_start_refusals: the step is start (branch)" "$(last_line)" "SHIP: refused (start, exit 1)"
mkdir -p "$C10/.claude/worktrees/pathx"
ship_go "$C10" docs/pathx --carry note10.md --message-file "$MSG"
chk "ship_inherits_start_refusals: an existing worktree path exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_inherits_start_refusals: start's own message (path)" "$SOUT" ".claude/worktrees/pathx already exists"
chk "ship_inherits_start_refusals: no commit anywhere" \
  "$([ "$(git -C "$C10" rev-parse main)" = "$BASE10" ] && [ "$(git -C "$C10" rev-parse docs/exists)" = "$BASE10" ]; echo $?)"
chk "ship_inherits_start_refusals: the carry file is still in main" "$([ -f "$C10/note10.md" ]; echo $?)"
chk "ship_inherits_start_refusals: the main checkout's index is clean" "$([ -z "$(git -C "$C10" diff --cached --name-only)" ]; echo $?)"

C11="$(ship_clone k11)"
git clone -q "$TMPD/sbare-k11" "$TMPD/sp-k11"; gitc "$TMPD/sp-k11"
echo "origin side" > "$TMPD/sp-k11/a.txt"; git -C "$TMPD/sp-k11" commit -qam "origin edits a"; git -C "$TMPD/sp-k11" push -q origin main
echo "local side" > "$C11/a.txt"
ship_go "$C11" docs/ship-conflict --carry a.txt --message-file "$MSG"
chk "ship_carry_conflict_stops: exits 2 (start's code)" "$([ "$SRC" -eq 2 ]; echo $?)"
chk_has "ship_carry_conflict_stops: the step is carry, with the worktree named" "$(last_line)" "SHIP: refused (carry, exit 2) worktree=$(sw "$C11" docs/ship-conflict)"
chk "ship_carry_conflict_stops: no commit past origin" \
  "$([ "$(git -C "$C11" rev-list --count origin/main..docs/ship-conflict)" = 0 ]; echo $?)"

# ===========================================================================
echo "=== ship: never a commit on the default branch (AC-12) ==="
# ===========================================================================
C12="$(ship_clone d12)"
echo "n" > "$C12/note12.md"
BASE12="$(git -C "$C12" rev-parse main)"
SOUT="$( ( source "$KIT_DIR/lib/wrap/wrap.sh" >/dev/null 2>&1
           cmd_start() { printf '%s\n' "$C12"; return 0; }
           cmd_ship "$C12" docs/ship-def --carry note12.md --message-file "$MSG" ) 2>&1 )"; SRC=$?
chk "ship_never_commits_on_default: exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_never_commits_on_default: the step is branch" "$(last_line)" "SHIP: refused (branch, exit 1)"
chk "ship_never_commits_on_default: the default ref did not move" "$([ "$(git -C "$C12" rev-parse main)" = "$BASE12" ]; echo $?)"
chk "ship_never_commits_on_default: nothing was staged" "$([ -z "$(git -C "$C12" diff --cached --name-only)" ]; echo $?)"

# ===========================================================================
echo "=== ship: the committed diff must stay inside the carry set (AC-13) ==="
# ===========================================================================
C13="$(ship_clone g13)"
echo "n" > "$C13/note13.md"
ship_hook "$C13" pre-commit 'echo extra > extra.txt; git add extra.txt'
n0="$(ovr_count)"
ship_go "$C13" docs/ship-guard --carry note13.md --message-file "$MSG" --proof-override "docs only"
chk "ship_guard_committed_diff: exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_guard_committed_diff: the step is guard, worktree kept" "$(last_line)" "SHIP: refused (guard, exit 1) worktree=$(sw "$C13" docs/ship-guard)"
chk_has "ship_guard_committed_diff: names the out-of-set path" "$SOUT" "the commit holds extra.txt, outside the carried paths"
chk "ship_guard_committed_diff: nothing pushed" "$(git -C "$TMPD/sbare-g13" show-ref --verify --quiet refs/heads/docs/ship-guard && echo 1 || echo 0)"
chk "ship_guard_committed_diff: no override logged" "$([ "$(ovr_count)" = "$n0" ]; echo $?)"
chk "ship_guard_committed_diff: no resume line (a land would push the stray file)" \
  "$(printf '%s\n' "$SOUT" | grep -q '^resume:' && echo 1 || echo 0)"

# A commit hook that rejects stops at the commit step.
C13B="$(ship_clone g13b)"
echo "n" > "$C13B/note13.md"
ship_hook "$C13B" commit-msg 'echo "format hook says no" >&2; exit 1'
ship_go "$C13B" docs/ship-hook --carry note13.md --message-file "$MSG"
chk "ship_commit_hook_rejects: exits 1" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_commit_hook_rejects: the step is commit" "$(last_line)" "SHIP: refused (commit, exit 1)"
chk_has "ship_commit_hook_rejects: the hook's own words show" "$SOUT" "format hook says no"
chk "ship_commit_hook_rejects: the worktree is kept" "$([ -d "$(sw "$C13B" docs/ship-hook)" ]; echo $?)"

# ===========================================================================
echo "=== ship: land's refusals pass through with their code (AC-14) ==="
# ===========================================================================
C14="$(ship_clone l14)"
echo "n" > "$C14/note14.md"
ship_hook "$C14" pre-push 'echo "gate says no" >&2; exit 1'
n0="$(ovr_count)"
ship_go "$C14" docs/ship-land --carry note14.md --message-file "$MSG" --title "docs: t 14" --no-pull --proof-override "SECRETTOKEN-9931"
chk "ship_inherits_land_refusals: exits with the push's code (1)" "$([ "$SRC" -eq 1 ]; echo $?)"
chk_has "ship_inherits_land_refusals: the step is land:push" "$(last_line)" "SHIP: refused (land:push, exit 1) worktree=$(sw "$C14" docs/ship-land)"
chk_has "ship_inherits_land_refusals: land's own LAND: line is printed" "$SOUT" "LAND: refused (push, exit 1)"
chk_has "ship_inherits_land_refusals: land's own refusal text is printed" "$SOUT" "PUSH REFUSED"
chk_has "ship_inherits_land_refusals: a resume line carries the flags" "$SOUT" "resume: wrap land $(sw "$C14" docs/ship-land) --title docs:\\ t\\ 14 --no-pull"
chk "ship_inherits_land_refusals: the override reason is in no output" \
  "$(printf '%s\n' "$SOUT" | grep -q 'SECRETTOKEN-9931' && echo 1 || echo 0)"
chk "ship_inherits_land_refusals: the override was logged once, before the refusal" "$([ "$(ovr_count)" = "$(( n0 + 1 ))" ]; echo $?)"
chk "ship_inherits_land_refusals: the worktree is kept" "$([ -d "$(sw "$C14" docs/ship-land)" ]; echo $?)"
chk "ship_inherits_land_refusals: the commit is on the branch, not on main" \
  "$([ "$(git -C "$C14" rev-list --count origin/main..docs/ship-land)" = 1 ] && [ "$(git -C "$C14" rev-parse main)" = "$(git -C "$C14" rev-parse origin/main)" ]; echo $?)"

# ===========================================================================
echo "=== ship: land's final kind maps to one honest outcome ==="
# ===========================================================================
# ship never passes --draft (it rejects the flag), so land can never end in kind `draft`
# through ship. The mapping is a function so each kind is checked without a full ship run.
fin() { ( source "$KIT_DIR/lib/wrap/wrap-ship.sh"; _LAND_KIND="$1" _LAND_REF="#7" _LAND_PULL=ok _LAND_WT=removed _LAND_STEP=done _SHIP_FINAL=""
          _ship_final; rc=$?; echo "rc=$rc final=${_SHIP_FINAL}" ) 2>&1; }
out="$(fin merged)"
chk_has "ship_final: merged maps to shipped" "$out" "rc=0 final=shipped #7 pull=ok worktree=removed"
out="$(fin already)"
chk_has "ship_final: already maps to already landed" "$out" "rc=0 final=already landed (#7)"
out="$(fin draft)"
chk_has "ship_final: draft is an explicit error naming the kind" "$out" "unexpected land outcome 'draft'"
chk_has "ship_final: draft returns 1 with no final line" "$out" "rc=1 final="
out="$(fin "")"
chk_has "ship_final: an empty kind is an explicit error too" "$out" "unexpected land outcome ''"

# ===========================================================================
echo "=== ship: the verb is documented (AC-16) ==="
# ===========================================================================
out="$("$WRAP" --help 2>&1)"
chk "ship_docs_name_verb: --help lists the verb once" "$([ "$(printf '%s\n' "$out" | grep -c 'wrap.sh ship')" = 1 ]; echo $?)"
for f in commands/wrap.md docs/reference/wrap.md lib/wrap/README.md docs/MANUAL.md; do
  chk "ship_docs_name_verb: $f names wrap ship" "$(grep -q 'wrap ship' "$KIT_DIR/$f" && echo 0 || echo 1)"
done

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-ship: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-ship: all $PASS passed"

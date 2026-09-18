#!/usr/bin/env bash
# test-board-row-gate.sh -- behavior tests for the board-row-gate PreToolUse hook.
# Each case stages real content in a scratch repo, feeds the hook a Bash tool payload
# (command + cwd), and asserts the verdict: allow (exit 0) or block (exit 2).
#
# Hermetic: HOME, the log dir, and every repo live under one temp dir.
# HOOK_BASH=/bin/bash runs the hook under macOS bash 3.2 instead of the PATH bash.
set -u

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$KIT_DIR/hooks/board-row-gate.sh"
[ -r "$HOOK" ] || { echo "ERROR: hook not found at $HOOK" >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/dwarves-kit-board-row-gate.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export DWARVES_KIT_LOG_DIR="$T/logs"
unset DWARVES_KIT_SKIP_BOARD_ROW_GATE
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@t.t; git config --global user.name t
git config --global init.defaultBranch main

PASS=0
FAIL=0
LAST_ERR=""

# check <label> <expect: allow|block> <cwd> <command>
check() {
  local label="$1" expect="$2" cwd="$3" cmd="$4" rc actual
  LAST_ERR=$(jq -cn --arg c "$cmd" --arg d "$cwd" \
      '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' | "${HOOK_BASH:-bash}" "$HOOK" 2>&1 >/dev/null)
  rc=$?
  case "$rc" in 0) actual=allow ;; 2) actual=block ;; *) actual="exit=$rc" ;; esac
  if [ "$actual" = "$expect" ]; then
    PASS=$((PASS + 1)); printf '  PASS %-58s %s\n' "$label" "$actual"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %-58s expected=%s actual=%s\n' "$label" "$expect" "$actual"
    [ -n "$LAST_ERR" ] && printf '%s\n' "$LAST_ERR" | sed 's/^/       /'
  fi
}

row() { printf '| %s | item | %s | %s |\n' "$1" "${3:-notes}" "${2:-queued}"; }  # id status notes

# mkrepo <dir> <board path> <prefix>: a repo whose HEAD board holds <prefix>-001 and -002.
mkrepo() {
  mkdir -p "$1/$(dirname "$2")"
  git init -q "$1"
  { printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n'
    row "$3-001"; row "$3-002"; } > "$1/$2"
  git -C "$1" add -A && git -C "$1" commit -qm base
}
reset_repo() { git -C "$1" reset -q; git -C "$1" checkout -q -- .; git -C "$1" clean -qfd; }
add_row() { row "$3" >> "$1/$2"; git -C "$1" add "$2"; }   # repo board id -> staged new row

R="$T/repo-id";      mkrepo "$R" _meta/BACKLOG.md ID
DF="$T/repo-df";     mkrepo "$DF" _meta/BACKLOG.md DF
FO="$T/repo-fo";     mkrepo "$FO" _meta/BACKLOG.md FO
ROOTB="$T/repo-root-board"; mkrepo "$ROOTB" BACKLOG.md TR
PLAIN="$T/repo-plain"; mkdir -p "$PLAIN"; git init -q "$PLAIN"; echo x > "$PLAIN/a"; git -C "$PLAIN" add -A; git -C "$PLAIN" commit -qm base
SPACED="$T/dir with space"; mkrepo "$SPACED" _meta/BACKLOG.md ID
NOWHERE="$T/not-a-repo"; mkdir -p "$NOWHERE"
B=_meta/BACKLOG.md

echo "== Non-commit commands and repos without a board never engage =="
add_row "$R" "$B" ID-003
check "1.1 ls"                                            allow "$R" "ls -la"
check "1.2 git status with a new row staged"              allow "$R" "git status"
check "1.3 git log --grep commit"                         allow "$R" "git log --grep commit"
check "1.4 a commit in a repo with no board"              allow "$PLAIN" "git commit -m 'feat: x'"
check "1.5 a commit outside any repo"                     allow "$NOWHERE" "git commit -m 'feat: x'"

echo "== New row: the marker decides =="
check "2.1 new row, no marker BLOCKS"                     block "$R" "git commit -m 'docs(board): file ID-003'"
case "$LAST_ERR" in *ID-003*board-row-ok*) PASS=$((PASS+1)); echo "  PASS 2.1b block names the ID and the marker" ;;
  *) FAIL=$((FAIL+1)); echo "  FAIL 2.1b block text missing the ID or the marker" ;; esac
check "2.2 marker as its own -m"                          allow "$R" "git commit -m 'docs(board): file ID-003' -m 'board-row-ok: Han asked for it'"
check "2.3 marker, double quotes, --message="             allow "$R" "git commit -m \"docs: x\" --message=\"board-row-ok: vendor blocker\""
check "2.4 marker via a literal \\n inside one -m BLOCKS" block "$R" 'git commit -m "docs: x\n\nboard-row-ok: y"'
check "2.5 marker via \$'...' with a real newline"         allow "$R" "git commit -m \$'docs: x\n\nboard-row-ok: y'"
check "2.6 empty reason BLOCKS"                           block "$R" "git commit -m 'docs: x' -m 'board-row-ok: '"
check "2.7 marker text in an unrelated earlier segment"   block "$R" "echo 'board-row-ok: x' && git commit -m 'docs: x'"

echo "== Heredoc messages (the agent commit shape) =="
# shellcheck disable=SC2016  # the command text must stay literal
HD_OK=$(printf '%s\n' 'git commit -m "$(cat <<'"'"'EOF'"'"'' 'docs(board): file a "quoted" row' '' 'board-row-ok: blocked on the vendor' 'EOF' ')"')
# shellcheck disable=SC2016
HD_NO=$(printf '%s\n' 'git commit -m "$(cat <<'"'"'EOF'"'"'' 'docs(board): file a row' '' 'Body text only.' 'EOF' ')"')
HD_STDIN=$(printf '%s\n' "git commit -F - <<EOF" 'docs: x' '' 'board-row-ok: Han asked' 'EOF')
check "3.1 heredoc body with the marker"                  allow "$R" "$HD_OK"
check "3.2 heredoc body without the marker BLOCKS"        block "$R" "$HD_NO"
check "3.3 -F - fed by a heredoc with the marker"         allow "$R" "$HD_STDIN"

echo "== Unreadable message fails closed only when new IDs exist =="
check "4.1 editor commit with a new row BLOCKS"           block "$R" "git commit"
case "$LAST_ERR" in *"could not be read"*) PASS=$((PASS+1)); echo "  PASS 4.1b block says the message could not be read" ;;
  *) FAIL=$((FAIL+1)); echo "  FAIL 4.1b block text does not name the unreadable message" ;; esac
printf 'docs: x\n\nboard-row-ok: Han asked\n' > "$T/msg-ok.txt"
printf 'docs: x\n' > "$R/msg-no.txt"
check "4.2 -F file with the marker"                       allow "$R" "git commit -F $T/msg-ok.txt"
check "4.3 -F relative file without the marker BLOCKS"    block "$R" "git commit -F msg-no.txt"
check "4.4 -F file that does not exist yet BLOCKS"        block "$R" "printf x > m.txt && git commit -F $T/missing.txt"
rm -f "$R/msg-no.txt"
reset_repo "$R"
check "4.5 editor commit with no board change"            allow "$R" "git commit"

echo "== Existing rows: flips, moves, and cited IDs add nothing =="
{ printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n'; row ID-001 shipped; row ID-002; } > "$R/$B"; git -C "$R" add "$B"
check "5.1 status flip of an existing row"                allow "$R" "git commit -m 'docs(board): close ID-001'"
reset_repo "$R"
{ printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n'; row ID-002; row ID-001; } > "$R/$B"; git -C "$R" add "$B"
check "5.2 moved existing row"                            allow "$R" "git commit -m 'docs(board): reorder'"
reset_repo "$R"
{ printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n'; row ID-001 shipped "closes once ID-999 ships"; row ID-002; } > "$R/$B"; git -C "$R" add "$B"
check "5.3 Notes citing an unknown ID"                    allow "$R" "git commit -m 'docs(board): close ID-001'"
reset_repo "$R"

echo "== Prefix-agnostic IDs =="
add_row "$DF" "$B" DF-003
check "6.1 DF- new row BLOCKS"                            block "$DF" "git commit -m 'docs: x'"
check "6.2 DF- new row with the marker"                   allow "$DF" "git commit -m 'docs: x' -m 'board-row-ok: asked'"
add_row "$FO" "$B" FO-017
check "6.3 FO- new row BLOCKS"                            block "$FO" "git commit -m 'docs: x'"
add_row "$ROOTB" BACKLOG.md TR-009
check "6.4 root BACKLOG.md board, TR- new row BLOCKS"     block "$ROOTB" "git commit -m 'docs: x'"

echo "== Target repo resolution =="
check "7.1 git -C <repo> from outside any repo BLOCKS"    block "$NOWHERE" "git -C $DF commit -m 'docs: x'"
check "7.2 git -C <repo> from a board-less repo BLOCKS"   block "$PLAIN" "git -C $FO commit -m 'docs: x'"
check "7.3 git -C <repo-without-board> from a board repo" allow "$DF" "git -C $PLAIN commit -m 'docs: x'"
add_row "$SPACED" "$B" ID-005
check "7.4 quoted git -C path with a space BLOCKS"        block "$NOWHERE" "git -C \"$SPACED\" commit -m 'docs: x'"
check "7.5 cd <repo> && git commit BLOCKS"                block "$NOWHERE" "cd $DF && git commit -m 'docs: x'"
check "7.6 cd <board-less repo> && git commit"            allow "$DF" "cd $PLAIN && git commit -m 'docs: x'"
check "7.7 cd \$VAR (ambiguous) checks the cwd repo"      block "$DF" "cd \"\$REPO\" && git commit -m 'docs: x'"
check "7.8 git -c key=val -C <repo> commit BLOCKS"        block "$NOWHERE" "git -c core.hooksPath=/dev/null -C $FO commit -m 'docs: x'"

echo "== What the commit takes: index, -a, pathspec =="
reset_repo "$R"; row ID-004 >> "$R/$B"; echo y > "$R/other"; git -C "$R" add other
check "8.1 unstaged new row, other file committed"        allow "$R" "git commit -m 'feat: other'"
check "8.2 -am takes the unstaged new row, BLOCKS"        block "$R" "git commit -am 'feat: other'"
check "8.3 --all with the marker"                         allow "$R" "git commit --all -m 'feat: x' -m 'board-row-ok: asked'"
check "8.4 pathspec naming the board BLOCKS"              block "$R" "git commit -m 'docs: x' -- _meta/BACKLOG.md"
reset_repo "$R"

echo "== Merge, rebase, cherry-pick, no HEAD, kill switch =="
add_row "$R" "$B" ID-006
GD=$(git -C "$R" rev-parse --absolute-git-dir)
touch "$GD/MERGE_HEAD";       check "9.1 merge in progress"          allow "$R" "git commit --no-edit"; rm -f "$GD/MERGE_HEAD"
mkdir "$GD/rebase-merge";     check "9.2 rebase in progress"         allow "$R" "git commit -m 'x'";   rmdir "$GD/rebase-merge"
touch "$GD/CHERRY_PICK_HEAD"; check "9.3 cherry-pick in progress"    allow "$R" "git commit -m 'x'";   rm -f "$GD/CHERRY_PICK_HEAD"
check "9.4 same staged row, no special state, BLOCKS"                block "$R" "git commit -m 'x'"
DWARVES_KIT_SKIP_BOARD_ROW_GATE=1 check "9.5 kill switch"            allow "$R" "git commit -m 'x'"
NH="$T/repo-nohead"; mkdir -p "$NH/_meta"; git init -q "$NH"; row ID-001 > "$NH/$B"; git -C "$NH" add -A
check "9.6 first commit (no HEAD) skips"                             allow "$NH" "git commit -m 'x'"

echo "== Review regressions: same-call staging, pathspecs, command position, segment scope =="
reset_repo "$R"; row ID-007 >> "$R/$B"; echo y > "$R/other"
check "11.1 git add -A && git commit (row unstaged) BLOCKS"      block "$R" "git add -A && git commit -m 'docs: x'"
check "11.2 git add <board> && git commit BLOCKS"                block "$R" "git add _meta/BACKLOG.md && git commit -m 'docs: x'"
check "11.3 git add <other> && git commit, row unstaged"         allow "$R" "git add other && git commit -m 'feat: other'"
check "11.4 pathspec . covers the board BLOCKS"                  block "$R" "git commit -m 'docs: x' ."
check "11.5 pathspec _meta covers the board BLOCKS"              block "$R" "git commit -m 'docs: x' _meta"
git -C "$R" add "$B" other
check "11.6 pathspec -- <other> leaves the staged board out"     allow "$R" "git commit -m 'feat: o' -- other"
check "11.7 commit text inside an echo string"                   allow "$R" "echo 'remember to git commit later'"
check "11.8 /usr/bin/git commit BLOCKS"                          block "$R" "/usr/bin/git commit -m 'docs: x'"
check "11.9 GIT_EDITOR=true git commit BLOCKS"                   block "$R" "GIT_EDITOR=true git commit -m 'docs: x'"
check "11.10 marker in a later echo -m BLOCKS"                   block "$R" "git commit -m 'docs: x' && echo -m 'board-row-ok: y'"
check "11.11 marker in a later heredoc BLOCKS"                   block "$R" "$(printf '%s\n' "git commit -m 'docs: x' && cat <<EOF" 'board-row-ok: y' 'EOF')"
check "11.12 here-string is not a heredoc BLOCKS"                block "$R" "$(printf '%s\n' "git commit -m 'docs: x' <<<\"EOF\"" 'board-row-ok: y' 'EOF')"
# shellcheck disable=SC2016
check "11.13 nested quotes in -m never read as a pathspec"       block "$R" 'git commit -m "$(printf "%s" "docs: x")"'
check "11.14 redirect target is not a pathspec BLOCKS"           block "$R" "git commit -m 'docs: x' > $T/commit.log"
check "11.15 -F /dev/zero with a new row blocks, no hang"        block "$R" "git commit -F /dev/zero"
reset_repo "$R"
check "11.16 -F /dev/zero with no board change, no hang"         allow "$R" "git commit -F /dev/zero"
row ID-008 >> "$R/$B"; git -C "$R" add "$B"; git -C "$R" commit -qm 'docs: row' -m 'board-row-ok: fixture'
check "11.17 --amend --no-edit over a row HEAD added BLOCKS"     block "$R" "git commit --amend --no-edit"
check "11.18 --amend with the marker"                            allow "$R" "git commit --amend -m 'docs: row' -m 'board-row-ok: asked'"
git -C "$R" reset -q --hard HEAD^

echo "== Log =="
if grep -q '| BLOCKED |' "$DWARVES_KIT_LOG_DIR/board-row-gate.log" 2>/dev/null \
   && grep -q '| MARKER |' "$DWARVES_KIT_LOG_DIR/board-row-gate.log"; then
  PASS=$((PASS+1)); echo "  PASS 10.1 blocks and marker passes are logged"
else
  FAIL=$((FAIL+1)); echo "  FAIL 10.1 log missing BLOCKED or MARKER lines"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

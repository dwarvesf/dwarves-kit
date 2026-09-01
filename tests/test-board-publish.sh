#!/usr/bin/env bash
# test-board-publish.sh -- `board publish`, the git leg of SPEC-002's
# intake -> publish -> relay sequencing (ops-toolkit ID-638).
#
# Proves:
#   AC1  a spoke-dirtied board file is committed (chore(board) subject) and
#        pushed to the remote; ONLY the board file is staged (other dirt stays)
#   AC2  no board changes -> no commit, exit 0
#   AC3  a worktree checkout path is refused (same fence as sync)
#   AC4  push failure (no remote) keeps the local commit and warns, exit 0
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BOARD_SH="$HERE/../lib/board/board.sh"
WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

mkrepo() {  # <dir> ; creates repo with _meta/BACKLOG.md + a bare origin
  local d="$1"
  git init -q -b main "$d"
  mkdir -p "$d/_meta"
  printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n| ID-1 | thing | notes | queued |\n' > "$d/_meta/BACKLOG.md"
  git -C "$d" -c user.email=t@t -c user.name=t add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init
  git init -q --bare "$d.remote"
  git -C "$d" remote add origin "$d.remote"
  git -C "$d" push -q -u origin main
}

echo "case AC1 (dirty board -> committed + pushed; other dirt untouched):"
mkrepo "$WORK/r1"
printf '| ID-2 | new row | from spoke | queued |\n' >> "$WORK/r1/_meta/BACKLOG.md"
echo scratch > "$WORK/r1/other.txt"
out="$(cd "$WORK/r1" && GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_NAME=t \
  bash "$BOARD_SH" publish --backlog-file "$WORK/r1/_meta/BACKLOG.md" 2>&1)"
git -C "$WORK/r1" log -1 --format=%s | grep -q "chore(board): publish spoke updates" \
  && ok "board commit created" || bad "no publish commit: $(git -C "$WORK/r1" log -1 --format=%s)"
git -C "$WORK/r1.remote" log -1 --format=%s main 2>/dev/null | grep -q "chore(board)" \
  && ok "pushed to origin" || bad "remote missing the publish commit"
git -C "$WORK/r1" status --porcelain | grep -q "other.txt" \
  && ok "unrelated dirt left untouched" || bad "unrelated file was swept into the commit"
echo "$out" | grep -q "pushed" && ok "reports pushed" || bad "no pushed report: $out"

echo "case AC2 (clean board -> no commit):"
before="$(git -C "$WORK/r1" rev-parse HEAD)"
out="$(cd "$WORK/r1" && bash "$BOARD_SH" publish --backlog-file "$WORK/r1/_meta/BACKLOG.md" 2>&1)"
[ "$(git -C "$WORK/r1" rev-parse HEAD)" = "$before" ] \
  && ok "HEAD unchanged" || bad "a commit appeared with no board changes"
echo "$out" | grep -q "no board changes" && ok "honest no-op report" || bad "no no-op report: $out"

echo "case AC3 (worktree path refused):"
mkdir -p "$WORK/r2/.claude/worktrees/x/_meta"
printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n' > "$WORK/r2/.claude/worktrees/x/_meta/BACKLOG.md"
out="$(bash "$BOARD_SH" publish --backlog-file "$WORK/r2/.claude/worktrees/x/_meta/BACKLOG.md" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "nonzero exit" || bad "worktree path accepted (rc=0)"
echo "$out" | grep -q "refusing a worktree" && ok "refusal names the fence" || bad "no refusal message: $out"

echo "case AC4 (push failure -> commit kept, warn, exit 0):"
mkrepo "$WORK/r3"
command rm -rf "$WORK/r3.remote"   # kill the remote so push fails
printf '| ID-3 | another row | x | queued |\n' >> "$WORK/r3/_meta/BACKLOG.md"
out="$(cd "$WORK/r3" && GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_NAME=t \
  bash "$BOARD_SH" publish --backlog-file "$WORK/r3/_meta/BACKLOG.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on push failure (commit preserved)" || bad "nonzero exit: $rc"
git -C "$WORK/r3" log -1 --format=%s | grep -q "chore(board)" \
  && ok "local commit kept" || bad "no local commit after push failure"
echo "$out" | grep -q "WARN push failed" && ok "push failure warns honestly" || bad "no push warning: $out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

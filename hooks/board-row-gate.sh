#!/usr/bin/env bash
# board-row-gate.sh, PreToolUse hook, matcher: Bash
# Blocks a `git commit` that adds a NEW board row unless the commit message carries a
# `board-row-ok: <reason>` line. Follow-ups are done in the session or dropped into its
# report; a row needs the operator's ask or an outside blocker (AGENTS.md zone 2, step 0).
# Source: ops-toolkit .githooks/board-row-gate (a git commit-msg hook). This is the same
# rule as a CC hook, so every repo with a board is covered with no per-repo install.
#
# Board: <repo>/_meta/BACKLOG.md, else <repo>/BACKLOG.md. A new row is a first-cell ID
# (^[A-Z][A-Z0-9]*-[0-9]+$, any prefix) in the content being committed that HEAD's board
# lacks. IDs cited in other cells never count. Status flips and moved rows add no ID.
# Repo: `git -C <path>` wins, then a resolvable `cd <path>` earlier in the command, else
# the session cwd. Merge, rebase, and cherry-pick states skip. No HEAD yet skips.
# Message: -m/--message values, heredoc bodies, and -F/--file files in the command. A
# message that cannot be read blocks, but only when new IDs exist.
# Kill switch: DWARVES_KIT_SKIP_BOARD_ROW_GATE=1 in the session env. Exit 2 = block.

set -uo pipefail
[ "${DWARVES_KIT_SKIP_BOARD_ROW_GATE:-0}" = "1" ] && exit 0
INPUT=$(cat 2>/dev/null) || exit 0
case "$INPUT" in *git*commit*) ;; *) exit 0 ;; esac   # fast path: no jq fork for most commands
command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
case "$CMD" in *git*commit*) ;; *) exit 0 ;; esac

Q="'"
DQ='"([^"\\]|\\.)*"'                     # a double-quoted word
SQ="${Q}[^${Q}]*${Q}"                    # a single-quoted word
WORD="($DQ|$SQ|[^[:space:];&|]+)"
GIT_RE="(^|[;&|({[:space:]])git(([[:space:]]+-[Cc][[:space:]]+$WORD)|([[:space:]]+--?[A-Za-z][-A-Za-z]*(=[^[:space:]]*)?))*[[:space:]]+commit([[:space:]]|$)"
[[ "$CMD" =~ $GIT_RE ]] || exit 0
MATCH="${BASH_REMATCH[0]}"
PRE="${CMD%%"$MATCH"*}"
POST="${CMD#*"$MATCH"}"

unquote() {  # strip one layer of quotes and expand a leading ~
  local w="$1"
  case "$w" in \"*\") w="${w#\"}"; w="${w%\"}" ;; "$Q"*"$Q") w="${w#"$Q"}"; w="${w%"$Q"}" ;; esac
  # shellcheck disable=SC2088  # matching a literal ~ in the command text, not expanding one
  case "$w" in "~") w="$HOME" ;; "~/"*) w="$HOME/${w#"~/"}" ;; esac
  printf '%s' "$w"
}
join() { case "$2" in /*) printf '%s' "$2" ;; *) printf '%s/%s' "$1" "$2" ;; esac; }

# Resolve the directory git runs in. An unresolvable cd ($VAR, a missing dir) falls back
# to the cwd: ambiguous means check the session repo.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
DIR="$CWD"
CD_RE="(^|[;&|({[:space:]])cd[[:space:]]+$WORD"
rest="$PRE"
while [[ "$rest" =~ $CD_RE ]]; do
  p=$(unquote "${BASH_REMATCH[2]}")
  rest="${rest#*"${BASH_REMATCH[0]}"}"
  case "$p" in *'$'*|*'`'*) DIR="$CWD"; break ;; esac
  p=$(join "$DIR" "$p")
  if [ -d "$p" ]; then DIR="$p"; else DIR="$CWD"; break; fi
done
rest="$MATCH"
C_RE="[[:space:]]-C[[:space:]]+$WORD"
while [[ "$rest" =~ $C_RE ]]; do
  DIR=$(join "$DIR" "$(unquote "${BASH_REMATCH[1]}")")
  rest="${rest#*"${BASH_REMATCH[0]}"}"
done

ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
BOARD=""
for b in _meta/BACKLOG.md BACKLOG.md; do [ -f "$ROOT/$b" ] && { BOARD="$b"; break; }; done
[ -n "$BOARD" ] || exit 0
GITDIR=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$GITDIR/$f" ] && exit 0
done
git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0

# Split heredoc bodies (message text) from the rest (argument text).
heredoc() {  # $1 = body|rest, stdin = text
  awk -v mode="$1" '
    d != "" { t = $0; sub(/^\t+/, "", t)
              if (t == d) { d = ""; if (mode == "rest") print; next }
              if (mode == "body") print; next }
    { if (mode == "rest") print
      if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
        d = substr($0, RSTART, RLENGTH); sub(/^<<-?[ \t]*["\047]?/, "", d) } }'
}
MSG=$(printf '%s\n' "$POST" | heredoc body)
ARGS=$(printf '%s\n' "$POST" | heredoc rest)
FOUND=0; [ -n "$MSG" ] && FOUND=1

# -m / --message values (repeatable; a short cluster like -am counts).
M_RE="(^|[[:space:]])(-[A-Za-z]*m|--message)(=|[[:space:]]*)(\"(([^\"\\\\]|\\\\.)*)\"|\\\$$Q(([^$Q\\\\]|\\\\.)*)$Q|$Q([^$Q]*)$Q|([^[:space:]\"$Q;&|]+))"
rest="$ARGS"
while [[ "$rest" =~ $M_RE ]]; do
  FOUND=1
  if   [ -n "${BASH_REMATCH[5]}" ]; then v="${BASH_REMATCH[5]}"
  elif [ -n "${BASH_REMATCH[7]}" ]; then v=$(printf '%b' "${BASH_REMATCH[7]}")
  elif [ -n "${BASH_REMATCH[9]}" ]; then v="${BASH_REMATCH[9]}"
  else v="${BASH_REMATCH[10]}"; fi
  MSG="$MSG"$'\n'"$v"
  ARGS="${ARGS/"${BASH_REMATCH[0]}"/ ${BASH_REMATCH[2]} }"   # keep the flag (-am), drop the value
  rest="${rest#*"${BASH_REMATCH[0]}"}"
done
# -F / --file: read the file git would read. `-F -` is stdin, covered by the heredoc body.
F_RE="(^|[[:space:]])(-[A-Za-z]*F|--file)(=|[[:space:]]+)$WORD"
rest="$ARGS"
while [[ "$rest" =~ $F_RE ]]; do
  p=$(unquote "${BASH_REMATCH[4]}")
  rest="${rest#*"${BASH_REMATCH[0]}"}"
  [ "$p" = "-" ] && continue
  p=$(join "$DIR" "$p")
  [ -r "$p" ] && { FOUND=1; MSG="$MSG"$'\n'"$(cat "$p")"; }
done

# The commit's own arguments end at the first control operator. -a/--all or a pathspec
# naming the board commits the working-tree file; otherwise the index is what lands.
ARGS=$(printf '%s' "$ARGS" | tr -d "\"$Q" | tr '\n' ';'); ARGS="${ARGS%%[;&|]*}"
SRC=":$BOARD"
A_RE='[[:space:]](-[A-Za-z]*a[A-Za-z]*|--all)[[:space:]]'
[[ " $ARGS " =~ $A_RE ]] && SRC=""
case "$ARGS" in *BACKLOG.md*) SRC="" ;; esac

ids() { sed -nE 's/^\|[[:space:]]*([A-Z][A-Z0-9]*-[0-9]+)[[:space:]]*\|.*/\1/p' | sort -u; }
if [ -n "$SRC" ]; then STAGED=$(git -C "$ROOT" show "$SRC" 2>/dev/null | ids)
else STAGED=$(ids < "$ROOT/$BOARD"); fi
[ -n "$STAGED" ] || exit 0
HEADIDS=$(git -C "$ROOT" show "HEAD:$BOARD" 2>/dev/null | ids)
NEW=$(comm -23 <(printf '%s\n' "$STAGED") <(printf '%s\n' "$HEADIDS") | tr '\n' ' ')
NEW="${NEW% }"
[ -n "$NEW" ] || exit 0

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
_log() { mkdir -p "$LOG_DIR" 2>/dev/null && printf '%s | %s | %s | %s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$ROOT" "$NEW" >> "$LOG_DIR/board-row-gate.log" 2>/dev/null || true; }
if printf '%s\n' "$MSG" | grep -qE '^board-row-ok: .+'; then _log MARKER; exit 0; fi
_log BLOCKED

if [ "$FOUND" = 1 ]; then WHY="The commit message has no 'board-row-ok: <reason>' line."
else WHY="The commit message could not be read from the command (editor commit, -C/-c reuse, or an -F file that does not exist yet)."; fi
cat >&2 <<BANNER
BLOCKED: board-row-gate. This commit adds new board row(s) to $BOARD in $ROOT:
  $NEW
$WHY
Rule: a follow-up is done in the session or dropped into its report. A row needs the
operator's ask or a blocker outside the session.
If this row meets that bar, pass the marker as its own message line, then retry:
  git commit -m "<subject>" -m "board-row-ok: <reason>"
or as a line of the heredoc body:  board-row-ok: <reason>
Otherwise unstage the row and put the follow-up in your final report instead.
Operator kill switch: DWARVES_KIT_SKIP_BOARD_ROW_GATE=1 in the session environment.
BANNER
exit 2

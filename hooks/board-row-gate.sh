#!/usr/bin/env bash
# board-row-gate.sh, PreToolUse hook, matcher: Bash
# Blocks a `git commit` that adds a NEW board row unless the commit message carries a
# `board-row-ok: <reason>` line. Follow-ups are done in the session or dropped into its
# report; a row needs the operator's ask or an outside blocker (AGENTS.md zone 2, step 0).
# Source: ops-toolkit .githooks/board-row-gate (a git commit-msg hook). This is the same
# rule as a CC hook, so every repo with a board is covered with no per-repo install.
#
# Board: <repo>/_meta/BACKLOG.md, else <repo>/BACKLOG.md. A new row is a first-cell ID
# (^[A-Z][A-Z0-9]*-[0-9]+$, any prefix) in the board content the commit takes that the
# base commit's board lacks. IDs cited in other cells never count, so status flips and
# moved rows add nothing. The content the commit takes: the index, plus the working tree
# when the commit uses -a or a pathspec covering the board, or when a `git add` earlier in
# the same command stages it (the hook runs before that add does).
# Repo: `git -C <path>` wins, then a resolvable `cd`/`pushd <path>` earlier in the
# command, else the session cwd. Only the first `git commit` of a command is checked.
# Merge, rebase, cherry-pick, and revert states skip. No HEAD yet skips.
# Message: -m/--message values, heredoc bodies, and -F/--file files of THAT commit only.
# A message that cannot be read blocks, but only when new IDs exist.
# Per-repo opt-out: `[gate] board_row_gate = false` in the committed project kit config, read via
# lib/gate/gate-policy.sh (default ON). Session kill switch: DWARVES_KIT_SKIP_BOARD_ROW_GATE=1.
# Exit 2 = block.
# Never evaluates command text; everything below reads it as a string.

set -uo pipefail
[ "${DWARVES_KIT_SKIP_BOARD_ROW_GATE:-0}" = "1" ] && exit 0
INPUT=$(cat 2>/dev/null) || exit 0
case "$INPUT" in *git*commit*) ;; *) exit 0 ;; esac   # fast path: no jq fork for most commands
command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
case "$CMD" in *git*commit*) ;; *) exit 0 ;; esac

# Heredocs: `rest` prints the command without bodies; `body` prints the bodies of
# openers lo+1..hi (1-based, in order); `count` prints how many openers the text has.
heredoc() {  # $1 = rest|body|count, $2 = lo, $3 = hi, stdin = text
  awk -v mode="$1" -v lo="${2:-0}" -v hi="${3:-0}" '
    d != "" { t = $0; sub(/^\t+/, "", t)
              if (t == d) { d = ""; if (mode == "rest") print; next }
              if (mode == "body" && n > lo && n <= hi) print; next }
    { if (mode == "rest") print
      s = $0
      while (match(s, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
        pre = substr(s, 1, RSTART - 1); op = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        if (pre ~ /<$/ || op ~ /^<<</) continue                     # a <<< here-string, not a heredoc
        n++; d = op; sub(/^<<-?[ \t]*["\047]?/, "", d); break } }
    END { if (mode == "count") print n + 0 }'
}

Q="'"
NL=$'\n'
DQ='"([^"\\]|\\.)*"'                     # a double-quoted word
SQ="${Q}[^${Q}]*${Q}"                    # a single-quoted word
WORD="($DQ|$SQ|[^[:space:];&|]+)"
LEAD="(^|[;&|({]|$NL)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=${WORD}[[:space:]]+)*([^[:space:];&|()]*/)?"
GIT_RE="${LEAD}git(([[:space:]]+-[Cc][[:space:]]+$WORD)|([[:space:]]+--?[A-Za-z][-A-Za-z]*(=[^[:space:]]*)?))*[[:space:]]+commit([[:space:]]|$)"
CMDR=$(printf '%s\n' "$CMD" | heredoc rest)   # match against the command minus heredoc bodies
[[ "$CMDR" =~ $GIT_RE ]] || exit 0
MATCH="${BASH_REMATCH[0]}"
PRE="${CMDR%%"$MATCH"*}"
POST="${CMDR#*"$MATCH"}"

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
CD_RE="(^|[;&|({[:space:]])(cd|pushd)[[:space:]]+$WORD"
rest="$PRE"
while [[ "$rest" =~ $CD_RE ]]; do
  p=$(unquote "${BASH_REMATCH[3]}")
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

# The commit's own segment: POST up to the first control operator outside quotes. A
# marker or heredoc after `&&` belongs to a later command, not to this commit.
q="" i=0 n=${#POST}
while [ "$i" -lt "$n" ]; do
  c="${POST:i:1}"
  if [ -n "$q" ]; then
    if [ "$q" = '"' ] && [ "$c" = "\\" ]; then i=$((i + 2)); continue; fi
    [ "$c" = "$q" ] && q=""
  else
    case "$c" in '"'|"$Q") q="$c" ;; ';'|'&'|'|'|"$NL") break ;; esac
  fi
  i=$((i + 1))
done
SEG="${POST:0:i}"

# -m / --message values (repeatable; a short cluster like -am counts). The flag stays in
# ARGS so -a is still seen; the value is dropped so the arg parse below never sees it.
MSG="" FOUND=0 ARGS="$SEG"
M_RE="(^|[[:space:]])(-[A-Za-z]*m|--message)(=|[[:space:]]*)(\"(([^\"\\\\]|\\\\.)*)\"|\\\$$Q(([^$Q\\\\]|\\\\.)*)$Q|$Q([^$Q]*)$Q|([^[:space:]\"$Q;&|]+))"
rest="$SEG"
while [[ "$rest" =~ $M_RE ]]; do
  FOUND=1
  if   [ -n "${BASH_REMATCH[5]}" ]; then v="${BASH_REMATCH[5]}"
  elif [ -n "${BASH_REMATCH[7]}" ]; then v=$(printf '%b' "${BASH_REMATCH[7]}")
  elif [ -n "${BASH_REMATCH[9]}" ]; then v="${BASH_REMATCH[9]}"
  else v="${BASH_REMATCH[10]}"; fi
  MSG="$MSG$NL$v"
  ARGS="${ARGS/"${BASH_REMATCH[0]}"/ ${BASH_REMATCH[2]} }"
  rest="${rest#*"${BASH_REMATCH[0]}"}"
done

# Walk the remaining words: -a/-i/--amend, -F files, and pathspecs. Quotes are dropped,
# so a path with a space splits; that only widens coverage, never narrows it.
ALL=0 INCLUDE=0 AMEND=0 FFILES="" PATHS="" take="" dashdash=0
set -f
# shellcheck disable=SC2086  # word splitting of the quote-stripped segment is the point
for w in $(printf '%s' "$ARGS" | tr -d "\"$Q"); do
  if [ -n "$take" ]; then [ "$take" = F ] && FFILES="$FFILES$NL$w"; take=""; continue; fi
  case "$w" in   # shell syntax, never a pathspec: a redirect eats its target
    *'>'|*'<') take=x; continue ;;
    *'$'*|*'('*|*')'*|*'<'*|*'>'*|*'`'*) continue ;;
  esac
  if [ "$dashdash" = 1 ]; then PATHS="$PATHS$NL$w"; continue; fi
  case "$w" in
    --) dashdash=1 ;;
    --all) ALL=1 ;;
    --include) INCLUDE=1 ;;
    --amend) AMEND=1 ;;
    --file=*) FFILES="$FFILES$NL${w#--file=}" ;;
    --file) take=F ;;
    --pathspec-from-file*) PATHS="$PATHS$NL*" ;;
    --reuse-message|--reedit-message|--template|--author|--date|--cleanup|--fixup|--squash|--trailer) take=x ;;
    --*) ;;
    -*) case "$w" in -*a*) ALL=1 ;; esac
        case "$w" in -*i*) INCLUDE=1 ;; esac
        case "$w" in
          -*F) take=F ;;
          -*F?*) FFILES="$FFILES$NL${w#*F}" ;;
          -*[Cct]) take=x ;;
        esac ;;
    *) PATHS="$PATHS$NL$w" ;;
  esac
done
set +f

# git refuses a pathspec that matches nothing, so a word that names no path means the
# parse misread the command: then pathspecs never narrow what the commit takes.
real_paths() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in *[*?[]*|:*) continue ;; esac
    [ -e "$(join "$DIR" "$p")" ] || return 1
  done <<< "$PATHS"
  return 0
}

# Does any pathspec cover the board? Globs, magic, and .. count as covering.
covers() {
  local prefix p rel
  prefix=$(git -C "$DIR" rev-parse --show-prefix 2>/dev/null)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in *[*?[]*|:*|*..*) return 0 ;; esac
    p="${p#./}"; [ "$p" = "." ] && p=""
    rel="$prefix$p"; rel="${rel%/}"
    [ -z "$rel" ] || [ "$rel" = "$BOARD" ] && return 0
    case "$BOARD" in "$rel"/*) return 0 ;; esac
  done <<< "$PATHS"
  return 1
}

# A `git add`/`rm`/`mv`/`stage` earlier in this command that reaches the board.
STAGE_RE="git([[:space:]]+-[Cc][[:space:]]+$WORD)*[[:space:]]+(add|stage|rm|mv)([[:space:]][^;&|]*)?"
PRESTAGE=0 rest="$PRE"
while [[ "$rest" =~ $STAGE_RE ]]; do
  case " ${BASH_REMATCH[5]} " in
    *" -A "*|*" --all "*|*" -u "*|*" --update "*|*" . "*|*BACKLOG*|*_meta*|*'*'*|*" :/"*) PRESTAGE=1 ;;
  esac
  rest="${rest#*"${BASH_REMATCH[0]}"}"
done

ids() { sed -nE 's/^\|[[:space:]]*([A-Z][A-Z0-9]*-[0-9]+)[[:space:]]*\|.*/\1/p'; }
WT=$(ids < "$ROOT/$BOARD")
IDX=$(git -C "$ROOT" show ":$BOARD" 2>/dev/null | ids)
if [ -n "$PATHS" ] && [ "$INCLUDE" = 0 ] && real_paths; then
  # --only (the default with pathspecs): the board lands only if a pathspec covers it.
  covers || exit 0
  TAKEN="$WT"
else
  TAKEN="$IDX"
  if [ "$ALL" = 1 ] || [ "$PRESTAGE" = 1 ] || { [ -n "$PATHS" ] && covers; }; then TAKEN="$IDX$NL$WT"; fi
fi
TAKEN=$(printf '%s\n' "$TAKEN" | sed '/^$/d' | sort -u)
[ -n "$TAKEN" ] || exit 0
BASE=HEAD
if [ "$AMEND" = 1 ]; then BASE="HEAD^"; fi   # an amend replaces HEAD, so compare with its parent
BASEIDS=$(git -C "$ROOT" show "$BASE:$BOARD" 2>/dev/null | ids | sort -u)
NEW=$(comm -23 <(printf '%s\n' "$TAKEN") <(printf '%s\n' "$BASEIDS") | tr '\n' ' ')
NEW="${NEW% }"
[ -n "$NEW" ] || exit 0

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
_log() { mkdir -p "$LOG_DIR" 2>/dev/null && printf '%s | %s | %s | %s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$ROOT" "$NEW" >> "$LOG_DIR/board-row-gate.log" 2>/dev/null || true; }

# Per-repo opt-out: `[gate] board_row_gate = false` in the committed, clean project config (default
# ON). Asked only now, so a commit with no new row never pays for it. Only exit 1 means off.
POLICY="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-policy.sh"
if [ -f "$POLICY" ]; then
  PRC=0; bash "$POLICY" enabled board_row_gate "$ROOT" || PRC=$?
  [ "$PRC" -eq 1 ] && { _log OFF-BY-CONFIG; exit 0; }
fi

# Only now read message sources that cost I/O: this commit's heredoc bodies and -F files.
A=$(printf '%s\n' "$PRE" | heredoc count)
K=$(printf '%s\n' "$SEG" | heredoc count)
if [ "$K" -gt 0 ]; then
  BODY=$(printf '%s\n' "$CMD" | heredoc body "$A" "$((A + K))")
  FOUND=1; MSG="$MSG$NL$BODY"
fi
while IFS= read -r p; do
  [ -n "$p" ] && [ "$p" != "-" ] || continue
  p=$(join "$DIR" "$(unquote "$p")")
  [ -f "$p" ] && [ -r "$p" ] && { FOUND=1; MSG="$MSG$NL$(cat "$p")"; }
done <<< "$FFILES"

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
Repo opt-out: [gate] board_row_gate = false in the committed project kit config (lib/gate/README.md).
Operator kill switch: DWARVES_KIT_SKIP_BOARD_ROW_GATE=1 in the session environment.
BANNER
exit 2

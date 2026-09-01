#!/usr/bin/env bash
# commit-format.sh, PreToolUse hook, matcher: Bash
# Lints the git commit SUBJECT (first -m line only): Conventional Commits type,
# <=72 chars, and no spec/ticket/phase markers in the subject. Subsequent -m
# body args and -F bodies are ignored, so a long body never trips the length
# check. Editor commits, --no-edit, and merge/fixup/squash/revert subjects pass
# through (no subject to lint, or tool-generated).
# Source: GSD gsd-validate-commit.sh (adapted to bash+jq). SPEC-014. Exit 2 = block.

set -uo pipefail
INPUT=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

# Only git commits.
printf '%s' "$CMD" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

# Extract the FIRST -m / --message subject. No subject -> editor/--no-edit/-F: skip.
SUBJ=""
if   [[ "$CMD" =~ --message[=\ ]+\"([^\"]*)\" ]]; then SUBJ="${BASH_REMATCH[1]}"
elif [[ "$CMD" =~ --message[=\ ]+\'([^\']*)\' ]]; then SUBJ="${BASH_REMATCH[1]}"
elif [[ "$CMD" =~ -[[:alpha:]]*m[[:space:]]*\"([^\"]*)\" ]]; then SUBJ="${BASH_REMATCH[1]}"
elif [[ "$CMD" =~ -[[:alpha:]]*m[[:space:]]*\'([^\']*)\' ]]; then SUBJ="${BASH_REMATCH[1]}"
fi
[ -z "$SUBJ" ] && exit 0

# Tool-generated subjects pass through.
case "$SUBJ" in
  "Merge "*|"fixup! "*|"squash! "*|"Revert "*) exit 0 ;;
esac

block() {  # $1 = why
  local LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$LOG_DIR" 2>/dev/null && printf '%s | BLOCKED | %s | %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(printf '%s' "$SUBJ" | head -c 80)" \
    >> "$LOG_DIR/commit-format.log" 2>/dev/null || true
  jq -cn --arg r "commit-format: $1 Subject: \"$(printf '%s' "$SUBJ" | head -c 80)\". Rules: Conventional Commits type, <=72 chars, no SPEC-/TASK-/phase markers in the subject (put those in the body)." \
    '{decision:"block",reason:$r}'
  exit 2
}

# 1. Length
[ "${#SUBJ}" -le 72 ] || block "subject is ${#SUBJ} chars (max 72)."

# 2. No spec / ticket / phase markers
printf '%s' "$SUBJ" | grep -qiE '(SPEC-[0-9]|TASK-[0-9]|TICKET-[0-9]|\bp[0-9]\b|phase-[0-9])' && block "subject carries a spec/ticket/phase marker."

# 3. Conventional Commits type
printf '%s' "$SUBJ" | grep -qE '^(feat|fix|docs|refactor|test|chore|build|ci|perf|style|revert)(\([^)]+\))?!?: .+' || block "subject is not a Conventional Commit (type(scope): summary)."

exit 0

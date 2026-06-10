#!/bin/bash
# safety-gate.sh, PreToolUse hook, matcher: Bash
# Blocks destructive deletes and direct pushes to main/master.
# Source: Trail of Bits claude-code-config (adapted for dwarves-kit)
# Exit 2 = block action, stderr = reason shown to Claude
#
# SPEC-064: parse-aware, not prose-aware. The original grepped the WHOLE command
# string, so heredoc bodies, quoted prose, and unrelated flags tripped it (five
# logged false positives on 2026-06-10 alone, including the gate firing on a
# BACKLOG row's prose that merely DESCRIBED the bug). Now the command is
# normalized first (heredoc bodies stripped, compound commands split into
# segments) and every rule keys on the segment's actual argv: an `rm` rule only
# fires on a segment whose command IS rm; a push rule only reads the ref tokens
# of a segment whose command IS git push. Known accepted hole: a ref hidden in a
# variable (`B=main; git push origin $B`) is not resolved; fail-open there, the
# remote branch protection is the backstop.

set -euo pipefail
set -f  # no globbing while we word-split segments
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:safety] checking: $(echo "$CMD" | head -c 80)" >&2
fi

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"

log_block() {
  mkdir -p "$LOG_DIR"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | $1 | $(pwd) | $(echo "$CMD" | head -c 120)" >> "$LOG_DIR/safety-gate.log"
}

block() {  # <rule> <message>
  log_block "$1"
  echo "BLOCKED: $2" >&2
  exit 2
}

# --- Normalize: strip heredoc bodies, then split compounds into one segment per line ---
# Heredoc bodies are DATA (test fixtures, generated file content, prose); rules must
# never read them. After stripping, &&, ||, ;, |, newlines, and subshell punctuation
# become segment boundaries, so each segment is one simple command whose first word is
# the binary the rules key on.
SEGMENTS=$(printf '%s\n' "$CMD" | awk '
  BEGIN { inhd = 0 }
  {
    line = $0
    if (inhd) {
      t = line; gsub(/^[ \t]+/, "", t)
      if (t == marker) inhd = 0
      next
    }
    if (match(line, /<<-?[ \t]*["'\'']?[A-Za-z_][A-Za-z0-9_]*["'\'']?/)) {
      m = substr(line, RSTART, RLENGTH)
      sub(/<<-?[ \t]*/, "", m); gsub(/["'\'']/, "", m)
      marker = m; inhd = 1
      line = substr(line, 1, RSTART - 1)
    }
    print line
  }' | awk '{ gsub(/&&|\|\||;|\|/, "\n"); gsub(/[$()`]/, " "); print }')

# UNWRAP quotes (keep content, drop the quote marks) so a quoted ref ("main") still
# reaches the token scan while rule scoping (per-segment binary) keeps prose harmless:
# a commit -m sentence never reaches the push rule because its segment's subcommand is
# commit, not push. (Review F1/F2: deleting spans both opened a quoted-ref bypass AND
# broke the quoted-allowlist-target case.)
strip_quotes() {
  printf '%s' "$1" | sed -E "s/\"([^\"]*)\"/\\1/g; s/'([^']*)'/\\1/g"
}

while IFS= read -r SEG; do
  [ -n "${SEG// /}" ] || continue
  # shellcheck disable=SC2086
  set -- $(strip_quotes "$SEG")
  # skip wrappers and env assignments to find the real binary
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      sudo|command|exec|nohup|time|env|eval|xargs) shift ;;
      bash|sh|zsh) shift; [ "${1:-}" = "-c" ] || [ "${1:-}" = "-s" ] && shift || break ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && continue
  BIN="$1"; shift

  case "$BIN" in
    rm)
      HAS_R=0; HAS_F=0; ALL_SAFE=1; HAVE_TARGET=0
      for t in "$@"; do
        case "$t" in
          --recursive) HAS_R=1 ;;
          --force) HAS_F=1 ;;
          --*) ;;
          -*r*f*|-*f*r*) HAS_R=1; HAS_F=1 ;;
          -*r*) HAS_R=1 ;;
          -*f*) HAS_F=1 ;;
        esac
      done
      if [ "$HAS_R" = 1 ] && [ "$HAS_F" = 1 ]; then
        # Build-artifact allowlist: regenerable dirs only; any other target blocks.
        for t in "$@"; do
          case "$t" in
            -*) ;;
            *..*) ALL_SAFE=0; break ;;   # parent traversal is never safe (C-1)
            node_modules|node_modules/|node_modules/*|./node_modules|./node_modules/|./node_modules/*|\
            dist|dist/|dist/*|./dist|./dist/|./dist/*|\
            build|build/|build/*|./build|./build/|./build/*|\
            .next|.next/|.next/*|./.next|./.next/|./.next/*|\
            .nuxt|.nuxt/|.nuxt/*|.turbo|.turbo/|.turbo/*|.cache|.cache/|.cache/*|\
            target|target/|target/*|./target|./target/|./target/*|\
            coverage|coverage/|coverage/*|out|out/|out/*)
              HAVE_TARGET=1 ;;
            *) ALL_SAFE=0; break ;;
          esac
        done
        if [ "$ALL_SAFE" = 1 ] && [ "$HAVE_TARGET" = 1 ]; then
          :  # safe regenerable delete
        else
          block "rm-rf" "Destructive delete detected. Use 'trash' or 'mv' to a temp directory instead of rm -rf (build artifacts like node_modules/dist are allowlisted)."
        fi
      fi
      ;;
    git)
      # find the git subcommand (first non-flag arg, skipping -C <path>)
      SUB=""; SKIP_NEXT=0
      for t in "$@"; do
        if [ "$SKIP_NEXT" = 1 ]; then SKIP_NEXT=0; continue; fi
        case "$t" in
          -C|--git-dir|--work-tree) SKIP_NEXT=1 ;;
          -*) ;;
          *) SUB="$t"; break ;;
        esac
      done
      case "$SUB" in
        push)
          for t in "$@"; do
            case "$t" in
              --force|-f) block "force-push" "Force push is dangerous. Use --force-with-lease if you must overwrite remote history." ;;
              --force-with-lease*|--force-if-includes) ;;
              +*) block "force-push" "Refspec force push (+ref) is --force without the lease. Use --force-with-lease." ;;
              main|master|*:main|*:master) block "push-to-main" "Do not push directly to main/master. Create a feature branch and open a PR." ;;
            esac
          done
          ;;
        reset)
          for t in "$@"; do
            [ "$t" = "--hard" ] && block "git-reset-hard" "'git reset --hard' discards uncommitted work. Use 'git stash' first, or 'git reset --keep'."
          done
          ;;
      esac
      ;;
    kubectl)
      SUB=""
      for t in "$@"; do case "$t" in -*) ;; *) SUB="$t"; break ;; esac; done
      [ "$SUB" = "delete" ] && block "kubectl-delete" "'kubectl delete' mutates a live cluster. Confirm the context and run it manually."
      ;;
    psql|mysql|sqlite3)
      printf '%s' "$SEG" | grep -qiE '\bDROP[ \t]+TABLE\b' && block "drop-table" "DROP TABLE is destructive. Run it manually after a backup, or use a reversible migration."
      ;;
  esac
done <<< "$SEGMENTS"

exit 0

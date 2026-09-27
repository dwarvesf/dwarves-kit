#!/bin/bash
# safety-gate.sh, PreToolUse hook, matcher: Bash
# Blocks destructive deletes and direct pushes to main/master.
# Source: Trail of Bits claude-code-config (adapted for dwarves-kit)
# Exit 2 = block action, stderr = reason shown to Claude
#
# Parse-aware, not prose-aware. The original grepped the WHOLE command
# string, so heredoc bodies, quoted prose, and unrelated flags tripped it (five
# logged false positives on 2026-06-10 alone, including the gate firing on a
# BACKLOG row's prose that merely DESCRIBED the bug). Now the command is
# normalized first (heredoc bodies stripped, compound commands split into
# segments) and every rule keys on the segment's actual argv: an `rm` rule only
# fires on a segment whose command IS rm; a push rule only reads the ref tokens
# of a segment whose command IS git push. Known accepted holes, fail-open, with the
# remote branch protection as the backstop: a ref hidden in a variable
# (`B=main; git push origin $B`) is not resolved, and a script run from a file or a
# pipe (`bash push.sh`, `printf ... | bash`) is not read.

set -euo pipefail
set -f  # no globbing while we word-split segments
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:safety] checking command (${#CMD} chars)" >&2
fi

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"

log_block() {
  mkdir -p "$LOG_DIR"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | $1 | $(pwd)" >> "$LOG_DIR/safety-gate.log"
}

block() {  # <rule> <message>
  log_block "$1"
  echo "BLOCKED: $2" >&2
  exit 2
}

# --- Normalize: strip heredoc bodies, then split compounds into one segment per line ---
# Heredoc bodies are DATA (test fixtures, generated file content, prose); rules must
# never read them. Two passes print segments, and the rules read every one:
#   1. The quote-aware walk splits the way bash does. A stack of open contexts
#      (' " $' $( `) decides what each character means, so a ; | & ( ) or newline
#      inside quotes stays data and `git push -o 'a;b' origin main` stays one segment.
#      Only an unquoted << opens a heredoc, and the rest of its line is still walked.
#   2. The naive pass splits on &&, ||, ;, | even inside quotes, because a quoted
#      string can be a script (`bash -c "cd x; git push origin main"`). Fail safe: it
#      can only add blocks, so prose like `-m "x; rm -rf y"` blocks as it always has.
SQ="'"
SEGMENTS=$(printf '%s\n' "$CMD" | awk -v sq="$SQ" '
  function emit() { gsub(/[$()`]/, " ", seg); print seg; seg = "" }
  function top() { return d ? st[d] : "" }
  BEGIN { hdre = "^<<-?[ \t]*[\"" sq "]?[A-Za-z_][A-Za-z0-9_]*[\"" sq "]?" }
  {
    line = $0
    if (inhd) {
      t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t == hm[hi] && ++hi > nh) { inhd = 0; nh = 0 }
      next
    }
    naive = line; gsub(/&&|\|\||;|\|/, "\n", naive); gsub(/[$()`]/, " ", naive); print naive
    n = length(line); cont = 0
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1); nx = substr(line, i + 1, 1); t = top()
      if (t == sq) { if (c == sq) d--; seg = seg c; continue }
      if (c == "\\") { seg = seg c nx; if (i == n) cont = 1; i++; continue }
      if (t == "E") { if (c == sq) d--; seg = seg c; continue }
      if (t == "\"") {
        if (c == "\"") { d--; seg = seg c; continue }
        if (c == "$" && nx == "(") { st[++d] = "$"; i++; emit(); continue }
        if (c == "`") { st[++d] = "`"; emit(); continue }
        seg = seg c; continue
      }
      # code context: top level, $( ... ) or ` ... `
      if (c == sq || c == "\"") { st[++d] = c; seg = seg c; continue }
      if (c == "$" && nx == sq) { st[++d] = "E"; seg = seg c nx; i++; continue }
      if (c == "$" && nx == "(") { st[++d] = "$"; i++; emit(); continue }
      if (c == "`") { if (t == "`") d--; else st[++d] = "`"; emit(); continue }
      if (c == ")") { if (t == "$") d--; emit(); continue }
      if (c == "(" || c == ";" || c == "|" || c == "&") { emit(); continue }
      if (c == "<" && substr(line, i, 3) != "<<<" && match(substr(line, i), hdre)) {
        m = substr(line, i, RLENGTH); sub(/^<<-?[ \t]*/, "", m); gsub("[\"" sq "]", "", m)
        hm[++nh] = m; i += RLENGTH - 1; continue
      }
      seg = seg c
    }
    if (nh) { inhd = 1; hi = 1 }
    t = top()
    if (cont) seg = seg " "
    else if (t == sq || t == "\"" || t == "E") seg = seg " "
    else emit()
  }
  END { emit() }')

# Build-artifact allowlist: regenerable dirs only; any other target blocks. Shared
# by every delete verb (rm, find), so the set of "safe to wipe" paths is defined
# once. Fail-closed: no path operand at all is not safe.
targets_all_safe() {
  local t have=0
  for t in "$@"; do
    case "$t" in
      -*) ;;
      *..*) return 1 ;;   # parent traversal is never safe (C-1)
      node_modules|node_modules/|node_modules/*|./node_modules|./node_modules/|./node_modules/*|\
      dist|dist/|dist/*|./dist|./dist/|./dist/*|\
      build|build/|build/*|./build|./build/|./build/*|\
      .next|.next/|.next/*|./.next|./.next/|./.next/*|\
      .nuxt|.nuxt/|.nuxt/*|.turbo|.turbo/|.turbo/*|.cache|.cache/|.cache/*|\
      target|target/|target/*|./target|./target/|./target/*|\
      coverage|coverage/|coverage/*|out|out/|out/*)
        have=1 ;;
      *) return 1 ;;
    esac
  done
  [ "$have" = 1 ]
}

while IFS= read -r SEG; do
  [ -n "${SEG// /}" ] || continue
  # DELETE quote marks and backslashes (keep content) so a quoted or escaped ref ("main",
  # ma\in) still reaches the token scan while rule scoping (per-segment binary) keeps prose
  # harmless: a commit -m sentence never reaches the push rule because its segment's
  # subcommand is commit, not push. Marks go, never spans (review F1/F2: deleting spans
  # opened a quoted-ref bypass AND broke the quoted-allowlist-target case). Deleting every
  # mark, not only paired ones, also clears the stray mark a naive-pass segment carries.
  # Parameter expansion, no subshell: this runs once per segment.
  WORDS=${SEG//[\'\"\\]/}
  # shellcheck disable=SC2086
  set -- $WORDS
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
        targets_all_safe "$@" || \
          block "rm-rf" "Destructive delete detected. Use 'trash' or 'mv' to a temp directory instead of rm -rf (build artifacts like node_modules/dist are allowlisted)."
      fi
      ;;
    find)
      # find carries its own delete verbs. The rm rule never sees them: this
      # segment's binary is find, not rm. 2026-07-08: an unguarded
      # `find ~/.cache/.bun -mindepth 1 -delete` wiped a bun global install.
      HAS_DEL=0; HAS_EXEC=0
      for t in "$@"; do
        case "$t" in
          -delete) HAS_DEL=1 ;;
          -exec|-execdir|-ok|-okdir) HAS_EXEC=1 ;;
          rm|/bin/rm|/usr/bin/rm) if [ "$HAS_EXEC" = 1 ]; then HAS_DEL=1; fi ;;
        esac
      done
      if [ "$HAS_DEL" = 1 ]; then
        # find's path operands are the leading tokens, before the first primary.
        PATHS=""
        for t in "$@"; do
          case "$t" in -*) break ;; *) PATHS="$PATHS $t" ;; esac
        done
        # shellcheck disable=SC2086
        targets_all_safe $PATHS || \
          block "find-delete" "Destructive delete detected (find -delete / -exec rm). Use 'trash' or 'mv' to a temp directory instead (build artifacts like node_modules/dist are allowlisted)."
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

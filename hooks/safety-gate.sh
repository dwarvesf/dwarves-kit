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
# (`B=main; git push origin $B`) or an escape (`$'\x6dain'`) is not resolved; a script
# run from a file or a pipe (`bash push.sh`, `printf ... | bash`) is not read; and a
# quoted separator inside a wrapped script (`bash -c "cd x; git push -o 'a;b' ..."`) or
# a `)` in a case pattern inside `"$(...)"` desyncs the walk; a misread << (in ${...})
# whose false delimiter line appears later skips the lines between; a false $(( or ((
# frame that spans lines only turns at its lone ), so a separator on an earlier line
# stays unread; a wrapper outside the segment-start list (ssh, flock) hides its command;
# a wrapper flag
# whose operand the segment-start table does not list (sudo -s, timeout -s SIG) turns
# the operand into the binary; zsh-only syntax beyond noglob, nocorrect, repeat, and
# always is read as bash.

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
#      (' " $' $( ( `) decides what each character means, so a ; | & ( ) or newline
#      inside quotes stays data and `git push -o 'a;b' origin main` stays one segment.
#      An unquoted # at a word start ends the line. Only an unquoted << (not <<<)
#      opens a heredoc; its body starts after the logical line ends, and the rest of
#      the marker's own line is still walked.
#   2. The naive pass splits on &&, ||, ;, | even inside quotes, because a quoted
#      string can be a script (`bash -c "cd x; git push origin main"`). Fail safe: it
#      can only add blocks, so prose like `-m "x; rm -rf y"` blocks as it always has.
# A heredoc whose delimiter never appears means the walk misread a << (arithmetic, a
# parameter expansion): the skipped lines are replayed through both passes, fail safe.
SQ="'"
SEGMENTS=$(printf '%s\n' "$CMD" | awk -v sq="$SQ" '
  function emit() { gsub(/[$()`]/, " ", seg); print seg; seg = "" }
  function top() { return d ? st[d] : "" }
  # $( and ` : the inner command walks as its own segments while the outer text waits in
  # sv[d]; on close it returns with "_" standing in for the substitution
  function sub_open(kind) { st[++d] = kind; sv[d] = seg; seg = ""; ws = 1 }
  function sub_close() { emit(); seg = sv[d] "_"; d--; ws = 0 }
  # open an arithmetic frame: kind ($ for $((, ( for (( at a command start), where it
  # opened, the index of its second (, and the segment length, line, and heredoc count at
  # the open, for the lone-) rewind. A position rewound once never reopens a frame, so
  # nested false frames cost one re-walk each, not one per enclosing rewind.
  function arith(kind, at, second) {
    if ((ln, at) in rw) return 0
    st[++d] = "A"; ak[d] = kind; ap[d] = 0; aw[d] = at; ao[d] = second; as[d] = length(seg); al[d] = ln; an[d] = nh
    return 1
  }
  function naive(s) { gsub(/&&|\|\||;|\|/, "\n", s); gsub(/[$()`]/, " ", s); print s }
  # The heredoc delimiter word at the start of s, after quote and backslash removal
  # (bash reads <<"E"OF as EOF). Sets wl to the characters consumed.
  function hdword(s,   k, ch, w, q) {
    k = 1; while (substr(s, k, 1) == " " || substr(s, k, 1) == "\t") k++
    w = ""; q = ""
    for (; k <= length(s); k++) {
      ch = substr(s, k, 1)
      if (q != "") { if (ch == q) q = ""; else w = w ch; continue }
      if (ch == sq || ch == "\"") { q = ch; continue }
      if (ch == "\\") { k++; w = w substr(s, k, 1); continue }
      if (index(" \t;&|<>()", ch)) break
      w = w ch
    }
    wl = k - 1; return w
  }
  # ws: the next character starts a word (a # there is a comment). Set by blanks and
  # operators; cleared by any other character, an escape, a closing quote, and the ) or `
  # that closes a substitution, because bash reads $(x)#y and a\ #y as one word.
  function proc(line,   i, n, c, nx, t, k, w, pc) {
    nv = nv line; ln++
    n = length(line); pc = cont; cont = 0
    if (!pc) ws = 1
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1); nx = substr(line, i + 1, 1); t = top()
      if (t == sq) { if (c == sq) { d--; ws = 0 } seg = seg c; continue }
      if (t == "A") {
        if (c == "$" && nx == "(") { sub_open("$"); i++; continue }
        if (c == "`") { sub_open("`"); continue }
        if (c == "(") ap[d]++
        else if (c == ")") {
          if (ap[d]) ap[d]--
          else if (nx == ")") { ws = (ak[d] == "("); d--; i++ }
          else if (al[d] == ln) {
            # a lone ) means it was never arithmetic, but $( ( or ( (: drop what the frame
            # read without boundaries and walk it again as code from the second (
            rw[ln, aw[d]] = 1; nh = an[d]
            seg = substr(seg, 1, as[d]); st[d] = ak[d]
            if (ak[d] == "$") { sv[d] = seg; seg = "" } else emit()
            ws = 1; i = ao[d] - 1; continue
          } else { st[d] = ak[d]; emit(); ws = 1; continue }
        }
        seg = seg c; continue
      }
      if (c == "\\") { if (i == n) { cont = 1; continue } seg = seg c nx; ws = 0; i++; continue }
      if (t == "E") { if (c == sq) { d--; ws = 0 } seg = seg c; continue }
      if (t == "\"") {
        if (c == "\"") { d--; seg = seg c; ws = 0; continue }
        if (c == "$" && substr(line, i, 3) == "$((" && arith("$", i, i + 2)) { i += 2; continue }
        if (c == "$" && nx == "(") { sub_open("$"); i++; continue }
        if (c == "`") { sub_open("`"); continue }
        seg = seg c; continue
      }
      # code context: top level, $( ... ), ( ... ) or ` ... `
      if (c == "#" && ws) break
      if (c == " " || c == "\t" || c == "<" || c == ">") {
        if (c == "<" && nx == "<" && substr(line, i + 2, 1) != "<" && (i == 1 || substr(line, i - 1, 1) != "<")) {
          k = (substr(line, i + 2, 1) == "-") ? 3 : 2
          w = hdword(substr(line, i + k))
          if (w != "" && !replay) hm[++nh] = w
          i += k + wl - 1; ws = 0; continue
        }
        seg = seg c; ws = 1; continue
      }
      if (c == sq || c == "\"") { st[++d] = c; seg = seg c; ws = 0; continue }
      if (c == "$" && nx == sq) { st[++d] = "E"; seg = seg c nx; i++; ws = 0; continue }
      if (c == "$" && substr(line, i, 3) == "$((" && arith("$", i, i + 2)) { i += 2; ws = 0; continue }
      if (c == "(" && nx == "(" && seg ~ /^[ \t]*(((if|then|elif|else|while|until|do|time|-p|for|!|\{|coproc([ \t]+[A-Za-z_][A-Za-z0-9_]*)?)[ \t]*)*)$/ && arith("(", i, i + 1)) {
        i++; continue
      }
      if (c == "$" && nx == "(") { sub_open("$"); i++; continue }
      if (c == "`") { if (t == "`") sub_close(); else sub_open("`"); continue }
      if (c == ")") { if (t == "$") sub_close(); else { if (t == "(") d--; ws = 1; emit() } continue }
      if (c == "(") { st[++d] = "("; emit(); ws = 1; continue }
      if (c == ";" || c == "|" || c == "&") { emit(); ws = 1; continue }
      seg = seg c; ws = 0
    }
    if (cont) { nv = substr(nv, 1, length(nv) - 1); return }
    naive(nv); nv = ""
    t = top()
    if (t == sq || t == "\"" || t == "E") seg = seg " "
    else { emit(); if (nh) { inhd = 1; hi = 1; nb = 0 } }
  }
  {
    if (inhd) {
      buf[++nb] = $0
      t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t == hm[hi] && ++hi > nh) { inhd = 0; nh = 0 }
      next
    }
    proc($0)
  }
  END {
    if (inhd) { replay = 1; nh = 0; for (k = 1; k <= nb; k++) proc(buf[k]) }
    if (nv != "") naive(nv)
    emit()
  }')

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
  # skip wrappers, env assignments, shell grammar, and redirections to find the real binary
  W=""  # the last wrapper whose flags can take an operand
  while [ $# -gt 0 ]; do
    # assignments and redirections read the raw word; the rest read its basename (/usr/bin/git)
    case "$1" in
      *=*) shift; continue ;;
      # N>&M duplicates carry no operand; a bare operator takes the next word
      *\>\&[0-9-]|*\<\&[0-9-]) shift; continue ;;
      \>*|\<*|\&\>*|[0-9]\>*|[0-9]\<*)
        case "$1" in *[!0-9\<\>\&\|]*) shift ;; *) shift; [ $# -gt 0 ] && shift ;; esac
        continue ;;
    esac
    case "${1##*/}" in
      sudo|doas|env|xargs|exec) W="${1##*/}"; shift ;;
      command|nohup|time|eval|builtin|bash|sh|zsh|noglob|nocorrect|repeat) W=""; shift ;;
      timeout|nice|stdbuf|ionice|caffeinate|chronic|unbuffer|watch) W=""; shift ;;
      # op run -- cmd, direnv exec DIR cmd, mise exec [tool@ver] -- cmd
      op) shift; case "${1:-}" in run) shift ;; esac ;;
      direnv) shift; case "${1:-}" in exec) shift; [ $# -gt 0 ] && shift ;; esac ;;
      mise) shift; case "${1:-}" in exec|x) shift; while [ $# -gt 0 ]; do case "$1" in *@*) shift ;; *) break ;; esac; done ;; esac ;;
      if|then|else|elif|while|until|do|'{'|'}'|'!'|always) shift ;;
      # coproc NAME { ... } and function NAME { ... }: the name is not the command
      coproc) shift; case "${2:-}" in '{'|if|while|until|for|select|'!') shift ;; esac ;;
      function) shift; [ $# -gt 0 ] && shift ;;
      # an operand flag of sudo, doas, env, xargs, or exec (sudo -u root, env -C dir,
      # xargs -I {}, xargs -d x); for any other wrapper (caffeinate -u, bash -u) it is a plain flag
      -u|-g|-U|-C|-D|-T|-I|-a|-d) shift; case "$W" in ?*) [ $# -gt 0 ] && shift ;; esac ;;
      # any other flag, and a duration or niceness operand (timeout 5m, nice -n 10);
      # bash -c / -lc lands here too
      -*|[0-9]|[0-9]*[0-9smhd.]) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && continue
  BIN="${1##*/}"; shift

  case "$BIN" in
    rm)
      HAS_R=0; HAS_F=0; ALL_SAFE=1; HAVE_TARGET=0
      for t in "$@"; do
        case "$t" in
          --recursive) HAS_R=1 ;;
          --force) HAS_F=1 ;;
          --*) ;;
          -*[rR]*f*|-*f*[rR]*) HAS_R=1; HAS_F=1 ;;
          -*[rR]*) HAS_R=1 ;;
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
          -C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix) SKIP_NEXT=1 ;;
          -*) ;;
          *) SUB="$t"; break ;;
        esac
      done
      case "$SUB" in
        push)
          for t in "$@"; do
            case "$t" in
              --force|-f*|-[!-]*f*) block "force-push" "Force push is dangerous. Use --force-with-lease if you must overwrite remote history." ;;
              --force-with-lease*|--force-if-includes) ;;
              +*) block "force-push" "Refspec force push (+ref) is --force without the lease. Use --force-with-lease." ;;
              refs/tags/*|*:refs/tags/*) ;;
              --mirror|--all|*\**|*\{*) block "push-all" "--mirror, --all, or a glob or brace refspec can push main/master. Push one feature branch." ;;
              main|master|*:main|*:master|refs/heads/main|refs/heads/master|*:refs/heads/main|*:refs/heads/master)
                block "push-to-main" "Do not push directly to main/master. Create a feature branch and open a PR." ;;
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
      SKIP_NEXT=0
      for t in "$@"; do
        if [ "$SKIP_NEXT" = 1 ]; then SKIP_NEXT=0; continue; fi
        case "$t" in
          -n|--namespace|--context|--cluster|--user|--kubeconfig|-s|--server|-l|--selector) SKIP_NEXT=1 ;;
          -*) ;;
          *) SUB="$t"; break ;;
        esac
      done
      [ "$SUB" = "delete" ] && block "kubectl-delete" "'kubectl delete' mutates a live cluster. Confirm the context and run it manually."
      ;;
    psql|mysql|sqlite3)
      # the SQL often arrives as a heredoc body, so read the whole command
      printf '%s' "$CMD" | grep -qiE '\bDROP[ \t]+TABLE\b' && block "drop-table" "DROP TABLE is destructive. Run it manually after a backup, or use a reversible migration."
      ;;
  esac
done <<< "$SEGMENTS"

exit 0

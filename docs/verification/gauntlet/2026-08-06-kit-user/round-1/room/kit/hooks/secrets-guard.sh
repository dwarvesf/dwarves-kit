#!/usr/bin/env bash
# secrets-guard.sh, PreToolUse hook, matcher: Read|Edit|Bash
# Blocks the agent from READING secret files. safety-gate covers write/exec
# destruction; this covers the read side. The path is canonicalized first
# (~, $HOME, and ../ spellings of the same file all normalize to one absolute
# path) so the denylist cannot be bypassed by an alternate spelling.
# Fail-closed on a confirmed secret match; fail-open (exit 0) on unparseable
# input so a parse error never bricks the session. Logs the attempted path +
# tool, never file contents.
#
# Scope is honest: the Read/Edit deny below (plus the settings.json
# permissions.deny block) is the primary, reliable layer. The Bash-command
# check is best-effort defense-in-depth against accidental/naive reads; a
# determined bypass (obfuscated reader, python -c, base64) is out of scope.
#
# Source: Trail of Bits claude-code-config deny-list + claudekit file-guard.
# SPEC-014 / ADR-0014. Exit 2 = block.

set -uo pipefail

INPUT=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0   # no jq -> fail-open

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$TOOL" ] && exit 0

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
log_block() {  # $1=tool  $2=path-or-cmd-snippet (never file contents)
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  printf '%s | BLOCKED | %s | %s | %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(pwd)" "$2" \
    >> "$LOG_DIR/secrets-guard.log" 2>/dev/null || true
}

# --- Secret path globs (edit here to extend). ALLOW wins over SECRET. ---
ALLOW_GLOBS=( '*/.env.example' '*/.env.sample' '*/.env.template' )
SECRET_GLOBS=(
  '*/.env' '*/.env.local' '*/.env.*.local' '*/.env.production' '*/.env.development'
  "$HOME/.ssh/"'*' '*/.ssh/id_'* '*/id_rsa' '*/id_ed25519'
  "$HOME/.aws/"'*' "$HOME/.gnupg/"'*' "$HOME/.config/gh/"'*'
  "$HOME/.git-credentials" "$HOME/.docker/config.json"
  "$HOME/.kube/config" "$HOME/.npmrc"
  '*.pem' '*.p12' '*.pfx'
  "$HOME/Library/Keychains/"'*'
)

# Portable path canonicalizer (realpath -m is not macOS-portable): expand a
# leading ~ / $HOME, make absolute, and resolve . and .. segments in bash.
normpath() {
  local p="$1" seg; local -a out=()
  case "$p" in
    '~')   p="$HOME" ;;
    '~/'*) p="$HOME/${p#\~/}" ;;
  esac
  p="${p//\$HOME/$HOME}"
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  local IFS=/
  for seg in $p; do
    case "$seg" in
      ''|.) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset 'out[$(( ${#out[@]} - 1 ))]' ;;
      *) out+=("$seg") ;;
    esac
  done
  printf '/%s' "${out[@]}"
}

is_secret() {  # $1 = raw path; returns 0 if secret
  local p r g
  p=$(normpath "$1")
  # Resolve symlinks + .. when the path exists, and match BOTH the lexical and
  # resolved forms, so a symlink with an innocuous name pointing at a secret is
  # still caught (H-1). Dangling/nonexistent paths fall back to the lexical form.
  if [ -e "$p" ] && command -v realpath >/dev/null 2>&1; then
    r=$(realpath "$p" 2>/dev/null || printf '%s' "$p")
  else
    r="$p"
  fi
  for g in "${ALLOW_GLOBS[@]}";  do [[ "$p" == $g || "$r" == $g ]] && return 1; done
  for g in "${SECRET_GLOBS[@]}"; do [[ "$p" == $g || "$r" == $g ]] && return 0; done
  return 1
}

case "$TOOL" in
  Read|Edit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
    [ -z "$FP" ] && exit 0
    if is_secret "$FP"; then
      NP=$(normpath "$FP")
      log_block "$TOOL" "$NP"
      jq -cn --arg t "$TOOL" --arg p "$NP" \
        '{decision:"block",reason:("secrets-guard: "+$t+" targets a secret file ("+$p+"). Reading credentials/keys is blocked. If this file is not a secret, rename it or add it to ALLOW_GLOBS in hooks/secrets-guard.sh.")}'
      exit 2
    fi
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -z "$CMD" ] && exit 0
    # Best-effort (DEC-008): a reader/redirect touching a clear secret token.
    if printf '%s' "$CMD" | grep -qE '(\bcat\b|\bless\b|\bmore\b|\bhead\b|\btail\b|\bxxd\b|\bstrings\b|\bod\b|\btac\b|\bnl\b|\bbase64\b|\bcp\b)' \
       && printf '%s' "$CMD" | grep -qE '(\.ssh/id_|id_rsa|id_ed25519|\.aws/credentials|\.gnupg/|\.git-credentials|\.pem\b|\.p12\b|\.kube/config|\.npmrc)'; then
      log_block "Bash" "$(printf '%s' "$CMD" | head -c 120)"
      jq -cn '{decision:"block",reason:"secrets-guard: this command appears to read a secret file (ssh key / aws creds / .pem). Blocked. Read the value from an env var or a secrets manager instead."}'
      exit 2
    fi
    ;;
esac

exit 0

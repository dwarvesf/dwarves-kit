#!/bin/bash
# permission-auto-approve.sh -- PermissionRequest hook that auto-approves a Bash command only when it is confirmed single, simple and read-only.
# permission-auto-approve.sh, PermissionRequest hook
#
# Auto-approves a Bash command only when it can be positively confirmed to be a
# single, simple, read-only invocation. Anything the hook cannot confirm returns
# no decision, so Claude Code shows the normal permission prompt. This hook
# never emits a deny/block decision. Read, Glob, Grep, WebSearch, and WebFetch
# are always allowed without scanning.
#
# Staged contract for Bash (first failing check falls through; each instrumented
# fall-through emits one DWARVES_KIT_DEBUG=1 stderr line carrying its stage token):
#   nul-guard: a NUL byte in the decoded .tool_input.command falls through; bash
#              $( ) drops NULs, so the scanned string would differ from the
#              executed one. The probe is jq -e 'explode | any(. == 0)', never
#              contains() (jq 1.6 truncates strings at NUL); only jq exit 1
#              means clean, every other exit falls through.
#   stage-a:   a newline in the command falls through.
#   stage-b:   every character of the command must match the LC_ALL=C allowlist
#              ^[A-Za-z0-9 ./_=:,@%+*~-]+$ ; any other character falls through.
#              (no backslash escapes inside the class: on the macOS regex
#              engine a "\/" would smuggle "\" itself into the allowlist)
#   stage-c:   read -ra WORDS <<< "$CMD" (IFS split, never glob-expands); an
#              empty WORDS (spaces-only command) falls through.
#   stage-d:   WORDS[0] in {ls cat head tail wc echo which type stat du df grep},
#              WORDS[0..1] in {git status, git ls-files}, or CMD exactly "pwd"
#              approves with no further checks (no write-capable option exists).
#   stage-e:   WORDS[0] must be a gated tool: find, git, or file. For git the
#              stage also requires a work tree: git -C <payload .cwd, else
#              $PWD> rev-parse --is-inside-work-tree must print exactly "true"
#              and exit 0. A clone can deliver a tracked bare-repo layout
#              (HEAD, objects/, refs/, config); git discovers it as a bare
#              repository and an approved "read" would run whatever the
#              carried config names (diff.external, gpg.program). The probe
#              runs before the stage-d git fast-path so NO git command
#              approves outside a work tree.
#   stage-f:   for git, WORDS[1] must be an allowed subcommand (find and file
#              have no subcommand gate); no arg token may contain "*"; every
#              "-"-leading token must be in the tool's safe-flag set.
#
# Runtime: /bin/bash 3.2, no associative arrays (safe-flag sets are case
# pattern lists), no mapfile, and under set -u an empty "${arr[@]}" aborts as
# unbound, so WORDS is initialized and length-checked before any expansion.
#
# Source: disler/hooks-mastery + Trail of Bits auto-allow pattern

set -euo pipefail
INPUT=$(cat)

# Fail-safe jq reads. Under `set -euo pipefail` an unparseable payload makes jq exit 5,
# pipefail propagates it, and set -e killed the hook right here (exit 5) before it could
# decide anything. Degrading to an EMPTY tool/cmd is the fail-CLOSED default: neither
# branch below matches, so the hook falls through to the normal permission dialog and
# exits 0. Unparseable input must never auto-approve, and must never wedge the hook.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

debug() {
  if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
    echo "[dwarves-kit:permission] $1" >&2
  fi
}

approve() {
  echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
  exit 0
}

if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  debug "tool=$TOOL cmd=$(echo "$CMD" | head -c 80)"
fi

# Always auto-approve read-only tools
case "$TOOL" in
  Read|Glob|Grep|WebSearch|WebFetch)
    approve
    ;;
esac

if [ "$TOOL" != "Bash" ] || [ -z "$CMD" ]; then
  debug "fall-through: bash-gate (not a non-empty Bash command)"
  exit 0
fi

# nul-guard: jq -e exits 1 only when the decoded command is NUL-free. Exit 0
# means a NUL is present; any other exit is a jq error. Both fall through.
NUL_RC=0
printf '%s' "$INPUT" | jq -e '(.tool_input.command // "") | explode | any(. == 0)' >/dev/null 2>&1 || NUL_RC=$?
if [ "$NUL_RC" -ne 1 ]; then
  debug "fall-through: nul-guard (jq rc=$NUL_RC; 0 = NUL present, other = jq error)"
  exit 0
fi

# stage-a: single line only. Redundant once stage-b lands (a newline is not in
# the allowlist) but kept so a multi-line command fails for the stated reason.
case "$CMD" in
  *$'\n'*)
    debug "fall-through: stage-a (command contains a newline)"
    exit 0
    ;;
esac

# stage-b: character allowlist over the WHOLE string, byte-exact under LC_ALL=C.
LC_ALL=C
SAFE_CHARS='^[A-Za-z0-9 ./_=:,@%+*~-]+$'
if [[ ! "$CMD" =~ $SAFE_CHARS ]]; then
  debug "fall-through: stage-b (character outside the ASCII allowlist)"
  exit 0
fi

# stage-c: IFS tokenize. read never glob-expands, which matters because the
# allowlist lets "*" through. A spaces-only command yields an empty WORDS.
WORDS=()
read -ra WORDS <<< "$CMD" || true
if [ "${#WORDS[@]}" -eq 0 ]; then
  debug "fall-through: stage-c (whitespace-only command)"
  exit 0
fi

# git work-tree probe (part of stage-e, runs before the stage-d git
# fast-path): a clone can deliver a tracked bare-repo layout, a directory
# carrying HEAD, objects/, refs/, and a live config. git discovers it as a
# bare repository, and an approved "read" (log via gpg.program, diff via
# diff.external, status via core.fsmonitor) then runs whatever the config
# names. --is-inside-work-tree prints "true" only inside a real work tree: a
# bare layout prints "false" and a non-repo exits nonzero, so every other
# outcome falls through. The probe itself executes no pager, fsmonitor, or
# diff/filter driver (rev-parse is plumbing; it reads config, never runs it;
# verified live against all four trap kinds). The .cwd read is the same
# fail-closed jq pattern as TOOL/CMD: missing or unparseable falls back to
# $PWD, and a nonexistent .cwd makes git -C exit nonzero, which falls through.
if [ "${WORDS[0]}" = "git" ]; then
  HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  WT=$(git -C "${HOOK_CWD:-$PWD}" rev-parse --is-inside-work-tree 2>/dev/null) || WT=""
  if [ "$WT" != "true" ]; then
    debug "fall-through: stage-e (git outside a work tree)"
    exit 0
  fi
fi

# stage-d: tools whose flag set has no write-capable option approve outright.
case "${WORDS[0]}" in
  ls|cat|head|tail|wc|echo|which|type|stat|du|df|grep)
    approve
    ;;
esac

# stage-d: git status and git ls-files (trailing flags unrestricted), pwd exact.
if [ "${WORDS[0]}" = "git" ] && [ "${#WORDS[@]}" -ge 2 ]; then
  case "${WORDS[1]}" in
    status|ls-files)
      approve
      ;;
  esac
fi

if [ "$CMD" = "pwd" ]; then
  approve
fi

# stage-e: only the gated tools continue.
case "${WORDS[0]}" in
  find|git|file)
    ;;
  *)
    debug "fall-through: stage-e (${WORDS[0]} is not an approved tool)"
    exit 0
    ;;
esac

# stage-f helpers. flag_ok <set> <token>: is this "-"-leading token in the set?
flag_ok() {
  local kind="$1" tok="$2"
  case "$kind" in
    find)
      case "$tok" in
        -name|-iname|-path|-ipath|-type|-maxdepth|-mindepth|-print|-print0) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    git-logdiffshow)
      case "$tok" in
        --oneline|--graph|--all|--stat|--name-only|--name-status|-p|--patch|--no-merges|--merges|--reverse|--cached|--staged|-n|--) return 0 ;;
        --format=*%G*|--pretty=*%G*) return 1 ;;
        --format=*|--pretty=*|--since=*|--until=*|--author=*|--grep=*|--max-count=*) return 0 ;;
        *) [[ "$tok" =~ ^-[0-9]+$ ]] ;;
      esac
      ;;
    git-branch)
      case "$tok" in
        -v|-vv|-a|-r|--list|--show-current) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    git-tag)
      case "$tok" in
        -l|--list) return 0 ;;
        *) [[ "$tok" =~ ^-n[0-9]*$ ]] ;;
      esac
      ;;
    file)
      case "$tok" in
        -b|--brief|-i|-s|-L|-f|--mime|--mime-type|--mime-encoding) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# scan_flags <set> <start-index>: for tools whose non-flag args are unrestricted,
# every arg token must be free of "*" and every "-"-leading token in the set.
scan_flags() {
  local kind="$1" i="$2" tok
  while [ "$i" -lt "${#WORDS[@]}" ]; do
    tok="${WORDS[$i]}"
    case "$tok" in
      *'*'*)
        debug "fall-through: stage-f ($kind arg contains '*': $tok)"
        exit 0
        ;;
    esac
    case "$tok" in
      -*)
        if ! flag_ok "$kind" "$tok"; then
          debug "fall-through: stage-f ($kind flag not in safe set: $tok)"
          exit 0
        fi
        ;;
    esac
    i=$((i + 1))
  done
}

# scan_exact <set> <start-index>: every arg token must be in the set; non-flag
# tokens fall too (this is what keeps "git branch <name>" from approving).
scan_exact() {
  local kind="$1" i="$2" tok
  while [ "$i" -lt "${#WORDS[@]}" ]; do
    tok="${WORDS[$i]}"
    if ! flag_ok "$kind" "$tok"; then
      debug "fall-through: stage-f ($kind arg not in safe set: $tok)"
      exit 0
    fi
    i=$((i + 1))
  done
}

# stage-f: per-tool checks.
case "${WORDS[0]}" in
  find)
    scan_flags find 1
    approve
    ;;
  file)
    scan_flags file 1
    approve
    ;;
  git)
    SUB="${WORDS[1]:-}"
    case "$SUB" in
      log|diff|show)
        scan_flags git-logdiffshow 1
        approve
        ;;
      branch)
        scan_exact git-branch 2
        approve
        ;;
      tag)
        scan_exact git-tag 2
        approve
        ;;
      remote)
        # Zero or one further token; if present it must be -v, --verbose, or show.
        if [ "${#WORDS[@]}" -le 3 ]; then
          if [ "${#WORDS[@]}" -eq 2 ]; then
            approve
          else
            case "${WORDS[2]}" in
              -v|--verbose|show)
                approve
                ;;
            esac
          fi
        fi
        debug "fall-through: stage-f (git remote arg outside {-v, --verbose, show})"
        exit 0
        ;;
      *)
        debug "fall-through: stage-f (git subcommand not allowed: ${SUB:-<none>})"
        exit 0
        ;;
    esac
    ;;
esac

# Everything else: let the normal permission dialog show
exit 0

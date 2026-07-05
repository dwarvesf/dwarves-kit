#!/usr/bin/env bash
# skill-curator shared helpers: paths, config, logging, lock, sentinel, secret scan, slug.
# Sourced by hooks/, lib/reviewer-run.sh, bin/cc-improve. Stdlib bash + jq only. No secrets.
#
# Every path is env-overridable (CC_SI_* wins over config.toml wins over the default) so tests
# can redirect all writes into a temp dir. The reviewer/curator MODEL never writes; only the
# trusted code that sources this file writes, and only to the fixed paths below.

# pipefail only (NOT -e / -u): a hook must never abort a session on an unset var or a non-zero
# step. Every variable below is referenced with ${VAR:-} defensively.
set -o pipefail

# Tool root = parent of this lib/ dir. CC_SI_ROOT is consumed by sourcing scripts (reviewer-run.sh
# reads $CC_SI_ROOT/prompts/...), so it is "unused" only within this file.
CC_SI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
CC_SI_ROOT="$(cd "$CC_SI_LIB/.." && pwd)"

_expand() { case "$1" in "~"/*) printf '%s/%s' "$HOME" "${1#\~/}";; *) printf '%s' "$1";; esac; }

CC_SI_STATE_DIR="$(_expand "${CC_SI_STATE_DIR:-$HOME/.claude/skill-curator}")"
CC_SI_PROPOSALS_DIR="$(_expand "${CC_SI_PROPOSALS_DIR:-$HOME/.claude/skill-proposals}")"
CC_SI_SKILLS_DIR="$(_expand "${CC_SI_SKILLS_DIR:-$HOME/.claude/skills}")"
CC_SI_LEDGER="$CC_SI_STATE_DIR/ledger.jsonl"
CC_SI_LOCK="$CC_SI_STATE_DIR/state/reviewer.lock"
CC_SI_LOG="$CC_SI_STATE_DIR/skill-curator.log"
CC_SI_CONFIG="$(_expand "${CC_SI_CONFIG:-$CC_SI_STATE_DIR/config.toml}")"

# cfg KEY DEFAULT : env CC_SI_<KEY> wins, then a `key = value` line in config.toml, then DEFAULT.
cfg() {
  local key="$1" def="${2:-}" envvar val
  envvar="CC_SI_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  if [ -n "${!envvar:-}" ]; then printf '%s' "${!envvar}"; return; fi
  if [ -f "$CC_SI_CONFIG" ]; then
    val="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$CC_SI_CONFIG" | head -1 \
            | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//; s/^'\''//; s/'\''$//')"
    if [ -n "$val" ]; then printf '%s' "$val"; return; fi
  fi
  printf '%s' "$def"
}

si_log() {  # timestamped line to the tool log; never fatal
  local ts; ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo '?')"
  mkdir -p "$CC_SI_STATE_DIR" 2>/dev/null || true
  printf '%s skill-curator: %s\n' "$ts" "$*" >> "$CC_SI_LOG" 2>/dev/null || true
}

ledger_append() {  # ledger_append <json-object-string>; one JSONL row, never fatal
  mkdir -p "$CC_SI_STATE_DIR" 2>/dev/null || true
  printf '%s\n' "$1" >> "$CC_SI_LEDGER" 2>/dev/null || true
}

# safe_slug <s>: lowercase kebab, strip anything that could escape a directory. Never empty.
safe_slug() {
  local s; s="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' \
                 | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
  s="${s:0:64}"
  [ -n "$s" ] && printf '%s' "$s" || printf 'untitled-draft'
}

# contains_secret <text>: 0 (true) if a high-precision secret pattern is present. Used by the
# trusted wrapper to DROP a draft rather than stage a printed credential (defense in depth on top
# of the reviewer-prompt ban + the promote-time scan).
contains_secret() {
  printf '%s' "${1:-}" | grep -Eq \
    -e 'sk-ant-[A-Za-z0-9_-]{8,}' \
    -e 'sk-[A-Za-z0-9]{20,}' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'ghp_[A-Za-z0-9]{30,}' \
    -e 'github_pat_[A-Za-z0-9_]{30,}' \
    -e 'xox[bpras]-[A-Za-z0-9-]{10,}' \
    -e 'AIza[0-9A-Za-z_-]{35}' \
    -e 'eyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{8,}' \
    -e '-----BEGIN [A-Z ]*PRIVATE KEY-----'
}

# reviewing_sentinel_set: true if we are already inside a reviewer (reentrancy guard).
reviewing_sentinel_set() { [ -n "${CLAUDE_REVIEWING:-}" ]; }

# Single-flight lock. macOS has no flock(1), so use an atomic mkdir lock (portable to macOS+Linux).
# si_acquire_lock: 0 if acquired (caller must si_release_lock on exit), 1 if a LIVE holder has it.
si_acquire_lock() {
  local d="${CC_SI_LOCK}.d"
  mkdir -p "$(dirname "$d")" 2>/dev/null || true
  if mkdir "$d" 2>/dev/null; then printf '%s' "$$" > "$d/pid" 2>/dev/null || true; return 0; fi
  local hp; hp="$(cat "$d/pid" 2>/dev/null || true)"          # steal a lock whose holder died
  if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then
    rm -f "$d/pid" 2>/dev/null || true; rmdir "$d" 2>/dev/null || true
    if mkdir "$d" 2>/dev/null; then printf '%s' "$$" > "$d/pid" 2>/dev/null || true; return 0; fi
  fi
  return 1
}
si_release_lock() { local d="${CC_SI_LOCK}.d"; rm -f "$d/pid" 2>/dev/null || true; rmdir "$d" 2>/dev/null || true; }

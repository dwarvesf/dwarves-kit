#!/bin/bash
# kit-update-notice.sh -- SessionStart (startup only) hook: tell the user when a newer kit release exists.
#
# Compares the installed VERSION with the latest VERSION on the default branch and, only when the
# latest is newer, prints one systemMessage line. It never installs anything; updating stays an
# explicit command. Fails silent: offline, no curl or jq, a bad VERSION, any error -> exit 0, no output.
#
# Knobs:
#   KIT_UPDATE_CHECK=0           disable the check
#   KIT_UPDATE_CHECK_URL=URL     where the latest VERSION is fetched (default: raw.githubusercontent.com master);
#                                a file:// URL works, which is how the tests run
#   KIT_UPDATE_STATE_DIR=DIR     cache of {checked_at, latest} (default ~/.claude/dwarves-kit/state/update-notice)
# The network is touched at most once per 24h; between fetches the cached latest is compared.
# The module toggle `update_check` is enforced by hooks/anchor-root.sh, like every non-spine hook.

DEFAULT_URL="https://raw.githubusercontent.com/dwarvesf/dwarves-kit/master/VERSION"
INTERVAL=86400

# is_semver <v>: strict major.minor.patch, digits only.
is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# semver_gt <a> <b>: success when a is newer than b. Both must pass is_semver.
semver_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  [ $((10#$a1)) -ne $((10#$b1)) ] && { [ $((10#$a1)) -gt $((10#$b1)) ]; return; }
  [ $((10#$a2)) -ne $((10#$b2)) ] && { [ $((10#$a2)) -gt $((10#$b2)) ]; return; }
  [ $((10#$a3)) -gt $((10#$b3)) ]
}

# fetch_latest -> stdout: the trimmed remote VERSION, or nothing.
fetch_latest() {
  command -v curl >/dev/null 2>&1 || return 1
  local raw
  raw="$(curl -fsS --max-time 2 "${KIT_UPDATE_CHECK_URL:-$DEFAULT_URL}" 2>/dev/null)" || return 1
  printf '%s' "$raw" | tr -d '[:space:]'
}

main() {
  [ "${KIT_UPDATE_CHECK:-1}" = "0" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local root installed
  root="${CLAUDE_PLUGIN_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}"
  installed="$(tr -d '[:space:]' < "$root/VERSION" 2>/dev/null)"
  is_semver "$installed" || return 0

  local state_dir cache now checked_at latest
  state_dir="${KIT_UPDATE_STATE_DIR:-$HOME/.claude/dwarves-kit/state/update-notice}"
  cache="$state_dir/cache.json"
  now="$(date +%s)"

  checked_at=0; latest=""
  if [ -f "$cache" ]; then
    IFS=$'\t' read -r checked_at latest < <(jq -r '[(.checked_at // 0), (.latest // "")] | @tsv' "$cache" 2>/dev/null)
    case "$checked_at" in ''|*[!0-9]*) checked_at=0 ;; esac
  fi

  if [ $((now - checked_at)) -ge "$INTERVAL" ] || [ "$checked_at" -gt "$now" ]; then
    local fetched
    fetched="$(fetch_latest)"
    is_semver "$fetched" && latest="$fetched"
    # Record the attempt even on failure, so an offline machine retries tomorrow, not every start.
    if mkdir -p "$state_dir" 2>/dev/null; then
      jq -n --argjson t "$now" --arg l "$latest" '{checked_at: $t, latest: $l}' > "$cache.tmp.$$" 2>/dev/null \
        && mv -f "$cache.tmp.$$" "$cache" 2>/dev/null
      rm -f "$cache.tmp.$$" 2>/dev/null
    fi
  fi

  is_semver "$latest" || return 0
  semver_gt "$latest" "$installed" || return 0

  local how
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    how="Run: claude plugin marketplace update dwarves-marketplace && claude plugin update kit@dwarves-marketplace, then restart Claude Code."
  else
    how="Pull the dwarves-kit checkout and re-run install.sh, then restart Claude Code."
  fi
  jq -cn --arg m "dwarves-kit $latest is available (installed: $installed). $how" '{systemMessage: $m}'
}

main </dev/null 2>/dev/null
exit 0

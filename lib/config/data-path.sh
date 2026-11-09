#!/usr/bin/env bash
# data-path.sh -- the single resolver for the kit's runtime data paths (state, cache, config).
#
# WHY: every feature used to hardcode its own default under ~/.claude, ~/.cache or ~/.config, each
# with its own env override. A plugin reinstall can wipe ~/.claude/dwarves-kit, and nobody could
# answer "where is my data". This is the one place the paths live, beside the ledger resolver
# (lib/telemetry/kit-log-dir.sh), which keeps owning the run logs.
#
# Kinds:
#   state   data that is lost for good if deleted: poller cursors, link state, drafts, ledgers
#   cache   safe to delete: throttle stamps, per-session hint timers, a fetched version
#   config  edited by the operator: policy and board files
#
# Resolution for one entry, first hit wins:
#   1. the entry's own env var (HARVEST_STATE_DIR, MONEY_GATE_LOG, ...), when non-empty
#   2. state and cache only: $KIT_DATA_ROOT -> <root>/state/<name> or <root>/cache/<name>. An
#      explicit per-process root beats old data on purpose: a test that pins it must never reach a
#      real host's state. `config data where` warns about old data it hides.
#   3. the LEGACY path, when it exists (a dangling symlink counts) and the path from step 4 or 5
#      holds nothing (missing, or an empty dir). A live host keeps its cursors and link state exactly where
#      they are; nothing moves until the operator runs `config data move --apply`.
#   4. state and cache only: the operator kit.toml key [data] root -> the same <root>/... path.
#      The key is read from the operator file only, and only when it has a [data] section. It sits
#      BELOW step 3: writing the key ahead of the move must not hide a cursor and reset it.
#   5. the default: ${XDG_STATE_HOME:-~/.local/state}/dwarves-kit/<name> (state),
#      ${XDG_CACHE_HOME:-~/.cache}/dwarves-kit/<name> (cache),
#      <operator config dir>/<name> (config; the dir is KIT_CONFIG_OPERATOR or ~/.config/dwarves-kit)
# Config entries skip steps 2 and 4: a root moves state and cache, never the files you edit. A root
# must be an absolute path (a leading ~/ is expanded); a relative one is ignored.
#
# Contract (no output on load, safe under set -euo pipefail):
#   kit_data_path <kind> <name>     -> the path (a dir, or a file for the *.log and *.json entries)
#   kit_data_source <kind> <name>   -> env | root-env | root-key | legacy | default
#   kit_data_entries                -> "<kind> <name>" per line
#   kit_data_env <kind> <name>      -> the entry's own env var, empty when it has none
#   kit_data_legacy <kind> <name>   -> the legacy path
#   kit_data_note <kind> <name>     -> one line: what lives there
# Also runnable: bash data-path.sh {path|source|env|legacy|note|entries} [kind name]
# Returns 1 with a stderr line for an unknown entry.
#
# Hot path: hooks source this at start and call kit_data_path only where they need the dir. The only
# fork is reading the operator kit.toml, and only when that file has a [data] section.
[ -n "${_KIT_DATA_PATH_SOURCED:-}" ] && return 0
_KIT_DATA_PATH_SOURCED=1

_KIT_DATA_SELF="${BASH_SOURCE[0]%/*}"
case "$_KIT_DATA_SELF" in /*) ;; *) _KIT_DATA_SELF="$PWD/$_KIT_DATA_SELF" ;; esac

# Helpers hand results back in globals (_KD_*), never through $(...): a hook pays a fork for each.
# ~ falls back to the password database when HOME is unset (launchd, env -i), as money-gate needs.
_kit_data_sethome() { _KD_HOME="${HOME:-}"; [ -n "$_KD_HOME" ] || _KD_HOME=~; }

# _kit_data_lookup <kind> <name> -- sets _KD_LEGACY _KD_ENV _KD_NOTE; returns 1 when unknown.
# The table: add an entry HERE and in kit_data_entries, nowhere else. board.json and
# hermes-links.json always lived in ~/.config/dwarves-kit; that stays their legacy path for a host
# whose XDG_CONFIG_HOME or operator config dir points somewhere else.
_kit_data_lookup() {
  _kit_data_sethome
  local h="$_KD_HOME"
  _KD_LEGACY=""; _KD_ENV=""; _KD_NOTE=""
  case "$1:$2" in
    state:harvest)
      _KD_LEGACY="$h/.claude/dwarves-kit/state/harvest"; _KD_ENV=HARVEST_STATE_DIR
      _KD_NOTE="transcript harvest: debounce stamps, sweep cursor, ledgers, run reports" ;;
    state:intake-sweep)
      _KD_LEGACY="$h/.claude/dwarves-kit/state/intake-sweep"; _KD_ENV=INTAKE_SWEEP_STATE_DIR
      _KD_NOTE="intake sweep: throttle stamp and the swept-keys cursor" ;;
    state:backlog-sync)
      _KD_LEGACY="$h/.cache/backlog-sync"
      _KD_NOTE="board sync: per-source link state and digest state (losing it duplicates board items)" ;;
    state:intel)
      _KD_LEGACY="$h/.claude/intel"
      _KD_NOTE="weekly digests and audits (session intel, session audit, kit-weekly log)" ;;
    state:skill-proposals)
      _KD_LEGACY="$h/.claude/skill-proposals"; _KD_ENV=SKILL_CURATOR_PROPOSALS_DIR
      _KD_NOTE="skill drafts waiting for /skill-review" ;;
    state:skill-curator)
      _KD_LEGACY="$h/.claude/skill-curator"; _KD_ENV=SKILL_CURATOR_STATE_DIR
      _KD_NOTE="skill curator: ledger, lock, log" ;;
    state:money-gate.log)
      _KD_LEGACY="$h/.claude/logs/money-gate.log"; _KD_ENV=MONEY_GATE_LOG
      _KD_NOTE="money gate: one line per guarded edit" ;;
    cache:backlog-stage)
      _KD_LEGACY="$h/.claude/dwarves-kit/state/backlog-stage"; _KD_ENV=BACKLOG_STAGE_STATE_DIR
      _KD_NOTE="backlog stager: throttle stamp and the child's payload" ;;
    cache:context-hints)
      _KD_LEGACY="$h/.claude/dwarves-kit/state/context-hints"; _KD_ENV=CONTEXT_HINTS_STATE
      _KD_NOTE="context hints: per-session timers" ;;
    cache:update-notice)
      _KD_LEGACY="$h/.claude/dwarves-kit/state/update-notice"; _KD_ENV=KIT_UPDATE_STATE_DIR
      _KD_NOTE="update notice: the latest version seen and when" ;;
    cache:context-budget)
      _KD_LEGACY="$h/.cache/claude-context-budget"
      _KD_NOTE="context budget: last threshold fired per session" ;;
    config:tool-policy.json)
      _KD_LEGACY="$h/.claude/dwarves-kit/tool-policy.json"; _KD_ENV=KIT_TOOL_POLICY
      _KD_NOTE="tool policy: which tool to prefer, ask or allow" ;;
    config:board.json)
      _KD_LEGACY="$h/.config/dwarves-kit/board.json"; _KD_ENV=DWARVES_BOARD_CONFIG
      _KD_NOTE="board: flags the sweep and health commands read first" ;;
    state:hermes-links.json)
      _KD_LEGACY="$h/.config/dwarves-kit/hermes-links.json"; _KD_ENV=DWARVES_HERMES_LINKS
      _KD_NOTE="board hermes: the link record per cluster" ;;
    config:harvest-sweep)
      _KD_LEGACY="$h/.config/harvest-sweep"
      _KD_NOTE="harvest sweep launcher: optional env file and bridge script" ;;
    *) echo "data-path: unknown entry '$1 $2' (see: config data where)" >&2; return 1 ;;
  esac
}

kit_data_entries() {
  printf '%s\n' \
    "state harvest" "state intake-sweep" "state backlog-sync" "state intel" "state hermes-links.json" \
    "state skill-proposals" "state skill-curator" "state money-gate.log" \
    "cache backlog-stage" "cache context-hints" "cache update-notice" "cache context-budget" \
    "config tool-policy.json" "config board.json" "config harvest-sweep"
}

kit_data_legacy() { _kit_data_lookup "$1" "$2" || return 1; printf '%s' "$_KD_LEGACY"; }
kit_data_env()    { _kit_data_lookup "$1" "$2" || return 1; printf '%s' "$_KD_ENV"; }
kit_data_note()   { _kit_data_lookup "$1" "$2" || return 1; printf '%s' "$_KD_NOTE"; }

# _kit_data_expand <value> -- sets _KD_X. A leading ~/ means the home dir, so a kit.toml value reads
# like a shell path. Needs _KD_HOME (set by _kit_data_lookup).
_kit_data_expand() {
  case "$1" in
    "~") _KD_X="$_KD_HOME" ;;
    "~/"*) _KD_X="$_KD_HOME/${1#"~/"}" ;;
    *) _KD_X="$1" ;;
  esac
}

# _kit_data_root_env -- sets _KD_ROOT from KIT_DATA_ROOT, or leaves it empty.
_kit_data_root_env() {
  _KD_ROOT=""; _KD_ROOT_BAD=""
  [ -n "${KIT_DATA_ROOT:-}" ] || return 0
  _kit_data_sethome
  _kit_data_expand "$KIT_DATA_ROOT"
  case "$_KD_X" in /*) _KD_ROOT="$_KD_X" ;; *) _KD_ROOT_BAD="KIT_DATA_ROOT=$KIT_DATA_ROOT" ;; esac
}

# _kit_data_root_key -- sets _KD_ROOT from the operator kit.toml [data] root, or leaves it empty.
_kit_data_root_key() {
  _KD_ROOT=""; _KD_ROOT_BAD=""
  _kit_data_sethome
  # kit-config.sh reads $HOME; with HOME unset (a bare env) the key is not consulted.
  [ -n "${HOME:-}" ] || return 0
  local op="${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$_KD_HOME/.config}/dwarves-kit}/kit.toml"
  [ -f "$op" ] || return 0
  # A hook pays for this on every run: skip the TOML reader unless the file has a [data] section.
  local txt=""
  IFS= read -r -d '' txt < "$op" || true
  case "$txt" in *"[data]"*) ;; *) return 0 ;; esac
  # shellcheck source=lib/config/kit-config.sh
  . "$_KIT_DATA_SELF/kit-config.sh" 2>/dev/null || return 0
  local v; v="$(kit_config_get_root data.root "")"
  [ -n "$v" ] || return 0
  _kit_data_expand "$v"
  case "$_KD_X" in /*) _KD_ROOT="$_KD_X" ;; *) _KD_ROOT_BAD="[data] root = $v" ;; esac
}

# _kit_data_root_override -- sets _KD_ROOT and _KD_ROOT_SRC (root-env | root-key), the env root first.
# For callers that want "the root, if any" (config data where and move).
_kit_data_root_override() {
  _KD_ROOT_SRC=""
  _kit_data_root_env
  if [ -n "$_KD_ROOT" ]; then _KD_ROOT_SRC=root-env; return 0; fi
  local bad="$_KD_ROOT_BAD"
  _kit_data_root_key
  [ -z "$_KD_ROOT" ] || _KD_ROOT_SRC=root-key
  [ -n "$_KD_ROOT_BAD" ] || _KD_ROOT_BAD="$bad"
}

# _kit_data_holds <path> -- true when the path exists and is not an empty directory (a dangling
# symlink counts). An empty target dir someone made by accident must not hide an older path.
_kit_data_holds() {
  [ -L "$1" ] && return 0
  [ -e "$1" ] || return 1
  [ -d "$1" ] || return 0
  local f
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then return 0; fi
  done
  return 1
}

# _kit_data_default <kind> <name> -- sets _KD_DEF, the path a user with no legacy data gets.
_kit_data_default() {
  _kit_data_sethome
  case "$1" in
    state) _KD_DEF="${XDG_STATE_HOME:-$_KD_HOME/.local/state}/dwarves-kit/$2" ;;
    cache) _KD_DEF="${XDG_CACHE_HOME:-$_KD_HOME/.cache}/dwarves-kit/$2" ;;
    config) _KD_DEF="${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$_KD_HOME/.config}/dwarves-kit}/$2" ;;
  esac
}

# _kit_data_resolve <kind> <name> -- sets _KD_PATH and _KD_SRC.
_kit_data_resolve() {
  local kind="$1" name="$2" ev
  _kit_data_lookup "$kind" "$name" || return 1
  _KD_PATH=""; _KD_SRC=""
  if [ -n "$_KD_ENV" ]; then
    ev="${!_KD_ENV:-}"
    if [ -n "$ev" ]; then _kit_data_expand "$ev"; _KD_PATH="$_KD_X"; _KD_SRC=env; return 0; fi
  fi
  local target="" tsrc=default
  if [ "$kind" != config ]; then
    _kit_data_root_env
    if [ -n "$_KD_ROOT" ]; then _KD_PATH="$_KD_ROOT/$kind/$name"; _KD_SRC=root-env; return 0; fi
    _kit_data_root_key
    if [ -n "$_KD_ROOT" ]; then target="$_KD_ROOT/$kind/$name"; tsrc=root-key; fi
  fi
  if [ -z "$target" ]; then _kit_data_default "$kind" "$name"; target="$_KD_DEF"; fi
  # The old path wins while it holds data and the target does not (a dangling symlink counts).
  if [ "$_KD_LEGACY" != "$target" ] && { [ -e "$_KD_LEGACY" ] || [ -L "$_KD_LEGACY" ]; } && ! _kit_data_holds "$target"; then
    _KD_PATH="$_KD_LEGACY"; _KD_SRC=legacy; return 0
  fi
  _KD_PATH="$target"; _KD_SRC="$tsrc"
}

kit_data_path()   { _kit_data_resolve "$1" "$2" || return 1; printf '%s' "$_KD_PATH"; }
kit_data_source() { _kit_data_resolve "$1" "$2" || return 1; printf '%s' "$_KD_SRC"; }

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -euo pipefail
  case "${1:-}" in
    path)    kit_data_path "${2:?kind}" "${3:?name}" ;;
    source)  kit_data_source "${2:?kind}" "${3:?name}" ;;
    env)     kit_data_env "${2:?kind}" "${3:?name}" ;;
    legacy)  kit_data_legacy "${2:?kind}" "${3:?name}" ;;
    note)    kit_data_note "${2:?kind}" "${3:?name}" ;;
    entries) kit_data_entries ;;
    *) echo "usage: data-path.sh {path|source|env|legacy|note} <kind> <name> | entries" >&2; exit 64 ;;
  esac
fi
